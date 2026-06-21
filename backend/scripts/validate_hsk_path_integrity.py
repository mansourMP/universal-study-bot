#!/usr/bin/env python3
"""Validate canonical HSK path integrity for release checks."""

from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _q1(conn: sqlite3.Connection, sql: str, params: tuple = ()) -> int:
    return int(conn.execute(sql, params).fetchone()[0])


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate HSK path integrity")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--standard", default="HSK3.0")
    parser.add_argument("--min-langs", type=int, default=36)
    args = parser.parse_args()

    repo_root = _repo_root()
    db_path = repo_root / args.db
    if not db_path.exists():
        print(json.dumps({"ok": False, "error": f"DB not found: {db_path}"}))
        return 1

    standard = args.standard.upper()
    conn = sqlite3.connect(str(db_path), timeout=20)
    try:
        conn.execute("PRAGMA busy_timeout = 20000")

        checks = {
            "core_rows": _q1(
                conn,
                "SELECT COUNT(*) FROM concept_curriculum_map WHERE standard=? AND band='core'",
                (standard,),
            ),
            "core_distinct": _q1(
                conn,
                "SELECT COUNT(DISTINCT concept_id) FROM concept_curriculum_map WHERE standard=? AND band='core'",
                (standard,),
            ),
            "core_dup_across_levels": _q1(
                conn,
                """
                SELECT COUNT(*) FROM (
                  SELECT concept_id
                  FROM concept_curriculum_map
                  WHERE standard=? AND band='core'
                  GROUP BY concept_id
                  HAVING COUNT(DISTINCT level) > 1
                )
                """,
                (standard,),
            ),
            "legacy_unit_concepts_rows": _q1(
                conn,
                "SELECT COUNT(*) FROM unit_concepts WHERE unit_id NOT LIKE 'UNIT_HSK%_%'",
            ),
            "unit_hsk_dup_concepts": _q1(
                conn,
                """
                SELECT COUNT(*) FROM (
                  SELECT concept_id
                  FROM unit_concepts
                  WHERE unit_id LIKE 'UNIT_HSK%_%'
                  GROUP BY concept_id
                  HAVING COUNT(DISTINCT unit_id) > 1
                )
                """,
            ),
            "missing_core_in_unit_hsk": _q1(
                conn,
                """
                SELECT COUNT(*) FROM (
                  SELECT DISTINCT concept_id
                  FROM concept_curriculum_map
                  WHERE standard=? AND band='core'
                  EXCEPT
                  SELECT DISTINCT concept_id
                  FROM unit_concepts
                  WHERE unit_id LIKE 'UNIT_HSK%_%'
                )
                """,
                (standard,),
            ),
            "missing_core_sentence_links": _q1(
                conn,
                """
                SELECT COUNT(*) FROM (
                  SELECT DISTINCT concept_id
                  FROM concept_curriculum_map
                  WHERE standard=? AND band='core'
                  EXCEPT
                  SELECT DISTINCT word_id
                  FROM word_sentences
                )
                """,
                (standard,),
            ),
            "missing_core_localizations": _q1(
                conn,
                """
                SELECT COUNT(*) FROM (
                  SELECT DISTINCT concept_id
                  FROM concept_curriculum_map
                  WHERE standard=? AND band='core'
                  EXCEPT
                  SELECT DISTINCT concept_id
                  FROM concept_localizations
                  WHERE TRIM(COALESCE(meaning,'')) != ''
                )
                """,
                (standard,),
            ),
            "core_below_min_langs": _q1(
                conn,
                f"""
                WITH core AS (
                  SELECT DISTINCT concept_id
                  FROM concept_curriculum_map
                  WHERE standard=? AND band='core'
                ),
                t AS (
                  SELECT concept_id, COUNT(*) AS langs
                  FROM concept_localizations
                  WHERE concept_id IN (SELECT concept_id FROM core)
                    AND TRIM(COALESCE(meaning,'')) != ''
                  GROUP BY concept_id
                )
                SELECT COUNT(*) FROM t WHERE langs < {int(args.min_langs)}
                """,
                (standard,),
            ),
        }

        # Fail conditions for strict release integrity.
        fail = (
            checks["core_distinct"] == 0
            or checks["core_dup_across_levels"] > 0
            or checks["legacy_unit_concepts_rows"] > 0
            or checks["unit_hsk_dup_concepts"] > 0
            or checks["missing_core_in_unit_hsk"] > 0
            or checks["missing_core_sentence_links"] > 0
            or checks["missing_core_localizations"] > 0
            or checks["core_below_min_langs"] > 0
        )

        print(json.dumps({"ok": not fail, "standard": standard, "checks": checks}))
        return 1 if fail else 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())

