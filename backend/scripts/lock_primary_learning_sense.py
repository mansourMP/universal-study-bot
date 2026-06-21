#!/usr/bin/env python3
"""Lock one primary learning sense per core concept and sync DB fields.

Goals:
- Exactly one primary sense per concept in scope.
- `concepts.meaning` == primary sense gloss.
- `concept_localizations.en.meaning` == primary sense gloss.
- If primary gloss contains hard list separators (; / |), keep first part as
  primary and add remaining parts as non-primary senses (if missing).

Notes:
- Comma-separated glosses are not auto-split by default to avoid harming
  idiomatic glosses (e.g. "more work, more rewards"). They are reported for
  manual review.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import re
import sqlite3
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple


HARD_SPLIT_RE = re.compile(r"[;/|；／｜]+")


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _norm(text: str | None) -> str:
    value = str(text or "").strip()
    value = value.replace("```", "").strip()
    value = re.sub(r"\s+", " ", value)
    return value.strip(" .;，、；:：")


def _split_hard(gloss: str) -> List[str]:
    text = _norm(gloss)
    if not text:
        return []
    parts = [_norm(p) for p in HARD_SPLIT_RE.split(text)]
    parts = [p for p in parts if p]
    # de-dup stable
    seen = set()
    out: List[str] = []
    for p in parts:
        key = p.lower()
        if key in seen:
            continue
        seen.add(key)
        out.append(p)
    return out


def _iter_scope_concepts(conn: sqlite3.Connection, standard: str) -> Iterable[sqlite3.Row]:
    return conn.execute(
        """
        SELECT DISTINCT c.id, c.text, COALESCE(c.pinyin,'') AS pinyin
        FROM concept_curriculum_map m
        JOIN concepts c ON c.id = m.concept_id
        WHERE m.standard = ? AND m.band = 'core'
        ORDER BY c.id
        """,
        (standard,),
    )


def _fetch_senses(conn: sqlite3.Connection, concept_id: str) -> List[sqlite3.Row]:
    return conn.execute(
        """
        SELECT sense_id, ordinal, gloss, is_primary
        FROM concept_senses
        WHERE concept_id = ?
        ORDER BY is_primary DESC, ordinal ASC, sense_id ASC
        """,
        (concept_id,),
    ).fetchall()


def _next_ordinal(senses: Sequence[sqlite3.Row]) -> int:
    if not senses:
        return 1
    return max(int(r["ordinal"] or 0) for r in senses) + 1


def _comma_list_like(gloss: str) -> bool:
    text = _norm(gloss)
    if not text or "," not in text:
        return False
    parts = [_norm(p) for p in text.split(",") if _norm(p)]
    if len(parts) < 2:
        return False
    # Treat short comma lists as likely multi-gloss candidates.
    return all(len(p.split()) <= 3 for p in parts)


def main() -> int:
    parser = argparse.ArgumentParser(description="Lock primary learning senses for core concepts")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--standard", default="HSK3.0")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--report-dir", default="docs/reports")
    parser.add_argument("--source-tag", default="sense_lock_2026-02-12")
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

    counters: Dict[str, int] = {
        "core_concepts": 0,
        "missing_senses": 0,
        "primary_reassigned": 0,
        "hard_split_primary_trimmed": 0,
        "alt_senses_inserted": 0,
        "concepts_meaning_updated": 0,
        "en_localization_upserted": 0,
        "comma_review_candidates": 0,
    }
    review_rows: List[Tuple[str, str, str, str]] = []

    try:
        rows = list(_iter_scope_concepts(conn, args.standard.upper()))
        counters["core_concepts"] = len(rows)

        if args.apply:
            conn.execute("BEGIN")

        for row in rows:
            cid = str(row["id"])
            hanzi = str(row["text"] or "").strip()
            pinyin = str(row["pinyin"] or "").strip()

            senses = _fetch_senses(conn, cid)
            if not senses:
                counters["missing_senses"] += 1
                current_meaning = conn.execute(
                    "SELECT COALESCE(meaning,'') FROM concepts WHERE id = ?",
                    (cid,),
                ).fetchone()[0]
                base = _norm(current_meaning) or hanzi
                if args.apply:
                    conn.execute(
                        """
                        INSERT OR IGNORE INTO concept_senses
                            (sense_id, concept_id, ordinal, gloss, is_primary, source)
                        VALUES (?, ?, 1, ?, 1, ?)
                        """,
                        (f"{cid}::s01", cid, base, args.source_tag),
                    )
                primary_gloss = base
            else:
                # Pick a primary sense deterministically.
                primary = next((s for s in senses if int(s["is_primary"] or 0) == 1), senses[0])
                primary_sid = str(primary["sense_id"])
                primary_gloss_raw = _norm(primary["gloss"])
                hard_parts = _split_hard(primary_gloss_raw)
                primary_gloss = hard_parts[0] if hard_parts else primary_gloss_raw

                if hard_parts and len(hard_parts) > 1:
                    counters["hard_split_primary_trimmed"] += 1
                    # Add remaining parts as alternative senses.
                    existing_glosses = {
                        _norm(s["gloss"]).lower()
                        for s in senses
                        if _norm(s["gloss"])
                    }
                    ordinal = _next_ordinal(senses)
                    for alt in hard_parts[1:]:
                        key = alt.lower()
                        if key in existing_glosses:
                            continue
                        if args.apply:
                            conn.execute(
                                """
                                INSERT OR IGNORE INTO concept_senses
                                    (sense_id, concept_id, ordinal, gloss, is_primary, source)
                                VALUES (?, ?, ?, ?, 0, ?)
                                """,
                                (f"{cid}::s{ordinal:02d}", cid, ordinal, alt, args.source_tag),
                            )
                        ordinal += 1
                        counters["alt_senses_inserted"] += 1

                if args.apply:
                    # Ensure exactly one primary sense.
                    conn.execute("UPDATE concept_senses SET is_primary = 0 WHERE concept_id = ?", (cid,))
                    # If another sense already has target gloss, use it as primary.
                    same_row = conn.execute(
                        """
                        SELECT sense_id
                        FROM concept_senses
                        WHERE concept_id = ? AND LOWER(TRIM(gloss)) = LOWER(TRIM(?))
                        ORDER BY ordinal ASC, sense_id ASC
                        LIMIT 1
                        """,
                        (cid, primary_gloss),
                    ).fetchone()
                    chosen_sid = str(same_row[0]) if same_row is not None else primary_sid
                    conn.execute(
                        """
                        UPDATE concept_senses
                        SET gloss = ?, is_primary = 1, source = ?
                        WHERE sense_id = ?
                        """,
                        (primary_gloss, args.source_tag, chosen_sid),
                    )
                    counters["primary_reassigned"] += 1

            if _comma_list_like(primary_gloss):
                counters["comma_review_candidates"] += 1
                review_rows.append((cid, hanzi, pinyin, primary_gloss))

            # Sync concepts.meaning and en localization to primary gloss.
            current_concept_meaning = conn.execute(
                "SELECT COALESCE(meaning,'') FROM concepts WHERE id = ?",
                (cid,),
            ).fetchone()[0]
            if _norm(current_concept_meaning) != primary_gloss:
                if args.apply:
                    conn.execute("UPDATE concepts SET meaning = ? WHERE id = ?", (primary_gloss, cid))
                counters["concepts_meaning_updated"] += 1

            en_row = conn.execute(
                """
                SELECT COALESCE(meaning,'')
                FROM concept_localizations
                WHERE concept_id = ? AND language_code = 'en'
                LIMIT 1
                """,
                (cid,),
            ).fetchone()
            en_meaning = _norm(en_row[0] if en_row else "")
            if en_meaning != primary_gloss:
                if args.apply:
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
                        (cid, primary_gloss, args.source_tag),
                    )
                counters["en_localization_upserted"] += 1

        if args.apply:
            conn.commit()

        stamp = dt.date.today().isoformat()
        report = {
            "date": stamp,
            "db": str(db_path),
            "standard": args.standard.upper(),
            "apply": bool(args.apply),
            **counters,
        }
        report_path = report_dir / f"sense_lock_report_{stamp}.json"
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

        review_path = report_dir / f"sense_lock_comma_review_{stamp}.csv"
        with review_path.open("w", encoding="utf-8", newline="") as f:
            w = csv.writer(f)
            w.writerow(["concept_id", "hanzi", "pinyin", "primary_gloss"])
            w.writerows(review_rows)

        print(json.dumps(report, ensure_ascii=False))
        print(f"Comma review CSV: {review_path}")
        print(f"Report: {report_path}")
        return 0
    except Exception:
        if args.apply:
            conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())

