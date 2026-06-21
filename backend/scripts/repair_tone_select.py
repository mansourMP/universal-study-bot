#!/usr/bin/env python3
"""Repair tone_select payloads using concepts.pinyin and derived correct_tone."""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path
from typing import Optional


def tone_from_pinyin(pinyin: str) -> Optional[int]:
    if not pinyin:
        return None
    tone_map = {
        "ā": 1, "á": 2, "ǎ": 3, "à": 4,
        "ē": 1, "é": 2, "ě": 3, "è": 4,
        "ī": 1, "í": 2, "ǐ": 3, "ì": 4,
        "ō": 1, "ó": 2, "ǒ": 3, "ò": 4,
        "ū": 1, "ú": 2, "ǔ": 3, "ù": 4,
        "ǖ": 1, "ǘ": 2, "ǚ": 3, "ǜ": 4,
    }
    parts = pinyin.strip().split()
    for part in parts:
        if part and part[-1].isdigit():
            tone = int(part[-1])
            if 1 <= tone <= 5:
                return tone
        for ch in part:
            if ch in tone_map:
                return tone_map[ch]
    return None


def main() -> int:
    db_path = Path("backend/learning_path.db")
    vocab_path = Path("backend/vocabulary_v2.db")
    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    vocab = None
    if vocab_path.exists():
        vocab = sqlite3.connect(str(vocab_path))
        vocab.row_factory = sqlite3.Row

    updated = 0
    missing_concepts = 0
    still_missing_tone = 0

    rows = conn.execute(
        "SELECT id, word_id, payload FROM word_exercises WHERE exercise_type = 'tone_select'"
    ).fetchall()

    for row in rows:
        ex_id = row["id"]
        word_id = str(row["word_id"])
        payload = {}
        try:
            payload = json.loads(row["payload"]) if row["payload"] else {}
        except json.JSONDecodeError:
            payload = {}

        pinyin = payload.get("pinyin")
        correct = payload.get("correct_tone")
        tone = tone_from_pinyin(pinyin) if pinyin else None

        # If pinyin lacks tone marks but correct_tone exists, append tone number to first syllable
        pinyin_appended = False
        if tone is None and isinstance(correct, int) and pinyin:
            parts = pinyin.strip().split()
            if parts:
                parts[0] = f"{parts[0]}{correct}"
                pinyin = " ".join(parts)
                payload["pinyin"] = pinyin
                tone = tone_from_pinyin(pinyin)
                pinyin_appended = True

        needs_fix = tone is None or not isinstance(correct, int) or correct != tone

        if not needs_fix:
            if pinyin_appended:
                conn.execute(
                    "UPDATE word_exercises SET payload = ? WHERE id = ?",
                    (json.dumps(payload, ensure_ascii=False), ex_id)
                )
                updated += 1
            continue

        concept_row = conn.execute(
            "SELECT text, pinyin FROM concepts WHERE id = ?",
            (word_id,)
        ).fetchone()
        if not concept_row:
            missing_concepts += 1
            continue

        concept_pinyin = concept_row["pinyin"]
        if (not concept_pinyin) or (tone_from_pinyin(concept_pinyin) is None):
            if vocab is not None:
                vrow = vocab.execute(
                    "SELECT pronunciation FROM concepts WHERE id = ?",
                    (word_id,)
                ).fetchone()
                if vrow and vrow["pronunciation"]:
                    concept_pinyin = vrow["pronunciation"]
        new_tone = tone_from_pinyin(concept_pinyin) if concept_pinyin else None
        if new_tone is None:
            still_missing_tone += 1
            continue

        payload["word"] = concept_row["text"]
        payload["pinyin"] = concept_pinyin
        payload["correct_tone"] = new_tone

        conn.execute(
            "UPDATE word_exercises SET payload = ? WHERE id = ?",
            (json.dumps(payload, ensure_ascii=False), ex_id)
        )
        updated += 1

    conn.commit()
    conn.close()
    if vocab is not None:
        vocab.close()

    print("--- Tone Select Repair ---")
    print(f"Total tone_select rows: {len(rows)}")
    print(f"Updated rows: {updated}")
    print(f"Missing concepts: {missing_concepts}")
    print(f"Still missing tone after repair: {still_missing_tone}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
