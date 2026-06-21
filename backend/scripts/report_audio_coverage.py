#!/usr/bin/env python3
"""Report audio coverage for learning_path concepts.

Strategy (matches runtime):
1) backend/static/audio/word_{concept_id}.mp3
2) backend/content/audio_map.json overrides (local files only)
3) /api/v2/audio/{concept_id} TTS endpoint (not counted as local file coverage)
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import sqlite3
import json


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _connect(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    return conn


def _collect_concept_ids(conn: sqlite3.Connection) -> list[str]:
    rows = conn.execute("SELECT DISTINCT concept_id FROM unit_concepts").fetchall()
    return [str(r[0]) for r in rows]


def _load_audio_map(map_path: Path) -> dict:
    if map_path.exists():
        try:
            data = json.loads(map_path.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                return {str(k): str(v) for k, v in data.items()}
        except Exception:
            return {}
    return {}


def _resolve_local_file(repo_root: Path, mapped: str) -> Path:
    file_path = Path(mapped)
    if not file_path.is_absolute():
        file_path = repo_root / mapped.lstrip("/")
    return file_path


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description="Report audio coverage for learning_path concepts")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--only-ids", help="Path to newline-delimited concept_ids to include")
    parser.add_argument("--strict", action="store_true", help="Exit non-zero if missing or placeholder audio exists")
    args = parser.parse_args()

    repo_root = _repo_root()
    db_path = repo_root / args.db
    audio_dir = repo_root / "backend" / "static" / "audio"
    map_path = repo_root / "backend" / "content" / "audio_map.json"
    placeholder_path = audio_dir / "_placeholder_template.mp3"

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

    audio_map = _load_audio_map(map_path)

    matched = 0
    matched_static = 0
    matched_map = 0
    placeholder_hash = _sha256(placeholder_path) if placeholder_path.exists() else None
    placeholder_count = 0
    non_placeholder_count = 0
    missing = []

    for cid in concept_ids:
        static_path = audio_dir / f"word_{cid}.mp3"
        if static_path.exists():
            matched += 1
            matched_static += 1
            if placeholder_hash and _sha256(static_path) == placeholder_hash:
                placeholder_count += 1
            else:
                non_placeholder_count += 1
            continue

        mapped = audio_map.get(cid)
        if mapped:
            mapped_path = _resolve_local_file(repo_root, mapped)
            if mapped_path.exists():
                matched += 1
                matched_map += 1
                if placeholder_hash and _sha256(mapped_path) == placeholder_hash:
                    placeholder_count += 1
                else:
                    non_placeholder_count += 1
                continue
        missing.append(cid)

    print("--- Audio Coverage Report ---")
    print(f"Concepts (unit_concepts distinct): {len(concept_ids)}")
    print("Runtime resolution order: static/audio/word_{concept_id}.mp3 -> audio_map.json override -> TTS endpoint")
    print(f"Overrides count (audio_map.json): {len(audio_map)}")
    print(f"Matched concept IDs: {matched}")
    print(f"Matched static files: {matched_static}")
    print(f"Matched overrides: {matched_map}")
    print(f"Placeholder audio count: {placeholder_count}")
    print(f"Non-placeholder audio count: {non_placeholder_count}")
    print(f"Missing mapped IDs: {len(missing)}")

    if missing:
        print("Top 50 missing IDs:")
        for cid in missing[:50]:
            print(cid)

    if args.strict and (missing or placeholder_count):
        print("ERROR: Missing or placeholder audio detected in strict mode.")
        return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
