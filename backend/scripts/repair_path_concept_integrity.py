#!/usr/bin/env python3
"""Repair missing `concepts` rows referenced by active path units.

This script inspects `unit_concepts` for numeric units (default 1..48),
finds concept IDs that are missing in `concepts`, and reconstructs minimal
concept rows from existing `word_exercises` payloads.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sqlite3
from pathlib import Path
from typing import Dict, Optional


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _extract_from_payload(payload: Dict) -> Dict[str, Optional[str]]:
    text = None
    pinyin = None
    meaning = None

    if not isinstance(payload, dict):
        return {"text": None, "pinyin": None, "meaning": None}

    # Flashcard-like payloads.
    if isinstance(payload.get("front"), str):
        text = payload.get("front")
    if isinstance(payload.get("pinyin"), str):
        pinyin = payload.get("pinyin")
    if isinstance(payload.get("back"), str):
        meaning = payload.get("back")

    # Tone select payload.
    if not text and isinstance(payload.get("word"), str):
        text = payload.get("word")
    if not pinyin and isinstance(payload.get("pinyin"), str):
        pinyin = payload.get("pinyin")

    # Sentence payload fallback.
    if not text and isinstance(payload.get("correct"), str):
        text = payload.get("correct")

    return {
        "text": text.strip() if isinstance(text, str) and text.strip() else None,
        "pinyin": pinyin.strip() if isinstance(pinyin, str) and pinyin.strip() else None,
        "meaning": meaning.strip() if isinstance(meaning, str) and meaning.strip() else None,
    }


def _load_sense_helpers():
    import importlib.util

    module_path = _repo_root() / "backend" / "learning_path" / "sense_store.py"
    spec = importlib.util.spec_from_file_location("sense_store_runtime", module_path)
    if spec is None or spec.loader is None:
        return None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    parser = argparse.ArgumentParser(description="Repair missing concepts in active path")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--min-unit", type=int, default=1)
    parser.add_argument("--max-unit", type=int, default=48)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    db_path = _repo_root() / args.db
    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        missing_rows = conn.execute(
            """
            SELECT DISTINCT uc.concept_id
            FROM unit_concepts uc
            LEFT JOIN concepts c ON c.id = uc.concept_id
            WHERE uc.unit_id GLOB '[0-9]*'
              AND CAST(uc.unit_id AS INTEGER) BETWEEN ? AND ?
              AND c.id IS NULL
            ORDER BY uc.concept_id
            """,
            (args.min_unit, args.max_unit),
        ).fetchall()

        missing_ids = [str(r["concept_id"]) for r in missing_rows]
        print(f"Missing concepts in units {args.min_unit}-{args.max_unit}: {len(missing_ids)}")
        if not missing_ids:
            return 0

        repaired = []
        unresolved = []

        for cid in missing_ids:
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
                  END,
                  id ASC
                """,
                (cid,),
            ).fetchall()

            text = pinyin = meaning = None
            for ex in ex_rows:
                payload_raw = ex["payload"]
                try:
                    payload = json.loads(payload_raw) if payload_raw else {}
                except Exception:
                    payload = {}
                fields = _extract_from_payload(payload)
                text = text or fields["text"]
                pinyin = pinyin or fields["pinyin"]
                meaning = meaning or fields["meaning"]

            if not text:
                unresolved.append(cid)
                continue

            repaired.append(
                {
                    "id": cid,
                    "text": text,
                    "pinyin": pinyin,
                    "meaning": meaning or "",
                }
            )

        print(f"Repairable: {len(repaired)}")
        print(f"Unresolved: {len(unresolved)}")
        if unresolved:
            print("Unresolved IDs:", ", ".join(unresolved))

        if args.dry_run:
            for row in repaired:
                print(
                    f"DRY-RUN INSERT {row['id']} | {row['text']} | {row['pinyin'] or ''} | {row['meaning'] or ''}"
                )
            return 0

        conn.executemany(
            """
            INSERT OR IGNORE INTO concepts (id, text, pinyin, meaning, created_at)
            VALUES (?, ?, ?, ?, datetime('now'))
            """,
            [(r["id"], r["text"], r["pinyin"], r["meaning"]) for r in repaired],
        )
        conn.commit()

        # Bootstrap concept_senses for newly inserted rows.
        sense_module = _load_sense_helpers()
        if sense_module is not None:
            inserted_senses = sense_module.bootstrap_concept_senses(conn)
        else:
            inserted_senses = 0

        stamp = dt.date.today().isoformat()
        print(f"Inserted concepts: {len(repaired)}")
        print(f"Bootstrapped senses: {inserted_senses}")
        print(f"Done [{stamp}]")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
