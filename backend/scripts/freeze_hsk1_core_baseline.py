#!/usr/bin/env python3
"""Freeze immutable HSK1 core baseline from learning_path.db.

Outputs:
- docs/specs/hsk1_core_baseline_v1.json
- docs/specs/hsk1_core_baseline_v1.sha256
- docs/reports/hsk1_core_freeze_YYYY-MM-DD.json
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sqlite3
from pathlib import Path
from typing import Any, Dict, List


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _q1(conn: sqlite3.Connection, sql: str, params: tuple = ()) -> int:
    return int(conn.execute(sql, params).fetchone()[0])


def _load_units(conn: sqlite3.Connection) -> List[Dict[str, Any]]:
    rows = conn.execute(
        """
        SELECT id, unit_number, title
        FROM units
        WHERE id LIKE 'UNIT_HSK1_%'
        ORDER BY unit_number ASC
        """
    ).fetchall()
    out: List[Dict[str, Any]] = []
    for row in rows:
        out.append({"unit_id": str(row[0]), "unit_number": int(row[1]), "title": str(row[2] or "")})
    return out


def _load_unit_words(conn: sqlite3.Connection, unit_id: str) -> List[Dict[str, Any]]:
    rows = conn.execute(
        """
        SELECT
          uc.sequence,
          c.id,
          c.text,
          c.pinyin,
          c.meaning,
          cs.sense_id,
          cs.gloss
        FROM unit_concepts uc
        JOIN concepts c ON c.id = uc.concept_id
        LEFT JOIN concept_senses cs
          ON cs.concept_id = c.id AND cs.is_primary = 1
        JOIN concept_curriculum_map m
          ON m.concept_id = c.id
         AND m.standard = 'HSK3.0'
         AND m.level = 'HSK1'
         AND m.band = 'core'
        WHERE uc.unit_id = ?
        ORDER BY uc.sequence ASC, c.id ASC
        """,
        (unit_id,),
    ).fetchall()
    out: List[Dict[str, Any]] = []
    for row in rows:
        out.append(
            {
                "sequence": int(row[0]),
                "word_id": str(row[1]),
                "hanzi": str(row[2] or ""),
                "pinyin": str(row[3] or ""),
                "meaning_en": str(row[4] or ""),
                "sense_id": str(row[5] or f"{row[1]}::s01"),
                "primary_gloss": str(row[6] or row[4] or ""),
            }
        )
    return out


def _canonical_bytes(payload: Dict[str, Any]) -> bytes:
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode("utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Freeze immutable HSK1 core baseline")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--out-json", default="docs/specs/hsk1_core_baseline_v1.json")
    parser.add_argument("--out-sha", default="docs/specs/hsk1_core_baseline_v1.sha256")
    parser.add_argument("--report-dir", default="docs/reports")
    parser.add_argument("--strict-core-count", type=int, default=500)
    parser.add_argument("--strict-units", type=int, default=32)
    parser.add_argument("--strict-unit-min", type=int, default=15)
    parser.add_argument("--strict-unit-max", type=int, default=16)
    args = parser.parse_args()

    root = _repo_root()
    db_path = root / args.db if not Path(args.db).is_absolute() else Path(args.db)
    out_json = root / args.out_json if not Path(args.out_json).is_absolute() else Path(args.out_json)
    out_sha = root / args.out_sha if not Path(args.out_sha).is_absolute() else Path(args.out_sha)
    report_dir = root / args.report_dir if not Path(args.report_dir).is_absolute() else Path(args.report_dir)
    report_dir.mkdir(parents=True, exist_ok=True)
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_sha.parent.mkdir(parents=True, exist_ok=True)

    if not db_path.exists():
        print(json.dumps({"ok": False, "error": f"DB not found: {db_path}"}))
        return 1

    conn = sqlite3.connect(str(db_path), timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout = 30000")

    try:
        units = _load_units(conn)
        core_count = _q1(
            conn,
            """
            SELECT COUNT(DISTINCT concept_id)
            FROM concept_curriculum_map
            WHERE standard='HSK3.0' AND level='HSK1' AND band='core'
            """,
        )

        # Strict guards before freezing.
        if core_count != args.strict_core_count:
            print(
                json.dumps(
                    {
                        "ok": False,
                        "error": "core_count_mismatch",
                        "expected": args.strict_core_count,
                        "actual": core_count,
                    }
                )
            )
            return 1

        if len(units) != args.strict_units:
            print(
                json.dumps(
                    {
                        "ok": False,
                        "error": "unit_count_mismatch",
                        "expected": args.strict_units,
                        "actual": len(units),
                    }
                )
            )
            return 1

        frozen_units: List[Dict[str, Any]] = []
        unit_size_violations: List[Dict[str, Any]] = []
        all_word_ids: List[str] = []

        for unit in units:
            words = _load_unit_words(conn, unit["unit_id"])
            size = len(words)
            if size < args.strict_unit_min or size > args.strict_unit_max:
                unit_size_violations.append(
                    {
                        "unit_id": unit["unit_id"],
                        "unit_number": unit["unit_number"],
                        "size": size,
                        "expected_min": args.strict_unit_min,
                        "expected_max": args.strict_unit_max,
                    }
                )
            frozen_units.append({**unit, "size": size, "words": words})
            all_word_ids.extend([w["word_id"] for w in words])

        unique_word_ids = sorted(set(all_word_ids))
        if len(unique_word_ids) != args.strict_core_count:
            print(
                json.dumps(
                    {
                        "ok": False,
                        "error": "unit_word_coverage_mismatch",
                        "expected_distinct_words": args.strict_core_count,
                        "actual_distinct_words": len(unique_word_ids),
                    }
                )
            )
            return 1

        if unit_size_violations:
            print(
                json.dumps(
                    {
                        "ok": False,
                        "error": "unit_size_violations",
                        "count": len(unit_size_violations),
                        "preview": unit_size_violations[:10],
                    }
                )
            )
            return 1

        payload: Dict[str, Any] = {
            "id": "hsk1_core_baseline_v1",
            "standard": "HSK3.0",
            "level": "HSK1",
            "band": "core",
            "frozen_at_utc": dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            "source_db": str(db_path),
            "stats": {
                "core_distinct_words": core_count,
                "units": len(frozen_units),
                "unit_size_min": min(u["size"] for u in frozen_units),
                "unit_size_max": max(u["size"] for u in frozen_units),
            },
            "units": frozen_units,
        }

        canonical = _canonical_bytes(payload)
        digest = hashlib.sha256(canonical).hexdigest()

        out_json.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        out_sha.write_text(f"{digest}  {out_json.name}\n", encoding="utf-8")

        report = {
            "ok": True,
            "id": payload["id"],
            "sha256": digest,
            "out_json": str(out_json),
            "out_sha": str(out_sha),
            "stats": payload["stats"],
        }
        report_path = report_dir / f"hsk1_core_freeze_{dt.date.today().isoformat()}.json"
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        report["report"] = str(report_path)
        print(json.dumps(report, ensure_ascii=False))
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
