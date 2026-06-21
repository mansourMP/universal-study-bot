#!/usr/bin/env python3
"""Canonicalize HSK path/unit structure for runtime consistency.

What this script does:
1) Uses UNIT_HSK* mappings in unit_concepts as canonical source.
2) Ensures one-level ownership per concept (keeps lowest HSK level).
3) Optionally purges legacy non-UNIT_HSK mappings from unit_concepts.
4) Resequences unit_concepts.sequence per unit after cleanup.
5) Rebuilds concept_curriculum_map HSK3.0 core from canonical UNIT_HSK mappings.

It does NOT modify concepts, localizations, sentences, or user mastery tables.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sqlite3
from collections import defaultdict
from pathlib import Path


UNIT_ID_RE = re.compile(r"^UNIT_HSK(\d+)_(\d{3})$")


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _level_num_from_unit_id(unit_id: str) -> int:
    m = UNIT_ID_RE.match(unit_id)
    if not m:
        return 999
    return int(m.group(1))


def _load_unit_rows(conn: sqlite3.Connection) -> list[tuple[str, str, int]]:
    rows = conn.execute(
        """
        SELECT unit_id, concept_id, sequence
        FROM unit_concepts
        WHERE unit_id LIKE 'UNIT_HSK%_%'
        ORDER BY unit_id ASC, sequence ASC, concept_id ASC
        """
    ).fetchall()
    return [(str(r[0]), str(r[1]), int(r[2] or 0)) for r in rows]


def _build_canonical_assignments(
    rows: list[tuple[str, str, int]],
) -> tuple[
    dict[str, str],  # concept -> canonical_unit_id
    dict[str, list[str]],  # concept -> levels seen (unit ids)
]:
    by_concept: dict[str, list[str]] = defaultdict(list)
    for unit_id, concept_id, _ in rows:
        by_concept[concept_id].append(unit_id)

    canonical_unit: dict[str, str] = {}
    for concept_id, unit_ids in by_concept.items():
        unique_units = sorted(set(unit_ids), key=lambda u: (_level_num_from_unit_id(u), u))
        canonical_unit[concept_id] = unique_units[0]

    return canonical_unit, by_concept


def main() -> int:
    parser = argparse.ArgumentParser(description="Canonicalize HSK path structure")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--standard", default="HSK3.0")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument(
        "--purge-legacy-unit-concepts",
        action="store_true",
        help="Delete non-UNIT_HSK mappings from unit_concepts",
    )
    parser.add_argument(
        "--report-dir",
        default="docs/reports",
    )
    args = parser.parse_args()

    repo_root = _repo_root()
    db_path = repo_root / args.db
    report_dir = repo_root / args.report_dir
    report_dir.mkdir(parents=True, exist_ok=True)

    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1

    conn = sqlite3.connect(str(db_path), timeout=20)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout = 20000")

    try:
        unit_rows = _load_unit_rows(conn)
        if not unit_rows:
            print("No UNIT_HSK mappings found in unit_concepts.")
            return 1

        canonical_unit, by_concept = _build_canonical_assignments(unit_rows)
        dup_concepts = {
            concept_id: sorted(set(unit_ids), key=lambda u: (_level_num_from_unit_id(u), u))
            for concept_id, unit_ids in by_concept.items()
            if len(set(unit_ids)) > 1
        }

        delete_noncanonical: list[tuple[str, str]] = []
        for unit_id, concept_id, _ in unit_rows:
            if canonical_unit.get(concept_id) != unit_id:
                delete_noncanonical.append((unit_id, concept_id))

        # Build kept mappings grouped by unit, preserving existing unit assignment.
        kept_by_unit: dict[str, list[str]] = defaultdict(list)
        for unit_id, concept_id, _ in unit_rows:
            if canonical_unit.get(concept_id) == unit_id:
                kept_by_unit[unit_id].append(concept_id)
        for unit_id in list(kept_by_unit.keys()):
            # stable deterministic order by concept_id for reproducibility
            kept_by_unit[unit_id] = sorted(set(kept_by_unit[unit_id]))

        legacy_rows = conn.execute(
            """
            SELECT COUNT(*) FROM unit_concepts
            WHERE unit_id NOT LIKE 'UNIT_HSK%_%'
            """
        ).fetchone()[0]

        # Planned curriculum rows from canonical assignments.
        curriculum_rows: list[tuple[str, str, str, str, str]] = []
        for concept_id, unit_id in sorted(canonical_unit.items()):
            m = UNIT_ID_RE.match(unit_id)
            if not m:
                continue
            level_label = f"HSK{int(m.group(1))}"
            curriculum_rows.append(
                (
                    concept_id,
                    args.standard.upper(),
                    level_label,
                    "core",
                    "canonicalize_hsk_path_structure.py",
                )
            )

        report = {
            "date": dt.date.today().isoformat(),
            "db": str(args.db),
            "standard": args.standard.upper(),
            "apply": bool(args.apply),
            "purge_legacy_unit_concepts": bool(args.purge_legacy_unit_concepts),
            "stats_before": {
                "unit_hsk_rows": len(unit_rows),
                "unit_hsk_distinct_words": len(set(c for _, c, _ in unit_rows)),
                "duplicate_concepts_across_levels": len(dup_concepts),
                "duplicate_row_deletions_planned": len(delete_noncanonical),
                "legacy_non_unit_hsk_rows": int(legacy_rows),
                "curriculum_core_rows_planned": len(curriculum_rows),
                "curriculum_core_distinct_words_planned": len(
                    {r[0] for r in curriculum_rows}
                ),
            },
            "duplicate_samples": [
                {"concept_id": cid, "unit_ids": uids[:6]}
                for cid, uids in sorted(dup_concepts.items())[:30]
            ],
        }

        if args.apply:
            with conn:
                # Delete non-canonical UNIT_HSK duplicates.
                conn.executemany(
                    "DELETE FROM unit_concepts WHERE unit_id = ? AND concept_id = ?",
                    delete_noncanonical,
                )

                # Optionally purge legacy mappings.
                if args.purge_legacy_unit_concepts:
                    conn.execute(
                        "DELETE FROM unit_concepts WHERE unit_id NOT LIKE 'UNIT_HSK%_%'"
                    )

                # Resequence each UNIT_HSK unit.
                unit_ids = [
                    str(r[0])
                    for r in conn.execute(
                        """
                        SELECT DISTINCT unit_id
                        FROM unit_concepts
                        WHERE unit_id LIKE 'UNIT_HSK%_%'
                        ORDER BY unit_id
                        """
                    ).fetchall()
                ]
                for unit_id in unit_ids:
                    concepts = [
                        str(r[0])
                        for r in conn.execute(
                            """
                            SELECT concept_id
                            FROM unit_concepts
                            WHERE unit_id = ?
                            ORDER BY sequence ASC, concept_id ASC
                            """,
                            (unit_id,),
                        ).fetchall()
                    ]
                    concepts = sorted(set(concepts))
                    conn.execute("DELETE FROM unit_concepts WHERE unit_id = ?", (unit_id,))
                    conn.executemany(
                        """
                        INSERT INTO unit_concepts (unit_id, concept_id, sequence)
                        VALUES (?, ?, ?)
                        """,
                        [(unit_id, cid, idx + 1) for idx, cid in enumerate(concepts)],
                    )

                # Rebuild HSK3.0 map fully from canonical UNIT_HSK mapping.
                conn.execute(
                    "DELETE FROM concept_curriculum_map WHERE standard = ?",
                    (args.standard.upper(),),
                )
                conn.executemany(
                    """
                    INSERT INTO concept_curriculum_map
                    (concept_id, standard, level, band, source, metadata, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, datetime('now'))
                    """,
                    [
                        (
                            concept_id,
                            standard,
                            level,
                            band,
                            source,
                            json.dumps({"source": "unit_hsk_canonical"}),
                        )
                        for concept_id, standard, level, band, source in curriculum_rows
                    ],
                )

            # Post-apply verification.
            dup_after = conn.execute(
                """
                SELECT COUNT(*) FROM (
                  SELECT concept_id
                  FROM concept_curriculum_map
                  WHERE standard = ? AND band = 'core'
                  GROUP BY concept_id
                  HAVING COUNT(DISTINCT level) > 1
                )
                """,
                (args.standard.upper(),),
            ).fetchone()[0]
            missing_core_in_path = conn.execute(
                """
                SELECT COUNT(*) FROM (
                  SELECT DISTINCT concept_id
                  FROM concept_curriculum_map
                  WHERE standard = ? AND band = 'core'
                  EXCEPT
                  SELECT DISTINCT concept_id
                  FROM unit_concepts
                  WHERE unit_id LIKE 'UNIT_HSK%_%'
                )
                """,
                (args.standard.upper(),),
            ).fetchone()[0]
            legacy_after = conn.execute(
                """
                SELECT COUNT(*)
                FROM unit_concepts
                WHERE unit_id NOT LIKE 'UNIT_HSK%_%'
                """
            ).fetchone()[0]
            core_rows_after = conn.execute(
                """
                SELECT COUNT(*)
                FROM concept_curriculum_map
                WHERE standard = ? AND band = 'core'
                """,
                (args.standard.upper(),),
            ).fetchone()[0]
            core_distinct_after = conn.execute(
                """
                SELECT COUNT(DISTINCT concept_id)
                FROM concept_curriculum_map
                WHERE standard = ? AND band = 'core'
                """,
                (args.standard.upper(),),
            ).fetchone()[0]
            report["stats_after"] = {
                "duplicate_concepts_across_levels": int(dup_after),
                "missing_core_words_in_unit_hsk_path": int(missing_core_in_path),
                "legacy_non_unit_hsk_rows": int(legacy_after),
                "curriculum_core_rows": int(core_rows_after),
                "curriculum_core_distinct_words": int(core_distinct_after),
            }

        report_path = (
            report_dir / f"hsk_path_canonicalization_{dt.date.today().isoformat()}.json"
        )
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

        print(
            json.dumps(
                {
                    "apply": bool(args.apply),
                    "dup_concepts_before": report["stats_before"][
                        "duplicate_concepts_across_levels"
                    ],
                    "delete_noncanonical_rows_planned": report["stats_before"][
                        "duplicate_row_deletions_planned"
                    ],
                    "legacy_rows_before": report["stats_before"][
                        "legacy_non_unit_hsk_rows"
                    ],
                    **(report.get("stats_after", {})),
                },
                ensure_ascii=False,
            )
        )
        print(f"Report: {report_path}")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())

