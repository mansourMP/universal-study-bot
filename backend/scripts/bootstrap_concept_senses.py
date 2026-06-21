#!/usr/bin/env python3
"""Bootstrap concept_senses from legacy concepts.meaning.

Usage:
  python3 backend/scripts/bootstrap_concept_senses.py
  python3 backend/scripts/bootstrap_concept_senses.py --db backend/learning_path.db
  python3 backend/scripts/bootstrap_concept_senses.py --dry-run
"""

from __future__ import annotations

import argparse
import importlib.util
import sqlite3
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def main() -> int:
    parser = argparse.ArgumentParser(description="Bootstrap concept senses")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    repo_root = _repo_root()
    module_path = repo_root / "backend" / "learning_path" / "sense_store.py"
    spec = importlib.util.spec_from_file_location("sense_store_runtime", module_path)
    if spec is None or spec.loader is None:
        print(f"Unable to load module: {module_path}")
        return 1
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    bootstrap_concept_senses = module.bootstrap_concept_senses
    ensure_sense_schema = module.ensure_sense_schema
    split_glosses = module.split_glosses

    db_path = repo_root / args.db
    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        ensure_sense_schema(conn)
        total_before = conn.execute("SELECT COUNT(*) FROM concept_senses").fetchone()[0]
        missing_concepts = conn.execute(
            """
            SELECT COUNT(*)
            FROM concepts c
            LEFT JOIN concept_senses cs ON cs.concept_id = c.id
            WHERE cs.concept_id IS NULL
            """
        ).fetchone()[0]

        print(f"DB: {db_path}")
        print(f"Senses before: {total_before}")
        print(f"Concepts without senses: {missing_concepts}")

        if args.dry_run:
            sample = conn.execute(
                """
                SELECT id, text, meaning
                FROM concepts
                WHERE meaning IS NOT NULL AND TRIM(meaning) != ''
                ORDER BY id ASC
                LIMIT 12
                """
            ).fetchall()
            print("\nSample split preview:")
            for row in sample:
                glosses = split_glosses(row["meaning"])
                print(f"- {row['id']} {row['text']}: {glosses[:4]}")
            return 0

        inserted = bootstrap_concept_senses(conn)
        total_after = conn.execute("SELECT COUNT(*) FROM concept_senses").fetchone()[0]
        print(f"Inserted rows: {inserted}")
        print(f"Senses after: {total_after}")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
