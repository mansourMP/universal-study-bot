#!/usr/bin/env python3
"""Generate a todo pack for concepts missing usage exercises."""

from __future__ import annotations

import argparse
import json
import sqlite3
from datetime import date
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _connect(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    return conn


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate usage sentence todo list")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--out-dir", default="docs/reports")
    parser.add_argument(
        "--unit-like",
        default="%",
        help="SQL LIKE pattern for unit_id scope (default: all units, e.g. UNIT_HSK1_%%)",
    )
    args = parser.parse_args()

    repo_root = _repo_root()
    db_path = repo_root / args.db
    out_dir = repo_root / args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1

    conn = _connect(db_path)
    try:
        rows = conn.execute(
            """
            SELECT DISTINCT c.id as concept_id, c.text, c.pinyin, c.meaning
            FROM unit_concepts uc
            JOIN concepts c ON c.id = uc.concept_id
            WHERE uc.unit_id LIKE ?
              AND uc.concept_id NOT IN (
                SELECT DISTINCT word_id
                FROM word_exercises
                WHERE exercise_type IN ('sentence_fill', 'collocation_pick')
            )
            ORDER BY CAST(c.id AS INTEGER)
            """
            ,
            (args.unit_like,),
        ).fetchall()
    finally:
        conn.close()

    date_str = date.today().isoformat()
    txt_path = out_dir / f"missing_usage_{date_str}.txt"
    json_path = out_dir / f"usage_sentence_todo_{date_str}.json"

    missing_ids = [str(r[0]) for r in rows]
    txt_path.write_text("\n".join(missing_ids) + ("\n" if missing_ids else ""), encoding="utf-8")

    payload = {
        "date": date_str,
        "scope_unit_like": args.unit_like,
        "count": len(rows),
        "items": [
            {
                "concept_id": str(r[0]),
                "hanzi": r[1],
                "pinyin": r[2],
                "meaning": r[3],
            }
            for r in rows
        ],
    }
    json_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"Wrote {txt_path}")
    print(f"Wrote {json_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
