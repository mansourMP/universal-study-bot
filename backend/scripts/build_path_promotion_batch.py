#!/usr/bin/env python3
"""Build a promotion batch from non-path concepts.

Prioritizes candidates with:
1) existing exercises
2) existing senses
3) Chinese surface forms (default)
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import re
import sqlite3
from pathlib import Path


_CJK_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff]")


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _looks_chinese(text: str) -> bool:
    return bool(_CJK_RE.search(text or ""))


def main() -> int:
    parser = argparse.ArgumentParser(description="Build path promotion batch")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--size", type=int, default=300)
    parser.add_argument("--min-unit", type=int, default=1)
    parser.add_argument("--max-unit", type=int, default=48)
    parser.add_argument("--allow-non-chinese", action="store_true")
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
        else repo_root / "docs" / "reports" / f"path_promotion_batch_{dt.date.today().isoformat()}.csv"
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
            ORDER BY
              COALESCE(we.exercise_count, 0) DESC,
              COALESCE(cs.sense_count, 0) DESC,
              c.id ASC
            """,
            (args.min_unit, args.max_unit),
        ).fetchall()

        filtered = []
        for r in rows:
            text = r["text"] or ""
            if not args.allow_non_chinese and not _looks_chinese(text):
                continue
            filtered.append(r)
            if len(filtered) >= args.size:
                break

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
                    "ready_score",
                ]
            )
            for r in filtered:
                ex_count = int(r["exercise_count"])
                sense_count = int(r["sense_count"])
                ready_score = ex_count * 10 + sense_count
                writer.writerow(
                    [
                        r["concept_id"],
                        r["text"],
                        r["pinyin"] or "",
                        r["meaning"] or "",
                        ex_count,
                        sense_count,
                        ready_score,
                    ]
                )

        print(f"Wrote {out_path}")
        print(f"Rows: {len(filtered)}")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
