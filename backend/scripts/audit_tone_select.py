#!/usr/bin/env python3
"""Audit tone_select exercises against pinyin tone marks or tone numbers."""

from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path
from typing import List, Optional, Tuple

TONE_MAP = {
    "ā": 1, "á": 2, "ǎ": 3, "à": 4,
    "ē": 1, "é": 2, "ě": 3, "è": 4,
    "ī": 1, "í": 2, "ǐ": 3, "ì": 4,
    "ō": 1, "ó": 2, "ǒ": 3, "ò": 4,
    "ū": 1, "ú": 2, "ǔ": 3, "ù": 4,
    "ǖ": 1, "ǘ": 2, "ǚ": 3, "ǜ": 4,
}


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _connect(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    return conn


def _extract_tones(pinyin: str) -> List[int]:
    tones: List[int] = []
    if not pinyin:
        return tones

    # Handle numeric tone suffixes like ma3
    parts = pinyin.strip().split()
    for part in parts:
        if part and part[-1].isdigit():
            tone = int(part[-1])
            if 1 <= tone <= 5:
                tones.append(tone)
                continue
        found = None
        for ch in part:
            if ch in TONE_MAP:
                found = TONE_MAP[ch]
                break
        if found:
            tones.append(found)
    return tones


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit tone_select exercises")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--limit", type=int, default=20)
    args = parser.parse_args()

    repo_root = _repo_root()
    db_path = repo_root / args.db

    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1

    conn = _connect(db_path)
    try:
        rows = conn.execute(
            "SELECT id, word_id, payload FROM word_exercises WHERE exercise_type = 'tone_select'"
        ).fetchall()
    finally:
        conn.close()

    total = 0
    mismatches: List[Tuple[str, str, str, Optional[int], List[int]]] = []
    missing_tone = 0

    for row in rows:
        total += 1
        ex_id = row[0]
        word_id = str(row[1])
        payload = {}
        try:
            payload = json.loads(row[2]) if row[2] else {}
        except json.JSONDecodeError:
            payload = {}

        pinyin = payload.get("pinyin", "")
        correct = payload.get("correct_tone")

        tones = _extract_tones(pinyin)
        if not tones:
            missing_tone += 1
            continue

        expected = tones[0]
        if isinstance(correct, int) and correct != expected:
            mismatches.append((ex_id, word_id, pinyin, correct, tones))

    mismatch_rate = (len(mismatches) / total) * 100 if total else 0.0

    print("--- Tone Select Audit ---")
    print(f"Total tone_select rows: {total}")
    print(f"Missing tone in pinyin: {missing_tone}")
    print(f"Mismatches (correct_tone != first syllable): {len(mismatches)} ({mismatch_rate:.1f}%)")

    if mismatches:
        print(f"Top {min(args.limit, len(mismatches))} mismatches:")
        for ex_id, word_id, pinyin, correct, tones in mismatches[: args.limit]:
            print(f"{ex_id} | word_id={word_id} | pinyin={pinyin} | correct_tone={correct} | tones={tones}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
