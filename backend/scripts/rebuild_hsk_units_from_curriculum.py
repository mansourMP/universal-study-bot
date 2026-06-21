#!/usr/bin/env python3
"""Rebuild UNIT_HSK* units from curriculum core mapping.

This script makes the path wiring deterministic by generating units and
unit_concepts directly from concept_curriculum_map (default: HSK3.0 core band).
It does not touch concepts, localizations, or sentences.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import sqlite3
from pathlib import Path


DEFAULT_LEVELS = ["HSK1", "HSK2", "HSK3", "HSK4", "HSK5", "HSK6", "HSK7"]


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _normalize_levels(raw: str) -> list[str]:
    if not raw.strip():
        return list(DEFAULT_LEVELS)
    out: list[str] = []
    for token in raw.split(","):
        t = token.strip().upper()
        if not t:
            continue
        if t.startswith("HSK"):
            num = "".join(ch for ch in t if ch.isdigit())
            if num:
                out.append(f"HSK{int(num)}")
        elif t.isdigit():
            out.append(f"HSK{int(t)}")
    return out or list(DEFAULT_LEVELS)


def _words_per_unit(level: str, base: int, advanced: int, advanced_start: int) -> int:
    try:
        num = int("".join(ch for ch in level if ch.isdigit()) or "1")
    except ValueError:
        num = 1
    if num >= advanced_start:
        return max(1, advanced)
    return max(1, base)


def _load_core_words(
    conn: sqlite3.Connection,
    standard: str,
    levels: list[str],
    band: str,
) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for level in levels:
        rows = conn.execute(
            """
            SELECT concept_id
            FROM concept_curriculum_map
            WHERE standard = ? AND level = ? AND band = ?
            ORDER BY concept_id
            """,
            (standard, level, band),
        ).fetchall()
        out[level] = [str(r[0]) for r in rows]
    return out


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Rebuild UNIT_HSK* units and path mappings from curriculum map"
    )
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--standard", default="HSK3.0")
    parser.add_argument("--band", default="core")
    parser.add_argument(
        "--levels",
        default="",
        help="Comma-separated levels to rebuild (default: HSK1..HSK7)",
    )
    parser.add_argument(
        "--words-per-unit",
        type=int,
        default=16,
        help="Words per unit for non-advanced levels",
    )
    parser.add_argument(
        "--words-per-unit-advanced",
        type=int,
        default=20,
        help="Words per unit for advanced levels",
    )
    parser.add_argument(
        "--advanced-start",
        type=int,
        default=7,
        help="First HSK level treated as advanced for unit sizing",
    )
    parser.add_argument(
        "--report-dir",
        default="docs/reports",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Write changes to DB. Without this flag, runs dry-run only.",
    )
    args = parser.parse_args()

    repo_root = _repo_root()
    db_path = repo_root / args.db
    report_dir = repo_root / args.report_dir
    report_dir.mkdir(parents=True, exist_ok=True)

    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1

    levels = _normalize_levels(args.levels)
    standard = args.standard.strip().upper()
    band = args.band.strip().lower()

    conn = sqlite3.connect(str(db_path), timeout=20)
    conn.row_factory = sqlite3.Row
    try:
        conn.execute("PRAGMA busy_timeout = 20000")
        words_by_level = _load_core_words(conn, standard, levels, band)

        plan_units: list[dict] = []
        plan_mappings: list[tuple[str, str, int]] = []
        per_level_summary: list[dict] = []

        for level in levels:
            words = words_by_level.get(level, [])
            if not words:
                per_level_summary.append(
                    {
                        "level": level,
                        "core_words": 0,
                        "words_per_unit": _words_per_unit(
                            level,
                            args.words_per_unit,
                            args.words_per_unit_advanced,
                            args.advanced_start,
                        ),
                        "units": 0,
                    }
                )
                continue

            per_unit = _words_per_unit(
                level,
                args.words_per_unit,
                args.words_per_unit_advanced,
                args.advanced_start,
            )
            unit_count = math.ceil(len(words) / per_unit)

            for i in range(unit_count):
                unit_number = i + 1
                unit_id = f"UNIT_{level}_{unit_number:03d}"
                chunk = words[i * per_unit : (i + 1) * per_unit]
                objectives = json.dumps(
                    [
                        "Learn and retain this core vocabulary cluster.",
                        "Use target words in listening, reading, and production tasks.",
                        "Stabilize recall via spaced repetition checkpoints.",
                    ],
                    ensure_ascii=False,
                )
                plan_units.append(
                    {
                        "id": unit_id,
                        "title": f"{level} Core Unit {unit_number:03d}",
                        "unit_number": unit_number,
                        "level": level,
                        "description": (
                            f"Auto-generated from {standard} {band} vocabulary set."
                        ),
                        "learning_objectives": objectives,
                        "estimated_hours": 2.0,
                        "word_count": len(chunk),
                    }
                )
                for seq, concept_id in enumerate(chunk, start=1):
                    plan_mappings.append((unit_id, concept_id, seq))

            per_level_summary.append(
                {
                    "level": level,
                    "core_words": len(words),
                    "words_per_unit": per_unit,
                    "units": unit_count,
                }
            )

        total_core_words = sum(int(x["core_words"]) for x in per_level_summary)

        report = {
            "date": dt.date.today().isoformat(),
            "db": str(args.db),
            "standard": standard,
            "band": band,
            "levels": per_level_summary,
            "totals": {
                "core_words": total_core_words,
                "units_planned": len(plan_units),
                "mappings_planned": len(plan_mappings),
            },
            "apply": bool(args.apply),
        }

        if args.apply:
            with conn:
                # Replace only UNIT_HSK* mappings; leave numeric legacy rows untouched.
                conn.execute("DELETE FROM unit_concepts WHERE unit_id LIKE 'UNIT_HSK%_%'")
                conn.execute("DELETE FROM units WHERE id LIKE 'UNIT_HSK%_%'")
                conn.executemany(
                    """
                    INSERT INTO units
                    (id, title, unit_number, level, description, learning_objectives, estimated_hours)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    [
                        (
                            row["id"],
                            row["title"],
                            row["unit_number"],
                            row["level"],
                            row["description"],
                            row["learning_objectives"],
                            row["estimated_hours"],
                        )
                        for row in plan_units
                    ],
                )
                conn.executemany(
                    """
                    INSERT INTO unit_concepts (unit_id, concept_id, sequence)
                    VALUES (?, ?, ?)
                    """,
                    plan_mappings,
                )

            mapped_rows = conn.execute(
                "SELECT COUNT(*) FROM unit_concepts WHERE unit_id LIKE 'UNIT_HSK%_%'"
            ).fetchone()[0]
            mapped_distinct = conn.execute(
                "SELECT COUNT(DISTINCT concept_id) FROM unit_concepts WHERE unit_id LIKE 'UNIT_HSK%_%'"
            ).fetchone()[0]
            missing_core = conn.execute(
                """
                SELECT COUNT(*) FROM (
                  SELECT DISTINCT concept_id
                  FROM concept_curriculum_map
                  WHERE standard = ? AND band = ?
                  EXCEPT
                  SELECT DISTINCT concept_id
                  FROM unit_concepts
                  WHERE unit_id LIKE 'UNIT_HSK%_%'
                )
                """,
                (standard, band),
            ).fetchone()[0]
            report["post_apply"] = {
                "mapped_rows": int(mapped_rows),
                "mapped_distinct_words": int(mapped_distinct),
                "missing_core_words": int(missing_core),
            }

        report_path = report_dir / f"hsk_unit_rebuild_{dt.date.today().isoformat()}.json"
        report_path.write_text(
            json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
        )

        print(
            json.dumps(
                {
                    "standard": standard,
                    "band": band,
                    "apply": bool(args.apply),
                    "core_words": total_core_words,
                    "units_planned": len(plan_units),
                    "mappings_planned": len(plan_mappings),
                    **(report.get("post_apply", {})),
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

