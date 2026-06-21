#!/usr/bin/env python3
"""Generate a variant todo pack for a pilot slice (no DB writes)."""

from __future__ import annotations

import argparse
import json
import sqlite3
from datetime import date
from pathlib import Path
from typing import Dict, List


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _connect(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    return conn


def _read_ids(path: Path) -> List[str]:
    return [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate variant todo pack for pilot slice")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--only-ids", required=True)
    parser.add_argument("--out-dir", default="docs/reports")
    args = parser.parse_args()

    repo_root = _repo_root()
    db_path = repo_root / args.db
    ids_path = repo_root / args.only_ids
    out_dir = repo_root / args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1
    if not ids_path.exists():
        print(f"IDs file not found: {ids_path}")
        return 1

    ids = _read_ids(ids_path)

    conn = _connect(db_path)
    try:
        rows = conn.execute(
            """
            SELECT word_id, exercise_type, COUNT(*) as cnt
            FROM word_exercises
            WHERE word_id IN ({})
            GROUP BY word_id, exercise_type
            """.format(",".join("?" for _ in ids)),
            ids,
        ).fetchall()
    finally:
        conn.close()

    by_word: Dict[str, Dict[str, int]] = {cid: {} for cid in ids}
    for row in rows:
        cid = str(row[0])
        by_word.setdefault(cid, {})[row[1]] = int(row[2])

    under_target = []
    for cid in ids:
        total = sum(by_word.get(cid, {}).values())
        if total < 3:
            under_target.append(
                {
                    "concept_id": cid,
                    "current_variants": total,
                    "by_type": by_word.get(cid, {}),
                    "needed_variants": 3 - total,
                    "suggested_types": ["sentence_fill"],
                }
            )

    pack = {
        "date": date.today().isoformat(),
        "pilot_ids": str(ids_path),
        "target_min_variants": 3,
        "under_target_count": len(under_target),
        "items": under_target,
    }

    out_path = out_dir / f"variant_todo_{date.today().isoformat()}.json"
    out_path.write_text(json.dumps(pack, indent=2), encoding="utf-8")
    print(f"Wrote {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
