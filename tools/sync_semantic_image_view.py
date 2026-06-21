#!/usr/bin/env python3
"""Create a semantic-name image view from naming CSV without renaming source files.

This script creates symlinks named by `recommended_filename` so tracking is easy.
Original files are untouched.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument(
        "--naming-csv",
        default="hsk1_universal_images_semantic_naming_v1_2026-02-15.csv",
        help="CSV with current_filename + recommended_filename",
    )
    p.add_argument(
        "--source-dirs",
        default="backend/static/images,assets/images",
        help="Comma-separated source directories to scan",
    )
    p.add_argument(
        "--out-dir",
        default="images omnis/semantic_named",
        help="Output directory for semantic-name symlinks",
    )
    p.add_argument(
        "--status-csv",
        default="images omnis/semantic_named_status.csv",
        help="Status CSV report path",
    )
    p.add_argument(
        "--summary-json",
        default="images omnis/semantic_named_summary.json",
        help="Summary JSON path",
    )
    p.add_argument(
        "--word-map",
        default="docs/reports/hsk1_public_word_id_map_2026-02-15.csv",
        help="Word public-id mapping CSV for legacy fallback",
    )
    p.add_argument(
        "--links",
        default="docs/reports/hsk1_sense_image_links_v1_2026-02-15.csv",
        help="Sense-image link CSV for legacy fallback",
    )
    p.add_argument(
        "--legacy-match",
        choices=["none", "w", "all"],
        default="w",
        help="Legacy filename fallback: none, word_Wxxxxx only, or word_Wxxxxx + word_N",
    )
    return p.parse_args()


def build_filename_index(source_dirs: list[Path]) -> dict[str, Path]:
    idx: dict[str, Path] = {}
    exts = {".webp", ".png", ".jpg", ".jpeg"}
    for d in source_dirs:
        if not d.exists():
            continue
        for p in d.rglob("*"):
            if not p.is_file() or p.suffix.lower() not in exts:
                continue
            # keep first occurrence for deterministic behavior
            idx.setdefault(p.name, p.resolve())
    return idx


def load_wordpub_to_wordid(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not path.exists():
        return out
    with path.open("r", encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            out[(row.get("word_public_id") or "").strip()] = (row.get("word_id") or "").strip()
    return out


def load_image_to_wordpub(path: Path) -> dict[str, set[str]]:
    out: dict[str, set[str]] = {}
    if not path.exists():
        return out
    with path.open("r", encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            image_id = (row.get("image_id") or "").strip()
            word_pub = (row.get("word_public_id") or "").strip()
            if image_id and word_pub:
                out.setdefault(image_id, set()).add(word_pub)
    return out


def main() -> int:
    args = parse_args()
    naming_csv = Path(args.naming_csv)
    source_dirs = [Path(x.strip()) for x in args.source_dirs.split(",") if x.strip()]
    out_dir = Path(args.out_dir)
    status_csv = Path(args.status_csv)
    summary_json = Path(args.summary_json)
    word_map_csv = Path(args.word_map)
    links_csv = Path(args.links)

    if not naming_csv.exists():
        raise SystemExit(f"Naming CSV not found: {naming_csv}")

    filename_index = build_filename_index(source_dirs)
    wordpub_to_wordid = load_wordpub_to_wordid(word_map_csv)
    image_to_wordpub = load_image_to_wordpub(links_csv)

    # Clean output dir (symlinks/files only)
    out_dir.mkdir(parents=True, exist_ok=True)
    for child in out_dir.iterdir():
        if child.is_symlink() or child.is_file():
            child.unlink()

    rows = list(csv.DictReader(naming_csv.open("r", encoding="utf-8", newline="")))
    report_rows: list[dict[str, str]] = []
    linked = 0
    missing = 0
    already_semantic = 0
    mapped_from_current = 0
    mapped_from_legacy = 0

    pat_w = re.compile(r"^word_(W\d{5})\.webp$", re.IGNORECASE)
    pat_n = re.compile(r"^word_(\d+)\.webp$", re.IGNORECASE)
    existing_word_w = {m.group(1).upper(): p for n, p in filename_index.items() for m in [pat_w.match(n)] if m}
    existing_word_n = {
        int(m.group(1)): p for n, p in filename_index.items() for m in [pat_n.match(n)] if m
    }

    for r in rows:
        image_id = (r.get("image_id") or "").strip()
        current_name = (r.get("current_filename") or "").strip()
        recommended_name = (r.get("recommended_filename") or "").strip()

        source_path: Path | None = None
        source_mode = ""

        if recommended_name and recommended_name in filename_index:
            source_path = filename_index[recommended_name]
            source_mode = "recommended_exists"
            already_semantic += 1
        elif current_name and current_name in filename_index:
            source_path = filename_index[current_name]
            source_mode = "mapped_from_current"
            mapped_from_current += 1
        elif args.legacy_match != "none":
            # fallback: map semantic image_id -> linked word_public_id(s) -> legacy word_Wxxxxx.webp
            for word_pub in image_to_wordpub.get(image_id, set()):
                word_id = wordpub_to_wordid.get(word_pub, "")
                if not word_id:
                    continue
                if word_id in existing_word_w:
                    source_path = existing_word_w[word_id]
                    source_mode = "mapped_from_legacy_word_W"
                    mapped_from_legacy += 1
                    break
                if (
                    args.legacy_match == "all"
                    and word_id.startswith("W")
                    and word_id[1:].isdigit()
                    and int(word_id[1:]) in existing_word_n
                ):
                    source_path = existing_word_n[int(word_id[1:])]
                    source_mode = "mapped_from_legacy_word_N"
                    mapped_from_legacy += 1
                    break
            if source_path is None:
                source_mode = "missing"
                missing += 1
        else:
            source_mode = "missing"
            missing += 1

        if source_path is not None and recommended_name:
            target = out_dir / recommended_name
            # If duplicate recommended names appear, keep first and mark duplicates as skipped
            if not target.exists():
                target.symlink_to(source_path)
                linked += 1
            else:
                source_mode = "duplicate_recommended_name"

        report_rows.append(
            {
                "image_id": image_id,
                "current_filename": current_name,
                "recommended_filename": recommended_name,
                "status": source_mode,
                "source_path": str(source_path) if source_path else "",
            }
        )

    status_csv.parent.mkdir(parents=True, exist_ok=True)
    with status_csv.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(
            f,
            fieldnames=[
                "image_id",
                "current_filename",
                "recommended_filename",
                "status",
                "source_path",
            ],
        )
        w.writeheader()
        w.writerows(report_rows)

    summary = {
        "ok": True,
        "naming_csv": str(naming_csv.resolve()),
        "source_dirs": [str(d.resolve()) for d in source_dirs if d.exists()],
        "out_dir": str(out_dir.resolve()),
        "status_csv": str(status_csv.resolve()),
        "total_rows": len(rows),
        "linked_symlinks": linked,
        "already_semantic": already_semantic,
        "mapped_from_current": mapped_from_current,
        "mapped_from_legacy": mapped_from_legacy,
        "missing": missing,
        "note": "Original files were not renamed. This is a semantic-name symlink view.",
    }
    summary_json.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
