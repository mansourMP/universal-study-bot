#!/usr/bin/env python3
"""Audit and lock canonical HSK mappings (core vs extension) in DB.

This script makes HSK scope explicit and removes ambiguity around counts.
It compares local pack sizes against official target profiles (HSK2.0/HSK3.0),
maps pack rows to `concepts`, and can persist the mapping in
`concept_curriculum_map`.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sqlite3
from pathlib import Path
from typing import Dict, List, Sequence, Tuple


TARGETS_BY_STANDARD = {
    # HSK 2.0 incremental targets (1..6).
    "HSK2.0": {
        1: 150,
        2: 150,
        3: 300,
        4: 600,
        5: 1300,
        6: 2500,
    },
    # HSK 3.0 incremental targets (1..6, and 7-9 combined as one band).
    "HSK3.0": {
        1: 500,
        2: 772,
        3: 973,
        4: 1000,
        5: 1071,
        6: 1140,
        7: 5636,
    },
}


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _normalize_pinyin(value: str | None) -> str:
    if not value:
        return ""
    return re.sub(r"\s+", " ", value.strip().lower())


def _load_overrides(path: Path | None) -> Dict:
    if path is None or not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        return {}
    return data


def _ensure_curriculum_table(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS concept_curriculum_map (
            concept_id TEXT NOT NULL,
            standard TEXT NOT NULL,
            level TEXT NOT NULL,
            band TEXT NOT NULL DEFAULT 'core',
            source TEXT,
            metadata TEXT,
            created_at TEXT DEFAULT (datetime('now')),
            PRIMARY KEY (concept_id, standard, level, band)
        );

        CREATE INDEX IF NOT EXISTS idx_ccm_standard_level
            ON concept_curriculum_map(standard, level, band);
        CREATE INDEX IF NOT EXISTS idx_ccm_concept
            ON concept_curriculum_map(concept_id);
        """
    )


def _load_pack_rows(pack_path: Path) -> List[Dict[str, str]]:
    with pack_path.open("r", encoding="utf-8") as f:
        data = json.load(f)

    rows = data.get("vocabulary", [])
    out: List[Dict[str, str]] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        hanzi = str(row.get("hanzi", "")).strip()
        pinyin = str(row.get("pinyin", "")).strip()
        if not hanzi:
            continue
        out.append({"hanzi": hanzi, "pinyin": pinyin})
    return out


def _resolve_concept_id(
    conn: sqlite3.Connection,
    hanzi: str,
    pinyin: str,
    manual_key_map: Dict[str, str] | None = None,
) -> Tuple[str | None, str]:
    """Return (concept_id, resolution_status)."""
    manual_key_map = manual_key_map or {}
    key = f"{hanzi}|{pinyin}"
    if key in manual_key_map:
        forced = str(manual_key_map[key])
        row = conn.execute("SELECT id FROM concepts WHERE id = ?", (forced,)).fetchone()
        if row is not None:
            return forced, "manual_override"

    rows = conn.execute(
        "SELECT id, pinyin FROM concepts WHERE text = ? ORDER BY id",
        (hanzi,),
    ).fetchall()

    if not rows:
        return None, "missing"
    if len(rows) == 1:
        return str(rows[0][0]), "exact"

    want = _normalize_pinyin(pinyin)
    if want:
        by_pinyin = [r for r in rows if _normalize_pinyin(r[1]) == want]
        if len(by_pinyin) == 1:
            return str(by_pinyin[0][0]), "disambiguated_by_pinyin"

    # Deterministic fallback, but flagged for manual review.
    return str(rows[0][0]), "ambiguous_fallback"


def _unit_words_for_level(conn: sqlite3.Connection, level: int) -> List[str]:
    pattern = f"UNIT_HSK{level}_%"
    rows = conn.execute(
        """
        SELECT DISTINCT concept_id
        FROM unit_concepts
        WHERE unit_id LIKE ?
        ORDER BY concept_id
        """,
        (pattern,),
    ).fetchall()
    return [str(r[0]) for r in rows]


def main() -> int:
    parser = argparse.ArgumentParser(description="Lock HSK curriculum mapping")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--pack-dir", default="backend/content/packs")
    parser.add_argument("--standard", default="HSK3.0")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--report-dir", default="docs/reports")
    parser.add_argument(
        "--overrides",
        default="docs/specs/hsk_lock_overrides_v1.json",
        help="JSON file for manual disambiguation and level additions",
    )
    parser.add_argument(
        "--allow-cross-level-duplicates",
        action="store_true",
        help="Allow the same concept_id to appear in multiple HSK levels",
    )
    parser.add_argument(
        "--enforce-target",
        action="store_true",
        help="Trim per-level core mappings to official target_incremental counts",
    )
    args = parser.parse_args()

    repo_root = _repo_root()
    db_path = repo_root / args.db
    pack_dir = repo_root / args.pack_dir
    report_dir = repo_root / args.report_dir
    report_dir.mkdir(parents=True, exist_ok=True)
    overrides_path = repo_root / args.overrides

    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1

    standard = args.standard.strip().upper()
    if standard not in TARGETS_BY_STANDARD:
        print(f"Unsupported --standard '{args.standard}'.")
        print(f"Supported: {', '.join(sorted(TARGETS_BY_STANDARD.keys()))}")
        return 1
    targets = TARGETS_BY_STANDARD[standard]

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row

    levels_report: List[Dict] = []
    total_core_ids: set[str] = set()
    total_extension_ids: set[str] = set()
    globally_assigned_core: set[str] = set()
    overrides = _load_overrides(overrides_path)
    manual_key_map = overrides.get("hanzi_pinyin_to_concept_id", {}) if isinstance(overrides, dict) else {}
    level_additions_map = overrides.get("level_core_additions", {}) if isinstance(overrides, dict) else {}
    level_removals_map = overrides.get("level_core_removals", {}) if isinstance(overrides, dict) else {}

    try:
        if args.apply:
            _ensure_curriculum_table(conn)

        for level in sorted(targets.keys()):
            pack_path = pack_dir / f"zh_hsk{level}_vocab.json"
            if not pack_path.exists():
                levels_report.append(
                    {
                        "level": f"HSK{level}",
                        "status": "missing_pack_file",
                        "pack_path": str(pack_path),
                    }
                )
                continue

            rows = _load_pack_rows(pack_path)
            target = targets[level]
            resolved_ids: List[str] = []
            status_counts = {
                "exact": 0,
                "disambiguated_by_pinyin": 0,
                "ambiguous_fallback": 0,
                "missing": 0,
                "manual_override": 0,
            }
            ambiguous_samples: List[Dict[str, str]] = []
            missing_samples: List[Dict[str, str]] = []

            for row in rows:
                concept_id, status = _resolve_concept_id(
                    conn,
                    row["hanzi"],
                    row["pinyin"],
                    manual_key_map=manual_key_map,
                )
                status_counts[status] += 1
                if concept_id:
                    resolved_ids.append(concept_id)
                if status == "ambiguous_fallback" and len(ambiguous_samples) < 20:
                    ambiguous_samples.append(
                        {
                            "hanzi": row["hanzi"],
                            "pinyin": row["pinyin"],
                            "chosen_concept_id": concept_id or "",
                        }
                    )
                if status == "missing" and len(missing_samples) < 20:
                    missing_samples.append(
                        {
                            "hanzi": row["hanzi"],
                            "pinyin": row["pinyin"],
                        }
                    )

            # Keep deterministic order, unique IDs only once per level.
            seen = set()
            core_ids = [cid for cid in resolved_ids if not (cid in seen or seen.add(cid))]
            level_label = f"HSK{level}"

            # Manual include/remove layer for deterministic corrections.
            manual_added = 0
            manual_removed = 0
            for cid in level_additions_map.get(level_label, []):
                cid_s = str(cid)
                row = conn.execute("SELECT id FROM concepts WHERE id = ?", (cid_s,)).fetchone()
                if row is None:
                    continue
                if cid_s not in core_ids:
                    core_ids.append(cid_s)
                    manual_added += 1
            if level_label in level_removals_map:
                removals = {str(cid) for cid in level_removals_map[level_label]}
                before = len(core_ids)
                core_ids = [cid for cid in core_ids if cid not in removals]
                manual_removed = before - len(core_ids)

            cross_level_duplicates = 0
            if not args.allow_cross_level_duplicates:
                filtered = []
                for cid in core_ids:
                    if cid in globally_assigned_core:
                        cross_level_duplicates += 1
                        continue
                    filtered.append(cid)
                    globally_assigned_core.add(cid)
                core_ids = filtered

            trimmed_for_target = 0
            target_underflow = max(0, target - len(core_ids))
            overflow_ids: List[str] = []
            if args.enforce_target:
                if len(core_ids) > target:
                    overflow_ids = core_ids[target:]
                    trimmed_for_target = len(overflow_ids)
                    core_ids = core_ids[:target]

            total_core_ids.update(core_ids)

            unit_ids = _unit_words_for_level(conn, level)
            extension_ids = sorted(set(unit_ids) - set(core_ids))
            total_extension_ids.update(extension_ids)

            if args.apply:
                conn.execute(
                    "DELETE FROM concept_curriculum_map WHERE standard = ? AND level = ?",
                    (standard, level_label),
                )
                conn.executemany(
                    """
                    INSERT OR REPLACE INTO concept_curriculum_map
                    (concept_id, standard, level, band, source, metadata, created_at)
                    VALUES (?, ?, ?, 'core', ?, ?, datetime('now'))
                    """,
                    [
                        (
                            cid,
                            standard,
                            level_label,
                            pack_path.name,
                            json.dumps({"source": "pack", "level": level_label}),
                        )
                        for cid in core_ids
                    ],
                )
                if extension_ids:
                    conn.executemany(
                        """
                        INSERT OR REPLACE INTO concept_curriculum_map
                        (concept_id, standard, level, band, source, metadata, created_at)
                        VALUES (?, ?, ?, 'extension', ?, ?, datetime('now'))
                        """,
                        [
                            (
                                cid,
                                standard,
                                level_label,
                                "unit_concepts",
                                json.dumps({"source": "units", "level": level_label}),
                            )
                            for cid in extension_ids
                        ],
                    )

            levels_report.append(
                {
                    "level": f"HSK{level}",
                    "target_incremental": target,
                    "pack_entries": len(rows),
                    "pack_unique_hanzi": len({r["hanzi"] for r in rows}),
                    "target_delta": len(rows) - target,
                    "core_mapped_concepts": len(core_ids),
                    "manual_added": manual_added,
                    "manual_removed": manual_removed,
                    "extension_from_units": len(extension_ids),
                    "trimmed_for_target": trimmed_for_target,
                    "target_underflow": target_underflow,
                    "resolution": status_counts,
                    "cross_level_duplicates_skipped": cross_level_duplicates,
                    "overflow_samples": overflow_ids[:20],
                    "ambiguous_samples": ambiguous_samples,
                    "missing_samples": missing_samples,
                }
            )

        if args.apply:
            conn.commit()

        summary = {
            "date": dt.date.today().isoformat(),
            "standard": standard,
            "db": str(args.db),
            "pack_dir": str(args.pack_dir),
            "apply": args.apply,
            "levels": levels_report,
            "totals": {
                "core_unique_concepts": len(total_core_ids),
                "extension_unique_concepts": len(total_extension_ids),
            },
        }

        report_path = report_dir / f"hsk_standard_lock_{dt.date.today().isoformat()}.json"
        report_path.write_text(
            json.dumps(summary, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

        print(f"HSK standard audit complete. apply={args.apply}")
        print(f"Report: {report_path}")
        for level in levels_report:
            if level.get("status") == "missing_pack_file":
                print(f"{level['level']}: missing pack file")
                continue
            print(
                f"{level['level']}: pack={level['pack_entries']} "
                f"target={level['target_incremental']} "
                f"delta={level['target_delta']} "
                f"core={level['core_mapped_concepts']} "
                f"ext={level['extension_from_units']} "
                f"manual+={level['manual_added']} "
                f"manual-={level['manual_removed']} "
                f"trim={level['trimmed_for_target']} "
                f"under={level['target_underflow']} "
                f"dup_skip={level['cross_level_duplicates_skipped']} "
                f"ambiguous={level['resolution']['ambiguous_fallback']} "
                f"override={level['resolution']['manual_override']} "
                f"missing={level['resolution']['missing']}"
            )

        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
