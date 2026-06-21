#!/usr/bin/env python3
"""Global DB cleanup for learning_path.db.

This script normalizes core semantic fields and removes globally broken
orphan rows while preserving curriculum/path data.

Default mode is dry-run. Use --apply to write changes.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import shutil
import sqlite3
from pathlib import Path
from typing import Dict


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _snapshot(conn: sqlite3.Connection) -> Dict[str, int]:
    q = """
    SELECT
      (SELECT COUNT(*) FROM concepts) AS concepts_total,
      (SELECT COUNT(*) FROM word_exercises) AS word_exercises_total,
      (SELECT COUNT(*) FROM word_sentences) AS word_sentences_total,
      (SELECT COUNT(*) FROM user_attempts) AS user_attempts_total,
      (SELECT COUNT(*) FROM user_exercise_history) AS user_ex_history_total,
      (SELECT COUNT(*) FROM word_exercises w LEFT JOIN concepts c ON c.id=w.word_id WHERE c.id IS NULL) AS orphan_word_exercises,
      (SELECT COUNT(*) FROM word_sentences ws LEFT JOIN concepts c ON c.id=ws.word_id WHERE c.id IS NULL) AS orphan_word_sentences,
      (SELECT COUNT(*) FROM word_sentences ws LEFT JOIN sentences s ON s.id=ws.sentence_id WHERE s.id IS NULL) AS orphan_sentence_links,
      (SELECT COUNT(*) FROM concepts c LEFT JOIN concept_senses s ON s.concept_id=c.id AND s.is_primary=1 WHERE s.sense_id IS NULL) AS concepts_no_primary_sense,
      (SELECT COUNT(*) FROM concepts c JOIN concept_senses s ON s.concept_id=c.id AND s.is_primary=1 WHERE TRIM(COALESCE(c.meaning,'')) != TRIM(COALESCE(s.gloss,''))) AS meaning_primary_mismatch
    """
    row = conn.execute(q).fetchone()
    keys = [d[0] for d in conn.execute(q).description]
    return {k: int(v or 0) for k, v in zip(keys, row)}


def _apply_cleanup(conn: sqlite3.Connection, source_tag: str) -> Dict[str, int]:
    writes: Dict[str, int] = {}
    conn.execute("BEGIN")
    try:
        cur = conn.execute(
            """
            UPDATE concepts
            SET meaning = (
              SELECT s.gloss FROM concept_senses s
              WHERE s.concept_id = concepts.id AND s.is_primary = 1
              LIMIT 1
            )
            WHERE EXISTS (
              SELECT 1 FROM concept_senses s
              WHERE s.concept_id = concepts.id AND s.is_primary = 1
            )
              AND TRIM(COALESCE(meaning, '')) != TRIM(
                COALESCE((
                  SELECT s2.gloss FROM concept_senses s2
                  WHERE s2.concept_id = concepts.id AND s2.is_primary = 1
                  LIMIT 1
                ), '')
              )
            """
        )
        writes["concept_meaning_synced"] = int(cur.rowcount if cur.rowcount is not None else 0)

        cur = conn.execute(
            """
            INSERT INTO concept_localizations
              (concept_id, language_code, meaning, context_translation, source_pack, updated_at)
            SELECT c.id, 'en', s.gloss, '', ?, datetime('now')
            FROM concepts c
            JOIN concept_senses s ON s.concept_id = c.id AND s.is_primary = 1
            LEFT JOIN concept_localizations cl
              ON cl.concept_id = c.id AND cl.language_code = 'en'
            WHERE cl.concept_id IS NULL
               OR TRIM(COALESCE(cl.meaning, '')) != TRIM(COALESCE(s.gloss, ''))
            ON CONFLICT(concept_id, language_code) DO UPDATE SET
              meaning = excluded.meaning,
              source_pack = excluded.source_pack,
              updated_at = datetime('now')
            """,
            (source_tag,),
        )
        writes["en_localization_upserts"] = int(cur.rowcount if cur.rowcount is not None else 0)

        cur = conn.execute(
            """
            DELETE FROM word_sentences
            WHERE word_id NOT IN (SELECT id FROM concepts)
            """
        )
        writes["deleted_orphan_word_sentences_by_word"] = int(cur.rowcount or 0)

        cur = conn.execute(
            """
            DELETE FROM word_sentences
            WHERE sentence_id NOT IN (SELECT id FROM sentences)
            """
        )
        writes["deleted_orphan_word_sentences_by_sentence"] = int(cur.rowcount or 0)

        cur = conn.execute(
            """
            DELETE FROM word_exercises
            WHERE word_id NOT IN (SELECT id FROM concepts)
            """
        )
        writes["deleted_orphan_word_exercises"] = int(cur.rowcount or 0)

        cur = conn.execute(
            """
            DELETE FROM user_exercise_history
            WHERE exercise_id NOT IN (SELECT id FROM word_exercises)
            """
        )
        writes["deleted_orphan_exercise_history"] = int(cur.rowcount or 0)

        cur = conn.execute(
            """
            DELETE FROM user_attempts
            WHERE word_id NOT IN (SELECT id FROM concepts)
            """
        )
        writes["deleted_orphan_attempts"] = int(cur.rowcount or 0)

        cur = conn.execute(
            """
            DELETE FROM concepts
            WHERE id NOT IN (SELECT DISTINCT concept_id FROM concept_curriculum_map)
              AND id NOT IN (SELECT DISTINCT concept_id FROM unit_concepts)
              AND id NOT IN (SELECT DISTINCT word_id FROM word_exercises)
              AND id NOT IN (SELECT DISTINCT word_id FROM word_sentences)
              AND (
                TRIM(COALESCE(meaning, '')) = ''
                OR id NOT IN (
                  SELECT concept_id FROM concept_senses WHERE is_primary = 1
                )
              )
            """
        )
        writes["deleted_dangling_concepts"] = int(cur.rowcount or 0)

        cur = conn.execute(
            """
            DELETE FROM concept_senses
            WHERE concept_id NOT IN (SELECT id FROM concepts)
            """
        )
        writes["deleted_orphan_concept_senses"] = int(cur.rowcount or 0)

        cur = conn.execute(
            """
            DELETE FROM concept_localizations
            WHERE concept_id NOT IN (SELECT id FROM concepts)
            """
        )
        writes["deleted_orphan_localizations"] = int(cur.rowcount or 0)

        conn.commit()
        return writes
    except Exception:
        conn.rollback()
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description="Global cleanup for learning_path.db")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--apply", action="store_true", help="Apply changes; default is dry-run")
    parser.add_argument("--source-tag", default="global_cleanup_2026-02-12")
    parser.add_argument("--report-dir", default="docs/reports")
    parser.add_argument("--backup-dir", default="backups")
    args = parser.parse_args()

    root = _repo_root()
    db_path = root / args.db
    if not db_path.exists():
        print(json.dumps({"ok": False, "error": f"DB not found: {db_path}"}))
        return 1

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys=ON")
    conn.execute("PRAGMA busy_timeout = 20000")

    before = _snapshot(conn)
    backup_path = None
    writes: Dict[str, int] = {}
    try:
        if args.apply:
            backup_dir = root / args.backup_dir
            backup_dir.mkdir(parents=True, exist_ok=True)
            stamp = dt.datetime.now().strftime("%Y-%m-%d_%H%M%S")
            backup_path = backup_dir / f"learning_path_pre_global_cleanup_{stamp}.db"
            shutil.copy2(db_path, backup_path)
            writes = _apply_cleanup(conn, args.source_tag)

        after = _snapshot(conn)
    finally:
        conn.close()

    report = {
        "date": dt.date.today().isoformat(),
        "db": str(db_path),
        "apply": bool(args.apply),
        "backup": str(backup_path) if backup_path else None,
        "before": before,
        "writes": writes,
        "after": after,
    }

    report_dir = root / args.report_dir
    report_dir.mkdir(parents=True, exist_ok=True)
    report_path = report_dir / f"global_data_cleanup_{dt.date.today().isoformat()}.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    print(json.dumps(report, ensure_ascii=False))
    print(f"Report: {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
