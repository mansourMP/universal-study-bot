#!/usr/bin/env python3
"""Verify HSK1 pilot images exist and are valid WebP with exact size."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import List

try:
    from PIL import Image
except Exception:
    Image = None


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _load_ids(path: Path) -> List[str]:
    ids: List[str] = []
    if not path.exists():
        return ids
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        ids.append(line)
    return ids


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify HSK1 pilot images are ready")
    parser.add_argument("--ids", default="docs/pilot/hsk1_pilot_ids.txt")
    parser.add_argument("--size", type=int, default=768)
    parser.add_argument("--dir", default="assets/images")
    args = parser.parse_args()

    if Image is None:
        print("Pillow not available. Install pillow to run this script.")
        return 1

    repo_root = _repo_root()
    ids_path = repo_root / args.ids
    ids = _load_ids(ids_path)
    if not ids:
        print(f"No IDs found at {ids_path}")
        return 1

    base_dir = repo_root / args.dir
    missing: List[str] = []
    bad_format: List[str] = []
    bad_size: List[str] = []

    for cid in ids:
        path = base_dir / f"word_{cid}.webp"
        if not path.exists():
            missing.append(cid)
            continue
        try:
            with Image.open(path) as img:
                if img.format != "WEBP":
                    bad_format.append(cid)
                if img.size != (args.size, args.size):
                    bad_size.append(cid)
        except Exception:
            bad_format.append(cid)

    total = len(ids)
    ok = total - len(missing) - len(bad_format) - len(bad_size)
    print(f"Total IDs: {total}")
    print(f"OK: {ok}")
    print(f"Missing: {len(missing)}")
    print(f"Bad format: {len(bad_format)}")
    print(f"Bad size: {len(bad_size)}")

    if missing:
        print("Missing IDs:", ",".join(missing[:50]))
    if bad_format:
        print("Bad format IDs:", ",".join(bad_format[:50]))
    if bad_size:
        print("Bad size IDs:", ",".join(bad_size[:50]))

    if missing or bad_format or bad_size:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
