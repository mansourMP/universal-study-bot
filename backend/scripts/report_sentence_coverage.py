#!/usr/bin/env python3
"""Report sentence exercise coverage (usage types) by concept."""

from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path

USAGE_TYPES = ("sentence_fill", "collocation_pick")


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _connect(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    return conn


def main() -> int:
    parser = argparse.ArgumentParser(description="Report sentence/usage exercise coverage")
    parser.add_argument("--db", default="backend/learning_path.db")
    args = parser.parse_args()

    repo_root = _repo_root()
    db_path = repo_root / args.db

    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1

    conn = _connect(db_path)
    try:
        total = conn.execute("SELECT COUNT(DISTINCT concept_id) FROM unit_concepts").fetchone()[0]
        rows = conn.execute(
            """
            SELECT COUNT(DISTINCT we.word_id)
            FROM word_exercises we
            JOIN unit_concepts uc ON uc.concept_id = we.word_id
            WHERE we.exercise_type IN (?, ?)
            """,
            USAGE_TYPES
        ).fetchone()
        covered = rows[0] if rows else 0
    finally:
        conn.close()

    print("--- Sentence Coverage Report ---")
    print(f"Concepts (unit_concepts distinct): {total}")
    print(f"Concepts with usage exercises ({USAGE_TYPES[0]}, {USAGE_TYPES[1]}): {covered}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
