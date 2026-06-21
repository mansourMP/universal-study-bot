#!/usr/bin/env python3
"""Import multilingual localization payloads from vocab packs into DB.

This preserves existing translation investment (e.g., 36 languages) in a
dedicated table independent of curriculum standard mapping.
"""

from __future__ import annotations

import argparse
import datetime as dt
import glob
import json
import re
import sqlite3
from pathlib import Path
from typing import Dict, List, Tuple


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _norm_text(v: str | None) -> str:
    return re.sub(r"\s+", "", str(v or "").strip())


def _norm_pinyin(v: str | None) -> str:
    return re.sub(r"\s+", " ", str(v or "").strip().lower())


def _ensure_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS concept_localizations (
            concept_id TEXT NOT NULL,
            language_code TEXT NOT NULL,
            meaning TEXT,
            context_translation TEXT,
            source_pack TEXT,
            updated_at TEXT DEFAULT (datetime('now')),
            PRIMARY KEY (concept_id, language_code)
        );

        CREATE INDEX IF NOT EXISTS idx_cl_concept
            ON concept_localizations(concept_id);
        CREATE INDEX IF NOT EXISTS idx_cl_lang
            ON concept_localizations(language_code);
        """
    )


def _resolve_concept_ids(conn: sqlite3.Connection, hanzi: str, pinyin: str) -> List[str]:
    rows = conn.execute(
        "SELECT id, pinyin FROM concepts WHERE text = ? ORDER BY id ASC",
        (hanzi,),
    ).fetchall()
    if not rows:
        return []
    want = _norm_pinyin(pinyin)
    if want:
        exact = [str(r[0]) for r in rows if _norm_pinyin(r[1]) == want]
        if exact:
            return exact
    return [str(rows[0][0])]


def _iter_pack_rows(pack_path: Path) -> List[Dict]:
    data = json.loads(pack_path.read_text(encoding="utf-8"))
    rows = data.get("vocabulary", [])
    return [r for r in rows if isinstance(r, dict)]


def main() -> int:
    parser = argparse.ArgumentParser(description="Import multilingual localizations from vocab packs")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument(
        "--packs-glob",
        default="backend/content/packs/zh_hsk[1-6]_vocab.json",
        help="Glob pattern for pack files that contain multilingual `meaning` dicts",
    )
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--report-dir", default="docs/reports")
    args = parser.parse_args()

    root = _repo_root()
    db_path = root / args.db
    report_dir = root / args.report_dir
    report_dir.mkdir(parents=True, exist_ok=True)

    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1

    pack_paths = sorted(Path(p) for p in glob.glob(str(root / args.packs_glob)))
    if not pack_paths:
        print(f"No pack files found for glob: {args.packs_glob}")
        return 1

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        _ensure_schema(conn)

        inserts: List[Tuple[str, str, str, str, str]] = []
        matched_rows = 0
        unmatched_rows = 0
        ambiguous_rows = 0
        processed_rows = 0
        languages = set()

        for pack_path in pack_paths:
            rows = _iter_pack_rows(pack_path)
            for row in rows:
                processed_rows += 1
                hanzi = _norm_text(row.get("hanzi"))
                pinyin = _norm_pinyin(row.get("pinyin"))
                if not hanzi:
                    continue

                meaning_map = row.get("meaning")
                context_map = row.get("context_translation")
                if not isinstance(meaning_map, dict):
                    continue
                if context_map is not None and not isinstance(context_map, dict):
                    context_map = {}
                context_map = context_map or {}

                concept_ids = _resolve_concept_ids(conn, hanzi, pinyin)
                if not concept_ids:
                    unmatched_rows += 1
                    continue
                if len(concept_ids) > 1:
                    ambiguous_rows += 1

                concept_id = concept_ids[0]
                matched_rows += 1

                for lang, m in meaning_map.items():
                    lang_code = str(lang or "").strip().lower()
                    meaning_txt = str(m or "").strip()
                    if not lang_code:
                        continue
                    if not meaning_txt and not context_map.get(lang_code):
                        continue
                    context_txt = str(context_map.get(lang_code, "") or "").strip()
                    languages.add(lang_code)
                    inserts.append(
                        (
                            concept_id,
                            lang_code,
                            meaning_txt,
                            context_txt,
                            pack_path.name,
                        )
                    )

        if args.apply and inserts:
            conn.executemany(
                """
                INSERT INTO concept_localizations
                    (concept_id, language_code, meaning, context_translation, source_pack, updated_at)
                VALUES (?, ?, ?, ?, ?, datetime('now'))
                ON CONFLICT(concept_id, language_code) DO UPDATE SET
                    meaning = excluded.meaning,
                    context_translation = excluded.context_translation,
                    source_pack = excluded.source_pack,
                    updated_at = datetime('now')
                """,
                inserts,
            )
            conn.commit()

        report = {
            "date": dt.date.today().isoformat(),
            "db": args.db,
            "packs_glob": args.packs_glob,
            "pack_files": [str(p) for p in pack_paths],
            "rows_processed": processed_rows,
            "rows_matched_to_concepts": matched_rows,
            "rows_unmatched": unmatched_rows,
            "rows_ambiguous": ambiguous_rows,
            "localization_rows_prepared": len(inserts),
            "languages_detected": sorted(languages),
            "applied": args.apply,
        }
        report_path = report_dir / f"concept_localizations_import_{dt.date.today().isoformat()}.json"
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

        print("Concept localizations import complete")
        print(f"Report: {report_path}")
        print(f"Prepared rows: {len(inserts)}")
        print(f"Languages: {len(languages)}")
        print(f"Applied: {args.apply}")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
