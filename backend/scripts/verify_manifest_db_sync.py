#!/usr/bin/env python3
"""Verify manifest word_ids match unit_concepts in learning_path.db."""

from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _connect(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    return conn


def _load_manifest(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def _manifest_word_ids(manifest: dict) -> set[str]:
    words: set[str] = set()
    for realm in manifest.get("realms", {}).values():
        for unit in realm.get("units", []):
            for lesson in unit.get("lessons", []):
                for wid in lesson.get("word_ids", []):
                    words.add(str(wid))
    return words


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify manifest and DB unit_concepts sync")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--manifest", default="backend/content/paths/zh_standard.json")
    parser.add_argument("--limit", type=int, default=20)
    args = parser.parse_args()

    repo_root = _repo_root()
    db_path = repo_root / args.db
    manifest_path = repo_root / args.manifest

    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1
    if not manifest_path.exists():
        print(f"Manifest not found: {manifest_path}")
        return 1

    manifest = _load_manifest(manifest_path)
    manifest_ids = _manifest_word_ids(manifest)

    conn = _connect(db_path)
    try:
        rows = conn.execute("SELECT DISTINCT concept_id FROM unit_concepts").fetchall()
    finally:
        conn.close()

    db_ids = {str(r[0]) for r in rows}

    missing_in_db = sorted(manifest_ids - db_ids)
    extra_in_db = sorted(db_ids - manifest_ids)

    print("--- Manifest/DB Sync Check ---")
    print(f"Manifest word_ids: {len(manifest_ids)}")
    print(f"DB unit_concepts distinct: {len(db_ids)}")
    print(f"Missing in DB: {len(missing_in_db)}")
    print(f"Extra in DB: {len(extra_in_db)}")

    if missing_in_db:
        print(f"Top {min(args.limit, len(missing_in_db))} missing IDs:")
        for wid in missing_in_db[: args.limit]:
            print(wid)

    if extra_in_db:
        print(f"Top {min(args.limit, len(extra_in_db))} extra IDs:")
        for wid in extra_in_db[: args.limit]:
            print(wid)

    if missing_in_db or extra_in_db:
        return 1

    print("✅ Manifest and DB are in sync")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
