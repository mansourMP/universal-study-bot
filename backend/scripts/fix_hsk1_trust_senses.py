#!/usr/bin/env python3
"""Repair high-risk HSK1 primary meanings for trust-critical words.

Updates three surfaces in sync:
- concepts.meaning
- concept_senses primary gloss
- concept_localizations.en meaning
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sqlite3
from pathlib import Path


FIX_MAP = {
    "W00016": ("点", "diǎn", "o'clock"),
    "W00037": ("号", "hào", "day of month"),
    "W00134": ("月", "yuè", "month"),
    "W00160": ("次", "cì", "time (occurrence)"),
    "W00235": ("日", "rì", "day; date"),
    "W00346": ("地", "de", "structural particle (before adverbial)"),
}


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def main() -> int:
    parser = argparse.ArgumentParser(description="Repair trust-critical HSK1 meanings")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--source-tag", default="hsk1_trust_sense_fix_2026-02-14")
    parser.add_argument("--report-dir", default="docs/reports")
    args = parser.parse_args()

    root = _repo_root()
    db_path = root / args.db
    report_dir = root / args.report_dir
    report_dir.mkdir(parents=True, exist_ok=True)

    if not db_path.exists():
        print(json.dumps({"ok": False, "error": f"DB not found: {db_path}"}))
        return 1

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout = 20000")

    rows = []
    writes = {
        "concepts_meaning_updated": 0,
        "primary_sense_updated": 0,
        "en_localization_upserted": 0,
    }

    try:
        if args.apply:
            conn.execute("BEGIN")

        for cid, (expected_hanzi, expected_pinyin, new_gloss) in FIX_MAP.items():
            c = conn.execute(
                "SELECT id, text, COALESCE(pinyin,''), COALESCE(meaning,'') FROM concepts WHERE id = ?",
                (cid,),
            ).fetchone()
            if c is None:
                rows.append(
                    {
                        "concept_id": cid,
                        "status": "missing_concept",
                    }
                )
                continue

            primary = conn.execute(
                """
                SELECT sense_id, COALESCE(gloss,'') AS gloss
                FROM concept_senses
                WHERE concept_id = ? AND is_primary = 1
                LIMIT 1
                """,
                (cid,),
            ).fetchone()

            current_concept_meaning = str(c[3] or "").strip()
            current_primary_gloss = str(primary["gloss"] if primary else "").strip()
            current_text = str(c[1] or "").strip()
            current_pinyin = str(c[2] or "").strip()

            status = "ok"
            if current_text != expected_hanzi or current_pinyin != expected_pinyin:
                status = "mismatch_expected_form"

            if args.apply and status == "ok":
                if current_concept_meaning != new_gloss:
                    conn.execute("UPDATE concepts SET meaning = ? WHERE id = ?", (new_gloss, cid))
                    writes["concepts_meaning_updated"] += 1

                if primary is None:
                    conn.execute(
                        """
                        INSERT OR IGNORE INTO concept_senses
                            (sense_id, concept_id, ordinal, gloss, is_primary, source)
                        VALUES (?, ?, 1, ?, 1, ?)
                        """,
                        (f"{cid}::s01", cid, new_gloss, args.source_tag),
                    )
                    writes["primary_sense_updated"] += 1
                elif current_primary_gloss != new_gloss:
                    conn.execute(
                        """
                        UPDATE concept_senses
                        SET gloss = ?, source = ?
                        WHERE sense_id = ?
                        """,
                        (new_gloss, args.source_tag, primary["sense_id"]),
                    )
                    writes["primary_sense_updated"] += 1

                conn.execute(
                    """
                    INSERT INTO concept_localizations
                        (concept_id, language_code, meaning, context_translation, source_pack, updated_at)
                    VALUES (?, 'en', ?, '', ?, datetime('now'))
                    ON CONFLICT(concept_id, language_code) DO UPDATE SET
                        meaning = excluded.meaning,
                        source_pack = excluded.source_pack,
                        updated_at = datetime('now')
                    """,
                    (cid, new_gloss, args.source_tag),
                )
                writes["en_localization_upserted"] += 1

            rows.append(
                {
                    "concept_id": cid,
                    "hanzi": current_text,
                    "pinyin": current_pinyin,
                    "old_concept_meaning": current_concept_meaning,
                    "old_primary_gloss": current_primary_gloss,
                    "new_gloss": new_gloss,
                    "status": status,
                }
            )

        if args.apply:
            conn.commit()

    finally:
        conn.close()

    stamp = dt.date.today().isoformat()
    report = {
        "ok": True,
        "date": stamp,
        "db": str(db_path),
        "apply": bool(args.apply),
        "source_tag": args.source_tag,
        "targets": len(FIX_MAP),
        "writes": writes,
        "rows": rows,
    }
    out = report_dir / f"hsk1_trust_sense_fix_{stamp}.json"
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "rows"}, ensure_ascii=False))
    print(f"Report: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

