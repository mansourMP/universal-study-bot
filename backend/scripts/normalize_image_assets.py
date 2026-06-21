#!/usr/bin/env python3
"""Normalize raw images into assets/images/word_{id}.webp (deterministic)."""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass, asdict
from datetime import date
from pathlib import Path
from typing import Dict, List, Tuple

try:
    from PIL import Image, ImageStat
except Exception as exc:  # pragma: no cover
    Image = None
    ImageStat = None


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _load_manifest(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _variance(img: Image.Image) -> float:
    stat = ImageStat.Stat(img)
    # Use grayscale variance
    if img.mode != "L":
        img = img.convert("L")
        stat = ImageStat.Stat(img)
    return stat.var[0] if stat.var else 0.0


def _trim_edges(img: Image.Image, max_trim_ratio: float = 0.2, threshold: float = 4.0) -> Tuple[Image.Image, Tuple[int, int, int, int], List[str]]:
    warnings: List[str] = []
    w, h = img.size
    left = top = 0
    right = w
    bottom = h
    max_trim_w = int(w * max_trim_ratio)
    max_trim_h = int(h * max_trim_ratio)
    step = max(2, min(w, h) // 200)  # deterministic small step

    def edge_var(box: Tuple[int, int, int, int]) -> float:
        crop = img.crop(box)
        return _variance(crop)

    trimmed = False
    # Trim top
    while top < max_trim_h:
        var = edge_var((left, top, right, min(top + step, bottom)))
        if var > threshold:
            break
        top += step
        trimmed = True
    # Trim bottom
    while (h - bottom) < max_trim_h:
        var = edge_var((left, max(bottom - step, top), right, bottom))
        if var > threshold:
            break
        bottom -= step
        trimmed = True
    # Trim left
    while left < max_trim_w:
        var = edge_var((left, top, min(left + step, right), bottom))
        if var > threshold:
            break
        left += step
        trimmed = True
    # Trim right
    while (w - right) < max_trim_w:
        var = edge_var((max(right - step, left), top, right, bottom))
        if var > threshold:
            break
        right -= step
        trimmed = True

    # Ensure at least 80% remains
    if (right - left) < int(w * 0.8) or (bottom - top) < int(h * 0.8):
        warnings.append("trim_skipped_too_aggressive")
        return img, (0, 0, w, h), warnings

    if trimmed:
        return img.crop((left, top, right, bottom)), (left, top, right, bottom), warnings
    return img, (0, 0, w, h), warnings


def _center_crop_square(img: Image.Image) -> Tuple[Image.Image, Tuple[int, int, int, int]]:
    w, h = img.size
    size = min(w, h)
    left = (w - size) // 2
    top = (h - size) // 2
    right = left + size
    bottom = top + size
    return img.crop((left, top, right, bottom)), (left, top, right, bottom)


@dataclass
class ItemReport:
    concept_id: int
    input_path: str
    input_size: Tuple[int, int]
    trim_box: Tuple[int, int, int, int]
    crop_box: Tuple[int, int, int, int]
    output_size: Tuple[int, int]
    output_path: str
    warnings: List[str]


def main() -> int:
    parser = argparse.ArgumentParser(description="Normalize raw images for HSK1 pilot")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--out-dir", default="assets/images")
    parser.add_argument("--size", type=int, default=768)
    parser.add_argument("--quality", type=int, default=85)
    parser.add_argument("--trim-edges", action="store_true", default=True)
    parser.add_argument("--no-trim-edges", action="store_true", default=False)
    parser.add_argument("--square-crop", default="center")
    args = parser.parse_args()

    if Image is None:
        print("Pillow not available. Install pillow to run this script.")
        return 1

    repo_root = _repo_root()
    manifest_path = repo_root / args.manifest
    manifest = _load_manifest(manifest_path)
    items = manifest.get("items", []) if isinstance(manifest, dict) else []

    out_dir = repo_root / args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    processed = 0
    skipped = 0
    failed = 0
    reports: List[ItemReport] = []

    for item in items:
        cid = item.get("concept_id")
        raw_path = item.get("raw_path")
        if not cid or not raw_path:
            skipped += 1
            continue
        src = repo_root / raw_path
        if not src.exists():
            failed += 1
            continue

        try:
            img = Image.open(src).convert("RGB")
        except Exception:
            failed += 1
            continue

        warnings: List[str] = []
        trim_box = (0, 0, *img.size)
        if args.no_trim_edges:
            trimmed = img
        else:
            trimmed, trim_box, warns = _trim_edges(img)
            warnings.extend(warns)

        if args.square_crop != "center":
            warnings.append("square_crop_non_center_not_supported")
        cropped, crop_box = _center_crop_square(trimmed)
        resized = cropped.resize((args.size, args.size), Image.LANCZOS)

        out_path = out_dir / f"word_{cid}.webp"
        resized.save(out_path, format="WEBP", quality=args.quality, method=6)

        processed += 1
        reports.append(
            ItemReport(
                concept_id=int(cid),
                input_path=str(src),
                input_size=img.size,
                trim_box=trim_box,
                crop_box=crop_box,
                output_size=resized.size,
                output_path=str(out_path),
                warnings=warnings,
            )
        )

    report = {
        "date": date.today().isoformat(),
        "processed": processed,
        "skipped": skipped,
        "failed": failed,
        "items": [asdict(r) for r in reports],
    }

    report_path = repo_root / "docs" / "reports" / f"image_asset_build_{date.today().isoformat()}.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

    print(f"Processed: {processed}")
    print(f"Skipped: {skipped}")
    print(f"Failed: {failed}")
    print(f"Wrote {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
