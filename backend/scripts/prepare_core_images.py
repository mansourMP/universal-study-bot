#!/usr/bin/env python3
"""Map backend/static/images/core/*.png to assets/images/word_{concept_id}.webp.

Uses backend/content/core_visuals.json text -> concepts.text lookup.
Outputs a mapping report and updates assets/content_pack_v1.json (images only).
"""

from __future__ import annotations

import json
import sqlite3
import subprocess
import shutil
from datetime import date
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _concept_sort_key(raw: str) -> tuple[int, str]:
    cid = str(raw or "").strip()
    digits = "".join(ch for ch in cid if ch.isdigit())
    if digits:
        return (int(digits), cid)
    return (10**12, cid)


def _connect(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    return conn


def _load_json(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _convert_png_to_webp(src: Path, dst: Path) -> tuple[bool, str]:
    # Prefer ffmpeg when webp encoder is available.
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg:
        ffmpeg_cmd = [
            ffmpeg,
            "-y",
            "-i",
            str(src),
            "-vcodec",
            "libwebp",
            "-lossless",
            "1",
            str(dst),
        ]
        result = subprocess.run(ffmpeg_cmd, capture_output=True, text=True)
        if result.returncode == 0:
            return True, ""
        err = (result.stderr or "").strip()
        if "Unknown encoder 'libwebp'" not in err:
            return False, err

    # Fallback to cwebp if ffmpeg lacks libwebp.
    cwebp = shutil.which("cwebp")
    if cwebp:
        cwebp_cmd = [cwebp, "-quiet", "-lossless", str(src), "-o", str(dst)]
        result = subprocess.run(cwebp_cmd, capture_output=True, text=True)
        if result.returncode == 0:
            return True, ""
        return False, (result.stderr or result.stdout or "").strip()

    return False, "Neither ffmpeg(libwebp) nor cwebp is available for webp conversion."


def main() -> int:
    repo_root = _repo_root()
    core_path = repo_root / "backend" / "content" / "core_visuals.json"
    db_path = repo_root / "backend" / "learning_path.db"
    core_dir = repo_root / "backend" / "static" / "images" / "core"
    out_dir = repo_root / "assets" / "images"
    out_dir.mkdir(parents=True, exist_ok=True)

    if not core_path.exists():
        print(f"core_visuals.json not found: {core_path}")
        return 1
    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1

    core_items = json.loads(core_path.read_text(encoding="utf-8"))
    if not isinstance(core_items, list):
        print("core_visuals.json is not a list")
        return 1

    conn = _connect(db_path)
    try:
        text_to_ids = {}
        rows = conn.execute("SELECT id, text FROM concepts").fetchall()
        for row in rows:
            text_to_ids.setdefault(row[1], []).append(str(row[0]))
    finally:
        conn.close()

    report_lines = [f"# Core image mapping ({date.today().isoformat()})", ""]
    mapped = {}
    unmapped = []

    for item in core_items:
        key = item.get("id")
        text = item.get("text")
        if not key or not text:
            continue
        ids = text_to_ids.get(text, [])
        if not ids:
            unmapped.append(key)
            report_lines.append(f"- {key}: text '{text}' not found in concepts")
            continue
        concept_id = sorted(ids, key=_concept_sort_key)[0]
        src = core_dir / f"{key}.png"
        if not src.exists():
            report_lines.append(f"- {key}: source image missing {src}")
            continue
        dst = out_dir / f"word_{concept_id}.webp"
        ok, err = _convert_png_to_webp(src, dst)
        if not ok:
            report_lines.append(f"- {key}: conversion failed ({err})")
            continue
        mapped[concept_id] = f"assets/images/word_{concept_id}.webp"
        report_lines.append(f"- {key}: {text} -> concept_id {concept_id}")

    # Update content_pack_v1.json (images only)
    manifest_path = repo_root / "assets" / "content_pack_v1.json"
    manifest = _load_json(manifest_path)
    manifest.setdefault("version", "v1")
    manifest.setdefault("audio", {})
    manifest.setdefault("images", {})
    for cid, path in mapped.items():
        manifest["images"][cid] = path
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    report_path = repo_root / "docs" / "reports" / f"core_image_mapping_{date.today().isoformat()}.md"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text("\n".join(report_lines) + "\n", encoding="utf-8")

    print(f"Mapped images: {len(mapped)}")
    if unmapped:
        print(f"Unmapped entries: {len(unmapped)}")
    print(f"Wrote {manifest_path}")
    print(f"Wrote {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
