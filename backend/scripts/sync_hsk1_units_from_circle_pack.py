#!/usr/bin/env python3
"""Sync HSK1 unit_concepts from the locked circle pack spec.

Why:
- DB unit_concepts can drift from the approved pack mapping.
- This script restores exact per-unit word assignment and sequence.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import shutil
import sqlite3
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _load_pack(pack_path: Path) -> list[dict]:
    raw = json.loads(pack_path.read_text(encoding="utf-8"))
    units = raw.get("units") or []
    if not units:
        raise ValueError("Pack has no units")
    units = sorted(units, key=lambda u: int(u["unit_number"]))
    return units


def _validate_pack(units: list[dict]) -> None:
    if len(units) != 32:
        raise ValueError(f"Expected 32 units in pack, got {len(units)}")

    seen: set[str] = set()
    for u in units:
        unit_id = str(u["unit_id"])
        size = int(u["size"])
        word_ids = list(u.get("word_ids") or [])
        if len(word_ids) != size:
            raise ValueError(
                f"{unit_id}: size={size} but word_ids={len(word_ids)}"
            )
        for wid in word_ids:
            if wid in seen:
                raise ValueError(f"Duplicate word_id in pack: {wid}")
            seen.add(wid)

    if len(seen) != 500:
        raise ValueError(f"Expected 500 unique HSK1 words, got {len(seen)}")


def _fetch_current_map(conn: sqlite3.Connection, unit_ids: list[str]) -> dict[str, set[str]]:
    placeholders = ",".join("?" for _ in unit_ids)
    rows = conn.execute(
        f"""
        SELECT unit_id, concept_id
        FROM unit_concepts
        WHERE unit_id IN ({placeholders})
        """,
        unit_ids,
    ).fetchall()
    out: dict[str, set[str]] = {uid: set() for uid in unit_ids}
    for unit_id, concept_id in rows:
        out.setdefault(str(unit_id), set()).add(str(concept_id))
    return out


def _build_pack_map(units: list[dict]) -> dict[str, set[str]]:
    return {str(u["unit_id"]): set(str(w) for w in (u.get("word_ids") or [])) for u in units}


def _write_moves_csv(
    path: Path,
    current_word_to_unit: dict[str, str],
    target_word_to_unit: dict[str, str],
) -> int:
    moved = []
    for wid, target_unit in target_word_to_unit.items():
        old_unit = current_word_to_unit.get(wid)
        if old_unit != target_unit:
            moved.append(
                {
                    "word_id": wid,
                    "from_unit": old_unit or "",
                    "to_unit": target_unit,
                }
            )

    moved.sort(key=lambda r: (r["from_unit"], r["to_unit"], r["word_id"]))
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["word_id", "from_unit", "to_unit"])
        writer.writeheader()
        writer.writerows(moved)
    return len(moved)


def _validate_words_exist(conn: sqlite3.Connection, word_ids: set[str]) -> None:
    placeholders = ",".join("?" for _ in word_ids)
    rows = conn.execute(
        f"SELECT id FROM concepts WHERE id IN ({placeholders})",
        sorted(word_ids),
    ).fetchall()
    found = {str(r[0]) for r in rows}
    missing = sorted(word_ids - found)
    if missing:
        raise ValueError(f"Pack contains word_ids missing in concepts: {missing[:10]}")


def _backup_db(db_path: Path, backup_dir: Path) -> Path:
    backup_dir.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out = backup_dir / f"{db_path.name}.hsk1_sync_{stamp}.bak"
    shutil.copy2(db_path, out)
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync HSK1 DB units from circle pack")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--pack", default="docs/specs/hsk1_unit_circle_pack_v1.json")
    parser.add_argument("--report-dir", default="docs/reports")
    parser.add_argument("--backup-dir", default="backups")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    root = _repo_root()
    db_path = root / args.db
    pack_path = root / args.pack
    report_dir = root / args.report_dir
    backup_dir = root / args.backup_dir
    report_dir.mkdir(parents=True, exist_ok=True)

    if not db_path.exists():
        raise FileNotFoundError(f"DB not found: {db_path}")
    if not pack_path.exists():
        raise FileNotFoundError(f"Pack not found: {pack_path}")

    units = _load_pack(pack_path)
    _validate_pack(units)
    unit_ids = [str(u["unit_id"]) for u in units]
    pack_map = _build_pack_map(units)
    pack_word_to_unit = {
        wid: unit_id for unit_id, words in pack_map.items() for wid in words
    }

    conn = sqlite3.connect(str(db_path))
    conn.execute("PRAGMA busy_timeout = 20000")
    try:
        all_pack_words = set(pack_word_to_unit.keys())
        _validate_words_exist(conn, all_pack_words)

        current_map = _fetch_current_map(conn, unit_ids)
        current_word_to_unit = {
            wid: uid for uid, words in current_map.items() for wid in words
        }

        unit_diffs = []
        for uid in unit_ids:
            target = pack_map.get(uid, set())
            curr = current_map.get(uid, set())
            if target != curr:
                unit_diffs.append(
                    {
                        "unit_id": uid,
                        "missing_in_db": len(target - curr),
                        "extra_in_db": len(curr - target),
                        "overlap": len(target & curr),
                    }
                )

        moved_count = sum(
            1
            for wid, target_uid in pack_word_to_unit.items()
            if current_word_to_unit.get(wid) != target_uid
        )

        stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")
        moved_csv = report_dir / f"hsk1_unit_sync_moved_words_{stamp}.csv"
        moved_csv_rows = _write_moves_csv(moved_csv, current_word_to_unit, pack_word_to_unit)

        backup_path = None
        applied_rows = 0
        if args.apply:
            backup_path = _backup_db(db_path, backup_dir)
            with conn:
                placeholders = ",".join("?" for _ in unit_ids)
                conn.execute(
                    f"DELETE FROM unit_concepts WHERE unit_id IN ({placeholders})",
                    unit_ids,
                )

                rows_to_insert: list[tuple[str, str, int]] = []
                for u in units:
                    uid = str(u["unit_id"])
                    for seq, wid in enumerate(u.get("word_ids") or [], start=1):
                        rows_to_insert.append((uid, str(wid), seq))
                conn.executemany(
                    """
                    INSERT INTO unit_concepts (unit_id, concept_id, sequence)
                    VALUES (?, ?, ?)
                    """,
                    rows_to_insert,
                )
                applied_rows = len(rows_to_insert)

        summary = {
            "ok": True,
            "apply": bool(args.apply),
            "db": args.db,
            "pack": args.pack,
            "units_total": len(unit_ids),
            "unit_diffs_total": len(unit_diffs),
            "misplaced_words_total": moved_count,
            "moved_words_csv": str(moved_csv),
            "moved_words_rows": moved_csv_rows,
            "backup_db": str(backup_path) if backup_path else None,
            "applied_rows": applied_rows,
            "sample_unit_diffs": unit_diffs[:10],
        }

        summary_path = report_dir / f"hsk1_unit_sync_summary_{stamp}.json"
        summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
        summary["summary_json"] = str(summary_path)
        print(json.dumps(summary, ensure_ascii=False))
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
