#!/usr/bin/env python3
"""Export vocabulary that exists in concepts but is not yet in active path units."""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import sqlite3
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def main() -> int:
    parser = argparse.ArgumentParser(description="Export concepts outside active path")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--min-unit", type=int, default=1)
    parser.add_argument("--max-unit", type=int, default=48)
    parser.add_argument("--out", default="")
    args = parser.parse_args()

    repo_root = _repo_root()
    db_path = repo_root / args.db
    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1

    out_path = (
        Path(args.out)
        if args.out
        else repo_root / "docs" / "reports" / f"outside_path_words_{dt.date.today().isoformat()}.csv"
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        rows = conn.execute(
            """
            SELECT
              c.id AS concept_id,
              c.text,
              c.pinyin,
              c.meaning,
              COALESCE(we.exercise_count, 0) AS exercise_count,
              COALESCE(cs.sense_count, 0) AS sense_count
            FROM concepts c
            LEFT JOIN (
              SELECT word_id, COUNT(*) AS exercise_count
              FROM word_exercises
              GROUP BY word_id
            ) we ON we.word_id = c.id
            LEFT JOIN (
              SELECT concept_id, COUNT(*) AS sense_count
              FROM concept_senses
              GROUP BY concept_id
            ) cs ON cs.concept_id = c.id
            WHERE c.id NOT IN (
              SELECT DISTINCT concept_id
              FROM unit_concepts
              WHERE unit_id GLOB '[0-9]*'
                AND CAST(unit_id AS INTEGER) BETWEEN ? AND ?
            )
            ORDER BY exercise_count DESC, c.id ASC
            """,
            (args.min_unit, args.max_unit),
        ).fetchall()

        with out_path.open("w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(
                [
                    "concept_id",
                    "text",
                    "pinyin",
                    "meaning",
                    "exercise_count",
                    "sense_count",
                    "has_exercises",
                    "has_senses",
                ]
            )
            for r in rows:
                ex_count = int(r["exercise_count"])
                sense_count = int(r["sense_count"])
                writer.writerow(
                    [
                        r["concept_id"],
                        r["text"],
                        r["pinyin"] or "",
                        r["meaning"] or "",
                        ex_count,
                        sense_count,
                        1 if ex_count > 0 else 0,
                        1 if sense_count > 0 else 0,
                    ]
                )

        print(f"Wrote {out_path}")
        print(f"Rows: {len(rows)}")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
