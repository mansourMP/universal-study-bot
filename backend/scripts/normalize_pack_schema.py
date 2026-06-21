#!/usr/bin/env python3
"""Normalize a vocab pack to the zh_hsk6-style schema.

Target row shape:
  - hanzi
  - pinyin
  - meaning (dict of canonical language codes)
  - pos
  - sense
  - context_sentence
  - context_translation (dict of canonical language codes)

The script preserves source metadata fields when present:
  - traditional
  - source_id
  - source_level
  - source_name
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import shutil
import sqlite3
from pathlib import Path
from typing import Dict, List, Tuple


CANON_LANGS = [
    "en",
    "uz",
    "es",
    "fr",
    "ru",
    "ar",
    "pt",
    "de",
    "it",
    "ja",
    "ko",
    "hi",
    "ur",
    "bn",
    "tr",
    "pl",
    "nl",
    "fa",
    "id",
    "vi",
    "th",
    "ms",
    "tl",
    "sw",
    "uk",
    "ro",
    "cs",
    "hu",
    "sv",
    "da",
    "no",
    "el",
    "he",
    "pa",
    "ta",
    "zh",
]


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _norm_pinyin(value: str | None) -> str:
    if not value:
        return ""
    return re.sub(r"\s+", " ", str(value)).strip().lower()


def _meaning_en_from_row(row: Dict) -> str:
    meaning = row.get("meaning")
    if isinstance(meaning, dict):
        return str(meaning.get("en") or "").strip()
    if isinstance(meaning, str):
        return meaning.strip()
    return str(row.get("meaning_en") or "").strip()


def _resolve_concept(conn: sqlite3.Connection, hanzi: str, pinyin: str) -> Tuple[str | None, str]:
    rows = conn.execute(
        "SELECT id, pinyin, meaning FROM concepts WHERE text = ? ORDER BY id",
        (hanzi,),
    ).fetchall()
    if not rows:
        return None, ""
    if len(rows) == 1:
        return str(rows[0][0]), str(rows[0][2] or "")

    want = _norm_pinyin(pinyin)
    if want:
        by_pin = [r for r in rows if _norm_pinyin(r[1]) == want]
        if len(by_pin) == 1:
            return str(by_pin[0][0]), str(by_pin[0][2] or "")

    # Deterministic fallback.
    return str(rows[0][0]), str(rows[0][2] or "")


def _load_localizations(
    conn: sqlite3.Connection, concept_id: str
) -> Tuple[Dict[str, str], Dict[str, str]]:
    meaning_map = {lang: "" for lang in CANON_LANGS}
    context_map = {lang: "" for lang in CANON_LANGS}

    rows = conn.execute(
        """
        SELECT language_code, meaning, context_translation
        FROM concept_localizations
        WHERE concept_id = ?
        """,
        (concept_id,),
    ).fetchall()
    for lang, meaning, context_translation in rows:
        code = str(lang or "").strip().lower()
        if code not in meaning_map:
            continue
        if meaning:
            meaning_map[code] = str(meaning).strip()
        if context_translation:
            context_map[code] = str(context_translation).strip()
    return meaning_map, context_map


def _pick_context_sentence(conn: sqlite3.Connection, concept_id: str) -> Tuple[str, str]:
    row = conn.execute(
        """
        SELECT s.text, s.translation
        FROM word_sentences ws
        JOIN sentences s ON s.id = ws.sentence_id
        WHERE ws.word_id = ?
        ORDER BY
          CASE WHEN COALESCE(s.tags, '') LIKE '%context%' THEN 0 ELSE 1 END,
          s.id
        LIMIT 1
        """,
        (concept_id,),
    ).fetchone()
    if not row:
        return "", ""
    return str(row[0] or "").strip(), str(row[1] or "").strip()


def main() -> int:
    parser = argparse.ArgumentParser(description="Normalize vocab pack schema")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--pack", required=True, help="Pack JSON path")
    parser.add_argument("--in-place", action="store_true")
    parser.add_argument("--out", default="", help="Output path when not using --in-place")
    args = parser.parse_args()

    repo_root = _repo_root()
    db_path = repo_root / args.db
    pack_path = repo_root / args.pack if not Path(args.pack).is_absolute() else Path(args.pack)
    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1
    if not pack_path.exists():
        print(f"Pack not found: {pack_path}")
        return 1

    raw = json.loads(pack_path.read_text(encoding="utf-8"))
    rows = raw.get("vocabulary", [])
    if not isinstance(rows, list):
        print("Invalid pack: `vocabulary` must be a list")
        return 1

    conn = sqlite3.connect(str(db_path))
    unresolved = 0
    out_rows: List[Dict] = []

    try:
        for row in rows:
            if not isinstance(row, dict):
                continue
            hanzi = str(row.get("hanzi") or "").strip()
            pinyin = str(row.get("pinyin") or "").strip()
            if not hanzi:
                continue

            concept_id, concept_meaning = _resolve_concept(conn, hanzi, pinyin)
            meaning_map = {lang: "" for lang in CANON_LANGS}
            context_map = {lang: "" for lang in CANON_LANGS}
            context_sentence = ""
            sentence_en = ""

            if concept_id:
                m_map, c_map = _load_localizations(conn, concept_id)
                meaning_map.update(m_map)
                context_map.update(c_map)
                context_sentence, sentence_en = _pick_context_sentence(conn, concept_id)
            else:
                unresolved += 1

            # Fallbacks.
            if not meaning_map["en"]:
                meaning_map["en"] = _meaning_en_from_row(row) or concept_meaning
            if not meaning_map["zh"]:
                meaning_map["zh"] = hanzi
            if sentence_en and not context_map["en"]:
                context_map["en"] = sentence_en
            if context_sentence and not context_map["zh"]:
                context_map["zh"] = context_sentence
            if not context_sentence:
                context_sentence = str(row.get("context_sentence") or "").strip()

            out_row: Dict = {
                "hanzi": hanzi,
                "pinyin": pinyin,
                "meaning": meaning_map,
                "pos": row.get("pos"),
                "sense": row.get("sense"),
                "context_sentence": context_sentence,
                "context_translation": context_map,
            }

            # Preserve source metadata fields when present.
            for key in ("traditional", "source_id", "source_level", "source_name"):
                if key in row:
                    out_row[key] = row.get(key)

            out_rows.append(out_row)
    finally:
        conn.close()

    level_value = raw.get("level")
    top = {
        "id": raw.get("id") or pack_path.stem,
        "language": raw.get("language") or "zh",
        "level": level_value,
        "kind": raw.get("kind") or "vocab",
        "version": raw.get("version") or 1,
        "schema_version": raw.get("schema_version") or "1.0",
        "domain": raw.get("domain") or "general",
        "topic": raw.get("topic") or f"hsk{level_value}_vocab",
        "tags": raw.get("tags") or ["hsk3.0", "normalized_pack"],
        "provenance": raw.get("provenance")
        or {
            "source": raw.get("source") or "unknown",
            "normalized_at": dt.datetime.now().isoformat(timespec="seconds"),
        },
        "vocabulary": out_rows,
    }

    if args.in_place:
        stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
        backup = pack_path.with_suffix(f".json.bak_{stamp}")
        shutil.copy2(pack_path, backup)
        out_path = pack_path
    else:
        out_path = (
            repo_root / args.out
            if args.out and not Path(args.out).is_absolute()
            else Path(args.out or str(pack_path.with_name(f"{pack_path.stem}.normalized.json")))
        )
        out_path.parent.mkdir(parents=True, exist_ok=True)
        backup = None

    out_path.write_text(json.dumps(top, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"Normalized rows: {len(out_rows)}")
    print(f"Unresolved concepts: {unresolved}")
    if backup is not None:
        print(f"Backup: {backup}")
    print(f"Output: {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
