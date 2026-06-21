#!/usr/bin/env python3
"""Repair `word_exercises.word_id` entries missing in `concepts`.

This keeps exercise data and canonical concept data consistent without
touching unit mappings. It reconstructs minimal concept rows from exercise
payloads (front/word/correct + pinyin/back).
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
from pathlib import Path
from typing import Dict, Optional


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _extract_fields(payload: Dict) -> Dict[str, Optional[str]]:
    if not isinstance(payload, dict):
        return {"text": None, "pinyin": None, "meaning": None}

    text = None
    pinyin = None
    meaning = None

    if isinstance(payload.get("front"), str) and payload["front"].strip():
        text = payload["front"].strip()
    if isinstance(payload.get("word"), str) and payload["word"].strip():
        text = text or payload["word"].strip()
    if isinstance(payload.get("correct"), str) and payload["correct"].strip():
        text = text or payload["correct"].strip()

    if isinstance(payload.get("pinyin"), str) and payload["pinyin"].strip():
        pinyin = payload["pinyin"].strip()

    if isinstance(payload.get("back"), str) and payload["back"].strip():
        meaning = payload["back"].strip()
    if isinstance(payload.get("translation"), str) and payload["translation"].strip():
        meaning = meaning or payload["translation"].strip()

    return {"text": text, "pinyin": pinyin, "meaning": meaning}


def _load_sense_helpers():
    import importlib.util

    module_path = _repo_root() / "backend" / "learning_path" / "sense_store.py"
    spec = importlib.util.spec_from_file_location("sense_store_runtime", module_path)
    if spec is None or spec.loader is None:
        return None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _contains_cjk(value: str) -> bool:
    return bool(re.search(r"[\u3400-\u4dbf\u4e00-\u9fff]", value))


def main() -> int:
    parser = argparse.ArgumentParser(description="Repair concepts missing for exercise word_ids")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--limit", type=int, default=0, help="Limit orphan IDs (0 = no limit)")
    parser.add_argument(
        "--include-non-cjk",
        action="store_true",
        help="Include non-CJK terms (disabled by default to keep zh DB clean)",
    )
    args = parser.parse_args()

    db_path = _repo_root() / args.db
    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        orphan_rows = conn.execute(
            """
            SELECT DISTINCT w.word_id
            FROM word_exercises w
            LEFT JOIN concepts c ON c.id = w.word_id
            WHERE c.id IS NULL
            ORDER BY w.word_id
            """
        ).fetchall()
        orphan_ids = [str(r["word_id"]) for r in orphan_rows]
        if args.limit > 0:
            orphan_ids = orphan_ids[: args.limit]

        print(f"Orphan word_ids: {len(orphan_ids)}")
        if not orphan_ids:
            return 0

        to_insert = []
        unresolved = []
        skipped_non_cjk = []
        for wid in orphan_ids:
            ex_rows = conn.execute(
                """
                SELECT exercise_type, payload
                FROM word_exercises
                WHERE word_id = ?
                ORDER BY
                  CASE exercise_type
                    WHEN 'flashcard' THEN 1
                    WHEN 'tone_select' THEN 2
                    WHEN 'sentence_fill' THEN 3
                    ELSE 9
                  END, id ASC
                """,
                (wid,),
            ).fetchall()

            text = None
            pinyin = None
            meaning = None
            for ex in ex_rows:
                try:
                    payload = json.loads(ex["payload"]) if ex["payload"] else {}
                except Exception:
                    payload = {}
                fields = _extract_fields(payload)
                text = text or fields["text"]
                pinyin = pinyin or fields["pinyin"]
                meaning = meaning or fields["meaning"]

            if not text:
                unresolved.append(wid)
                continue

            if not args.include_non_cjk and not _contains_cjk(text):
                skipped_non_cjk.append(wid)
                continue

            to_insert.append((wid, text, pinyin, meaning or ""))

        print(f"Repairable: {len(to_insert)}")
        print(f"Unresolved: {len(unresolved)}")
        print(f"Skipped non-CJK: {len(skipped_non_cjk)}")
        if unresolved:
            print("Unresolved sample:", ", ".join(unresolved[:20]))
        if skipped_non_cjk:
            print("Skipped non-CJK sample:", ", ".join(skipped_non_cjk[:20]))

        if not args.apply:
            for row in to_insert[:20]:
                print(f"DRY-RUN {row[0]} -> {row[1]} | {row[2] or ''} | {row[3] or ''}")
            print("Dry-run only. Re-run with --apply to write changes.")
            return 0

        conn.executemany(
            """
            INSERT OR IGNORE INTO concepts (id, text, pinyin, meaning, created_at)
            VALUES (?, ?, ?, ?, datetime('now'))
            """,
            to_insert,
        )

        # Bootstrap sense rows for inserted concepts.
        sense_module = _load_sense_helpers()
        inserted_senses = 0
        if sense_module is not None:
            inserted_senses = sense_module.bootstrap_concept_senses(conn)

        conn.commit()
        print(f"Inserted concepts: {len(to_insert)}")
        print(f"Bootstrapped senses: {inserted_senses}")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
