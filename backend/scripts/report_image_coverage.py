#!/usr/bin/env python3
"""Report image coverage for learning_path concepts.

Resolution order mirrors runtime:
1) backend/static/images/word_{concept_id}.webp
2) backend/content/image_map.json overrides (local files only)
3) /api/v2/image/{concept_id} endpoint (not counted as local file coverage)
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sqlite3


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _connect(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    return conn


def _collect_concept_ids(conn: sqlite3.Connection) -> list[str]:
    rows = conn.execute("SELECT DISTINCT concept_id FROM unit_concepts").fetchall()
    return [str(r[0]) for r in rows]


def _load_image_map(map_path: Path) -> dict:
    if map_path.exists():
        try:
            data = json.loads(map_path.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                return {str(k): str(v) for k, v in data.items()}
        except Exception:
            return {}
    return {}


def _resolve_local_path(mapped: str, repo_root: Path) -> Path | None:
    mapped_path = Path(mapped)
    if mapped_path.is_absolute():
        return mapped_path
    if mapped.startswith("/static/"):
        return repo_root / mapped.lstrip("/")
    if mapped.startswith("static/"):
        return repo_root / mapped
    return None


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def _webp_dimensions(path: Path) -> tuple[int, int] | None:
    data = path.read_bytes()
    if len(data) < 16 or data[:4] != b"RIFF" or data[8:12] != b"WEBP":
        return None
    chunk = data[12:16]
    if chunk == b"VP8X" and len(data) >= 30:
        w = int.from_bytes(data[24:27], "little") + 1
        h = int.from_bytes(data[27:30], "little") + 1
        return w, h
    if chunk == b"VP8L" and len(data) >= 25:
        b0, b1, b2, b3 = data[21:25]
        w = (b0 | ((b1 & 0x3F) << 8)) + 1
        h = (((b1 & 0xC0) >> 6) | (b2 << 2) | ((b3 & 0x0F) << 10)) + 1
        return w, h
    return None


def _is_placeholder(path: Path, placeholder_hash: str | None) -> bool:
    if placeholder_hash and _sha256(path) == placeholder_hash:
        return True
    dims = _webp_dimensions(path)
    return dims == (1, 1)


def main() -> int:
    parser = argparse.ArgumentParser(description="Report image coverage for learning_path concepts")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--only-ids", help="Path to newline-delimited concept_ids to include")
    parser.add_argument("--strict", action="store_true", help="Exit non-zero if missing or placeholder images exist")
    args = parser.parse_args()

    repo_root = _repo_root()
    db_path = repo_root / args.db
    img_dir = repo_root / "backend" / "static" / "images"
    map_path = repo_root / "backend" / "content" / "image_map.json"
    placeholder_path = img_dir / "_placeholder_1x1.webp"

    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1

    conn = _connect(db_path)
    try:
        concept_ids = _collect_concept_ids(conn)
    finally:
        conn.close()

    if args.only_ids:
        only_path = repo_root / args.only_ids
        if not only_path.exists():
            print(f"only-ids file not found: {only_path}")
            return 1
        allowed = {
            line.strip()
            for line in only_path.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.strip().startswith("#")
        }
        concept_ids = [cid for cid in concept_ids if cid in allowed]

    image_map = _load_image_map(map_path)
    matched = 0
    matched_static = 0
    matched_overrides = 0
    placeholder_hash = _sha256(placeholder_path) if placeholder_path.exists() else None
    placeholder_count = 0
    non_placeholder_count = 0
    missing = []

    for cid in concept_ids:
        matched_any = False
        static_path = img_dir / f"word_{cid}.webp"
        if static_path.exists():
            matched += 1
            matched_static += 1
            matched_any = True
            if _is_placeholder(static_path, placeholder_hash):
                placeholder_count += 1
            else:
                non_placeholder_count += 1
            continue

        mapped = image_map.get(cid)
        if mapped:
            mapped_path = _resolve_local_path(mapped, repo_root)
            if mapped_path and mapped_path.exists():
                matched += 1
                matched_overrides += 1
                matched_any = True
                if _is_placeholder(mapped_path, placeholder_hash):
                    placeholder_count += 1
                else:
                    non_placeholder_count += 1
                continue
        if not matched_any:
            missing.append(cid)

    print("--- Image Coverage Report ---")
    print(f"Concepts (unit_concepts distinct): {len(concept_ids)}")
    print("Runtime resolution order: static/images/word_{concept_id}.webp -> image_map.json override -> image endpoint")
    print(f"Overrides count (image_map.json): {len(image_map)}")
    print(f"Matched concept IDs: {matched}")
    print(f"Matched static files: {matched_static}")
    print(f"Matched overrides: {matched_overrides}")
    print(f"Placeholder image count: {placeholder_count}")
    print(f"Non-placeholder image count: {non_placeholder_count}")
    print(f"Missing image IDs: {len(missing)}")

    if missing:
        print("Top 50 missing IDs:")
        for cid in missing[:50]:
            print(cid)

    if args.strict and (missing or placeholder_count):
        print("ERROR: Missing or placeholder images detected in strict mode.")
        return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
