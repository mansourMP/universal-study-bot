#!/usr/bin/env python3
"""Stage external vocabulary and audit merge status against current DB.

This script keeps a single canonical vocab graph (`concepts` + `concept_senses`)
while allowing new sources (HSK2.0/HSK3.0/other) to be merged safely.

Output reports:
- *_summary.json
- *_matched.csv
- *_new.csv
- *_ambiguous.csv
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import re
import sqlite3
from pathlib import Path
from typing import Dict, Iterable, List, Sequence


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _normalize_text(value: str | None) -> str:
    if not value:
        return ""
    return re.sub(r"\s+", "", str(value)).strip()


def _normalize_pinyin(value: str | None) -> str:
    if not value:
        return ""
    return re.sub(r"\s+", " ", str(value)).strip().lower()


def _pick(raw: Dict, *keys: str) -> str:
    """Case-insensitive field lookup for heterogeneous CSV/JSON sources."""
    if not isinstance(raw, dict):
        return ""
    lower_map = {str(k).lower(): v for k, v in raw.items()}
    for key in keys:
        if key in raw:
            return str(raw.get(key, ""))
        value = lower_map.get(key.lower())
        if value is not None:
            return str(value)
    return ""


def _row_from_dict(raw: Dict, source_name: str) -> Dict[str, str]:
    """Normalize source row fields into common shape."""
    hanzi = _pick(raw, "hanzi", "word", "text", "simplified", "traditional")
    pinyin = _pick(raw, "pinyin", "pronunciation", "reading", "webpinyin")
    meaning = _pick(raw, "meaning_en", "translation_en", "en", "meaning", "gloss")
    level = _pick(raw, "source_level", "hsk_level", "level")

    return {
        "hanzi": str(hanzi).strip(),
        "pinyin": str(pinyin).strip(),
        "meaning_en": str(meaning).strip(),
        "source_level": str(level).strip(),
        "source_name": source_name,
    }


def _load_json_rows(path: Path, source_name: str) -> List[Dict[str, str]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(data, dict):
        if isinstance(data.get("vocabulary"), list):
            rows = data["vocabulary"]
        elif isinstance(data.get("words"), list):
            rows = data["words"]
        else:
            rows = []
    elif isinstance(data, list):
        rows = data
    else:
        rows = []

    out = []
    for raw in rows:
        if isinstance(raw, dict):
            out.append(_row_from_dict(raw, source_name))
    return out


def _load_csv_rows(path: Path, source_name: str) -> List[Dict[str, str]]:
    out: List[Dict[str, str]] = []
    with path.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for raw in reader:
            out.append(_row_from_dict(raw, source_name))
    return out


def _load_source_rows(path: Path, source_name: str) -> List[Dict[str, str]]:
    ext = path.suffix.lower()
    if ext == ".json":
        return _load_json_rows(path, source_name)
    if ext == ".csv":
        return _load_csv_rows(path, source_name)
    raise ValueError(f"Unsupported source format: {ext}. Use .json or .csv")


def _query_concepts(conn: sqlite3.Connection, hanzi: str) -> List[sqlite3.Row]:
    return conn.execute(
        """
        SELECT c.id, c.text, c.pinyin, c.meaning
        FROM concepts c
        WHERE c.text = ?
        ORDER BY c.id
        """,
        (hanzi,),
    ).fetchall()


def _query_curriculum_rows(conn: sqlite3.Connection, concept_id: str) -> List[sqlite3.Row]:
    try:
        return conn.execute(
            """
            SELECT standard, level, band
            FROM concept_curriculum_map
            WHERE concept_id = ?
            ORDER BY standard, level, band
            """,
            (concept_id,),
        ).fetchall()
    except sqlite3.OperationalError:
        return []


def _write_csv(path: Path, fieldnames: Sequence[str], rows: Iterable[Dict[str, str]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit external vocab merge against DB concepts")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--source", required=True, help="Path to external vocab (.json or .csv)")
    parser.add_argument("--source-name", default="", help="Source label for reports")
    parser.add_argument("--report-dir", default="docs/reports")
    parser.add_argument("--sample-limit", type=int, default=20)
    args = parser.parse_args()

    repo_root = _repo_root()
    db_path = repo_root / args.db
    source_path = repo_root / args.source if not Path(args.source).is_absolute() else Path(args.source)
    report_dir = repo_root / args.report_dir
    report_dir.mkdir(parents=True, exist_ok=True)

    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1
    if not source_path.exists():
        print(f"Source not found: {source_path}")
        return 1

    source_name = args.source_name.strip() or source_path.stem
    stamp = dt.date.today().isoformat()
    prefix = f"vocab_merge_audit_{source_name}_{stamp}"

    rows = _load_source_rows(source_path, source_name)
    # Remove empty-hanzi and exact duplicates in source itself.
    dedup: List[Dict[str, str]] = []
    seen_keys = set()
    for row in rows:
        hanzi = _normalize_text(row["hanzi"])
        if not hanzi:
            continue
        key = (hanzi, _normalize_pinyin(row["pinyin"]), row["meaning_en"].strip().lower())
        if key in seen_keys:
            continue
        seen_keys.add(key)
        dedup.append(row)
    rows = dedup

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        matched: List[Dict[str, str]] = []
        new_rows: List[Dict[str, str]] = []
        ambiguous: List[Dict[str, str]] = []

        for row in rows:
            hanzi = _normalize_text(row["hanzi"])
            pinyin = _normalize_pinyin(row["pinyin"])
            candidates = _query_concepts(conn, hanzi)

            if not candidates:
                new_rows.append(
                    {
                        **row,
                        "reason": "missing_in_concepts",
                    }
                )
                continue

            if len(candidates) == 1:
                concept = candidates[0]
                tag_rows = _query_curriculum_rows(conn, str(concept["id"]))
                matched.append(
                    {
                        **row,
                        "concept_id": str(concept["id"]),
                        "concept_pinyin": concept["pinyin"] or "",
                        "concept_meaning": concept["meaning"] or "",
                        "status": "exact_text_match",
                        "curriculum_tags": "|".join(
                            f"{r['standard']}:{r['level']}:{r['band']}" for r in tag_rows
                        ),
                    }
                )
                continue

            by_pinyin = [
                c for c in candidates if _normalize_pinyin(c["pinyin"]) == pinyin and pinyin
            ]
            if len(by_pinyin) == 1:
                concept = by_pinyin[0]
                tag_rows = _query_curriculum_rows(conn, str(concept["id"]))
                matched.append(
                    {
                        **row,
                        "concept_id": str(concept["id"]),
                        "concept_pinyin": concept["pinyin"] or "",
                        "concept_meaning": concept["meaning"] or "",
                        "status": "disambiguated_by_pinyin",
                        "curriculum_tags": "|".join(
                            f"{r['standard']}:{r['level']}:{r['band']}" for r in tag_rows
                        ),
                    }
                )
            else:
                ambiguous.append(
                    {
                        **row,
                        "candidate_concept_ids": "|".join(str(c["id"]) for c in candidates),
                        "candidate_pinyins": "|".join((c["pinyin"] or "") for c in candidates),
                        "reason": "multiple_text_matches",
                    }
                )

        summary = {
            "date": stamp,
            "db": args.db,
            "source": str(source_path),
            "source_name": source_name,
            "rows_total_after_dedup": len(rows),
            "matched": len(matched),
            "new": len(new_rows),
            "ambiguous": len(ambiguous),
            "samples": {
                "new": new_rows[: args.sample_limit],
                "ambiguous": ambiguous[: args.sample_limit],
            },
        }

        summary_path = report_dir / f"{prefix}_summary.json"
        matched_path = report_dir / f"{prefix}_matched.csv"
        new_path = report_dir / f"{prefix}_new.csv"
        ambiguous_path = report_dir / f"{prefix}_ambiguous.csv"

        summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
        _write_csv(
            matched_path,
            [
                "hanzi",
                "pinyin",
                "meaning_en",
                "source_level",
                "source_name",
                "concept_id",
                "concept_pinyin",
                "concept_meaning",
                "status",
                "curriculum_tags",
            ],
            matched,
        )
        _write_csv(
            new_path,
            ["hanzi", "pinyin", "meaning_en", "source_level", "source_name", "reason"],
            new_rows,
        )
        _write_csv(
            ambiguous_path,
            [
                "hanzi",
                "pinyin",
                "meaning_en",
                "source_level",
                "source_name",
                "candidate_concept_ids",
                "candidate_pinyins",
                "reason",
            ],
            ambiguous,
        )

        print("Vocab merge audit complete")
        print(f"Summary: {summary_path}")
        print(f"Matched: {matched_path} ({len(matched)})")
        print(f"New: {new_path} ({len(new_rows)})")
        print(f"Ambiguous: {ambiguous_path} ({len(ambiguous)})")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
