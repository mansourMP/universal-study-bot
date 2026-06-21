#!/usr/bin/env python3
"""Apply context-translation worker outputs to pack + DB."""

from __future__ import annotations

import argparse
import datetime as dt
import glob
import json
import re
import shutil
import sqlite3
from pathlib import Path
from typing import Dict, List, Tuple


CANON_LANGS = {
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
}


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _norm_pinyin(value: str | None) -> str:
    if not value:
        return ""
    return re.sub(r"\s+", " ", str(value)).strip().lower()


def _resolve_concept_id(conn: sqlite3.Connection, hanzi: str, pinyin: str) -> str | None:
    rows = conn.execute(
        "SELECT id, pinyin FROM concepts WHERE text = ? ORDER BY id",
        (hanzi,),
    ).fetchall()
    if not rows:
        return None
    if len(rows) == 1:
        return str(rows[0][0])

    want = _norm_pinyin(pinyin)
    if want:
        by_pinyin = [row for row in rows if _norm_pinyin(row[1]) == want]
        if len(by_pinyin) == 1:
            return str(by_pinyin[0][0])
    return str(rows[0][0])


def _load_result_items(paths: List[str]) -> Tuple[List[Dict], int]:
    items: List[Dict] = []
    failures = 0
    for path in sorted(paths):
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        part = data.get("items") or []
        if isinstance(part, list):
            items.extend([row for row in part if isinstance(row, dict)])
        fail = data.get("failures") or []
        if isinstance(fail, list):
            failures += len(fail)
    return items, failures


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply context translation results to pack + DB")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--pack", default="backend/content/packs/zh_hsk7_vocab.json")
    parser.add_argument("--input-glob", default="docs/context_results/*.result.json")
    parser.add_argument("--report-dir", default="docs/reports")
    parser.add_argument("--source-tag", default="deepseek_context_batch")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--overwrite", action="store_true")
    args = parser.parse_args()

    root = _repo_root()
    db_path = root / args.db
    pack_path = root / args.pack if not Path(args.pack).is_absolute() else Path(args.pack)
    report_dir = root / args.report_dir if not Path(args.report_dir).is_absolute() else Path(args.report_dir)
    report_dir.mkdir(parents=True, exist_ok=True)

    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1
    if not pack_path.exists():
        print(f"Pack not found: {pack_path}")
        return 1

    input_glob = str(root / args.input_glob) if not Path(args.input_glob).is_absolute() else args.input_glob
    files = sorted(glob.glob(input_glob))
    if not files:
        print(f"No result files matched: {args.input_glob}")
        return 1

    pack_data = json.loads(pack_path.read_text(encoding="utf-8"))
    rows = pack_data.get("vocabulary") or []
    if not isinstance(rows, list):
        print("Invalid pack: `vocabulary` must be list.")
        return 1

    items, failures = _load_result_items(files)

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    conn.execute("BEGIN")

    rows_updated = 0
    db_upserts = 0
    values_applied = 0
    values_skipped_existing = 0
    unresolved_rows = 0

    try:
        for item in items:
            cid = str(item.get("concept_id") or "").strip()
            row_index = int(item.get("row_index", -1))
            translations = item.get("translations") or {}
            if not cid or not isinstance(translations, dict):
                continue
            if row_index < 0 or row_index >= len(rows):
                continue

            row = rows[row_index]
            if not isinstance(row, dict):
                continue

            # Safety: re-resolve row concept_id and ensure it matches worker concept_id.
            hanzi = str(row.get("hanzi") or "").strip()
            pinyin = str(row.get("pinyin") or "").strip()
            resolved = _resolve_concept_id(conn, hanzi, pinyin)
            if resolved and resolved != cid:
                unresolved_rows += 1
                continue

            context_map = row.get("context_translation")
            if not isinstance(context_map, dict):
                context_map = {}

            row_changed = False
            for lang_raw, text_raw in translations.items():
                lang = str(lang_raw or "").strip().lower()
                text = str(text_raw or "").strip()
                if not lang or lang not in CANON_LANGS or not text:
                    continue

                existing_row = str(context_map.get(lang) or "").strip()
                if existing_row and not args.overwrite:
                    values_skipped_existing += 1
                    continue

                if args.apply:
                    context_map[lang] = text
                values_applied += 1
                row_changed = True

                # Upsert DB context_translation.
                if args.apply:
                    existing = conn.execute(
                        """
                        SELECT meaning, context_translation
                        FROM concept_localizations
                        WHERE concept_id = ? AND language_code = ?
                        LIMIT 1
                        """,
                        (cid, lang),
                    ).fetchone()
                    existing_meaning = str(existing["meaning"] or "").strip() if existing else ""
                    existing_ctx = str(existing["context_translation"] or "").strip() if existing else ""
                    if existing_ctx and not args.overwrite:
                        continue
                    conn.execute(
                        """
                        INSERT INTO concept_localizations
                            (concept_id, language_code, meaning, context_translation, source_pack, updated_at)
                        VALUES (?, ?, ?, ?, ?, datetime('now'))
                        ON CONFLICT(concept_id, language_code) DO UPDATE SET
                            context_translation = excluded.context_translation,
                            source_pack = excluded.source_pack,
                            updated_at = datetime('now')
                        """,
                        (cid, lang, existing_meaning, text, args.source_tag),
                    )
                    db_upserts += 1

            if row_changed:
                rows[row_index]["context_translation"] = context_map
                rows_updated += 1

        if args.apply:
            stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
            backup = pack_path.with_suffix(f".json.bak_{stamp}")
            shutil.copy2(pack_path, backup)
            pack_path.write_text(json.dumps(pack_data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            conn.commit()
        else:
            backup = None
            conn.rollback()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    report = {
        "date": dt.date.today().isoformat(),
        "db": str(db_path),
        "pack": str(pack_path),
        "input_glob": args.input_glob,
        "files": len(files),
        "items_seen": len(items),
        "failures_seen": failures,
        "apply": args.apply,
        "overwrite": args.overwrite,
        "rows_updated": rows_updated,
        "values_applied": values_applied,
        "values_skipped_existing": values_skipped_existing,
        "db_upserts": db_upserts,
        "unresolved_rows": unresolved_rows,
        "backup": str(backup) if args.apply and backup is not None else "",
    }
    report_path = report_dir / f"apply_context_results_{dt.date.today().isoformat()}.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))
    print(f"Report: {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
