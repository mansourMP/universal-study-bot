#!/usr/bin/env python3
"""Suggest concept matches for a given text (no DB writes)."""

from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path
from typing import Dict, List, Tuple

TONE_MAP = str.maketrans(
    {
        "ā": "a",
        "á": "a",
        "ǎ": "a",
        "à": "a",
        "ē": "e",
        "é": "e",
        "ě": "e",
        "è": "e",
        "ī": "i",
        "í": "i",
        "ǐ": "i",
        "ì": "i",
        "ō": "o",
        "ó": "o",
        "ǒ": "o",
        "ò": "o",
        "ū": "u",
        "ú": "u",
        "ǔ": "u",
        "ù": "u",
        "ǖ": "u",
        "ǘ": "u",
        "ǚ": "u",
        "ǜ": "u",
        "ü": "u",
    }
)

SYNONYM_HINTS = {
    "车": ["汽车", "车子"],
    "看书": ["读书", "书"],
}


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _strip_tones(pinyin: str) -> str:
    return pinyin.translate(TONE_MAP) if pinyin else pinyin


def _fetch_all(conn: sqlite3.Connection) -> List[Tuple[str, str, str]]:
    cur = conn.cursor()
    cur.execute("SELECT id, text, pinyin FROM concepts")
    return cur.fetchall()


def _exact_matches(rows, text: str):
    return [r for r in rows if r[1] == text]


def _contains_matches(rows, text: str):
    return [r for r in rows if text in r[1]]


def _pinyin_matches(rows, text: str):
    t = _strip_tones(text.lower())
    matches = []
    for r in rows:
        p = _strip_tones((r[2] or "").lower())
        if not p:
            continue
        if t == p or t in p:
            matches.append(r)
    return matches


def _synonym_matches(rows, text: str):
    hints = SYNONYM_HINTS.get(text, [])
    if not hints:
        return []
    return [r for r in rows if r[1] in hints]


def _format(rows: List[Tuple[str, str, str]]) -> List[str]:
    return [f"{r[0]}\t{r[1]}\t{r[2] or ''}" for r in sorted(rows, key=lambda x: int(x[0]))]


def main() -> int:
    parser = argparse.ArgumentParser(description="Suggest concept matches for a text")
    parser.add_argument("--text", required=True)
    parser.add_argument("--db", default="backend/learning_path.db")
    args = parser.parse_args()

    db_path = _repo_root() / args.db
    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1

    conn = sqlite3.connect(str(db_path))
    rows = _fetch_all(conn)
    conn.close()

    text = args.text.strip()
    groups: Dict[str, List[Tuple[str, str, str]]] = {
        "exact": _exact_matches(rows, text),
        "contains": _contains_matches(rows, text),
        "pinyin": _pinyin_matches(rows, text),
        "synonyms": _synonym_matches(rows, text),
    }

    print(f"Query: {text}")
    for key in ("exact", "contains", "synonyms", "pinyin"):
        items = _format(groups[key])
        print(f"\n[{key}] {len(items)}")
        for line in items[:20]:
            print(line)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
