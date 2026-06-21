#!/usr/bin/env python3
"""Import missing vocab rows (from stage_vocab_merge_audit *_new.csv) into concepts.

Typical workflow:
1) stage_vocab_merge_audit.py -> produces *_new.csv
2) import_missing_concepts_from_audit.py --new-csv ... --apply
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import re
import sqlite3
from pathlib import Path
from typing import Dict, List, Tuple


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _normalize_pinyin(value: str) -> str:
    return re.sub(r"\s+", " ", str(value or "").strip().lower())


def _normalize_text(value: str) -> str:
    return re.sub(r"\s+", "", str(value or "").strip())


def _load_rows(path: Path) -> List[Dict[str, str]]:
    out: List[Dict[str, str]] = []
    with path.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for raw in reader:
            out.append(
                {
                    "hanzi": str(raw.get("hanzi", "")).strip(),
                    "pinyin": str(raw.get("pinyin", "")).strip(),
                    "meaning_en": str(raw.get("meaning_en", "")).strip(),
                    "source_level": str(raw.get("source_level", "")).strip(),
                    "source_name": str(raw.get("source_name", "")).strip(),
                }
            )
    return out


def _next_numeric_id(conn: sqlite3.Connection) -> int:
    row = conn.execute(
        """
        SELECT MAX(CAST(SUBSTR(id, 2) AS INTEGER))
        FROM concepts
        WHERE id GLOB 'W[0-9]*'
        """
    ).fetchone()
    max_id = int(row[0] or 0)
    return max_id + 1


def _fmt_id(n: int) -> str:
    # 6 digits keeps ordering clear once past 99999.
    return f"W{n:06d}"


def main() -> int:
    parser = argparse.ArgumentParser(description="Import missing concepts from audit new.csv")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--new-csv", required=True, help="Path to *_new.csv from audit")
    parser.add_argument("--report-dir", default="docs/reports")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    repo_root = _repo_root()
    db_path = repo_root / args.db
    csv_path = (
        repo_root / args.new_csv if not Path(args.new_csv).is_absolute() else Path(args.new_csv)
    )
    report_dir = repo_root / args.report_dir
    report_dir.mkdir(parents=True, exist_ok=True)

    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1
    if not csv_path.exists():
        print(f"CSV not found: {csv_path}")
        return 1

    rows = _load_rows(csv_path)
    dedup_map: Dict[Tuple[str, str], Dict[str, str]] = {}
    skipped_empty = 0
    for row in rows:
        hanzi = _normalize_text(row["hanzi"])
        pinyin = _normalize_pinyin(row["pinyin"])
        if not hanzi:
            skipped_empty += 1
            continue
        dedup_map[(hanzi, pinyin)] = row
    dedup_rows = list(dedup_map.values())

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        to_insert: List[Tuple[str, str, str, str]] = []
        already_exists = 0
        for row in dedup_rows:
            hanzi = _normalize_text(row["hanzi"])
            pinyin = _normalize_pinyin(row["pinyin"])
            existing = conn.execute(
                """
                SELECT id
                FROM concepts
                WHERE text = ? AND LOWER(COALESCE(pinyin, '')) = ?
                LIMIT 1
                """,
                (hanzi, pinyin),
            ).fetchone()
            if existing:
                already_exists += 1
                continue

            meaning = row["meaning_en"].strip()
            to_insert.append((hanzi, row["pinyin"].strip(), meaning, row["source_level"].strip()))

        next_id = _next_numeric_id(conn)
        inserts_sql: List[Tuple[str, str, str, str]] = []
        sample_ids: List[str] = []
        for hanzi, pinyin, meaning, _src_level in to_insert:
            cid = _fmt_id(next_id)
            next_id += 1
            inserts_sql.append((cid, hanzi, pinyin, meaning))
            if len(sample_ids) < 20:
                sample_ids.append(cid)

        if args.apply and inserts_sql:
            conn.executemany(
                """
                INSERT OR IGNORE INTO concepts (id, text, pinyin, meaning, created_at)
                VALUES (?, ?, ?, ?, datetime('now'))
                """,
                inserts_sql,
            )
            conn.commit()

        summary = {
            "date": dt.date.today().isoformat(),
            "db": args.db,
            "new_csv": str(csv_path),
            "rows_input": len(rows),
            "rows_dedup": len(dedup_rows),
            "rows_skipped_empty": skipped_empty,
            "already_exists_exact_text_pinyin": already_exists,
            "rows_candidate_insert": len(inserts_sql),
            "applied": args.apply,
            "sample_new_ids": sample_ids,
        }
        report_path = report_dir / f"import_missing_concepts_{dt.date.today().isoformat()}.json"
        report_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")

        print("Missing-concepts import plan complete")
        print(f"Report: {report_path}")
        print(f"Candidates: {len(inserts_sql)}")
        print(f"Applied: {args.apply}")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
