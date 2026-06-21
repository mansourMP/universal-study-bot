#!/usr/bin/env python3
"""Convert ivankra hsk30-expanded.csv into per-level pack JSON files.

Outputs (default):
- backend/content/packs/hsk30_expanded/zh_hsk1_vocab.json
- ...
- backend/content/packs/hsk30_expanded/zh_hsk7_vocab.json   # contains source Level=7-9
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Tuple


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _norm(value: str | None) -> str:
    return str(value or "").strip()


def _pick(row: Dict[str, str], *keys: str) -> str:
    lower_map = {str(k).lower(): v for k, v in row.items()}
    for key in keys:
        if key in row:
            return _norm(row.get(key))
        value = lower_map.get(key.lower())
        if value is not None:
            return _norm(str(value))
    return ""


def _pack_level(source_level: str) -> int | None:
    v = _norm(source_level)
    if not v:
        return None
    if v == "7-9":
        return 7
    if v.isdigit():
        n = int(v)
        if 1 <= n <= 6:
            return n
    return None


def _row_key(hanzi: str, pinyin: str) -> Tuple[str, str]:
    return hanzi, pinyin.lower().replace("  ", " ").strip()


def main() -> int:
    parser = argparse.ArgumentParser(description="Build per-level packs from hsk30-expanded.csv")
    parser.add_argument(
        "--source",
        default="hsk30-expanded.csv",
        help="CSV path (workspace-relative or absolute)",
    )
    parser.add_argument(
        "--out-dir",
        default="backend/content/packs/hsk30_expanded",
        help="Output directory for zh_hsk{N}_vocab.json packs",
    )
    parser.add_argument(
        "--report-dir",
        default="docs/reports",
        help="Directory for build summary report",
    )
    args = parser.parse_args()

    repo_root = _repo_root()
    source_path = (
        repo_root / args.source if not Path(args.source).is_absolute() else Path(args.source)
    )
    out_dir = repo_root / args.out_dir
    report_dir = repo_root / args.report_dir

    if not source_path.exists():
        print(f"Source not found: {source_path}")
        return 1

    out_dir.mkdir(parents=True, exist_ok=True)
    report_dir.mkdir(parents=True, exist_ok=True)

    grouped: Dict[int, List[Dict]] = defaultdict(list)
    dedup: Dict[int, set] = defaultdict(set)
    skipped_bad_level = 0
    skipped_empty = 0
    total_rows = 0
    duplicate_rows = 0

    with source_path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        for raw in reader:
            total_rows += 1
            hanzi = _pick(raw, "Simplified", "hanzi", "word", "text")
            pinyin = _pick(raw, "Pinyin", "pinyin", "pronunciation")
            src_level = _pick(raw, "Level", "source_level", "level")
            if not hanzi or not pinyin:
                skipped_empty += 1
                continue
            level = _pack_level(src_level)
            if level is None:
                skipped_bad_level += 1
                continue

            key = _row_key(hanzi, pinyin)
            if key in dedup[level]:
                duplicate_rows += 1
                continue
            dedup[level].add(key)

            grouped[level].append(
                {
                    "hanzi": hanzi,
                    "pinyin": pinyin,
                    "meaning_en": "",
                    "source_level": src_level,
                    "pos": _pick(raw, "POS", "pos") or None,
                    "traditional": _pick(raw, "Traditional", "traditional") or None,
                    "source_id": _pick(raw, "ID", "source_id") or None,
                    "source_name": "ivankra_hsk30_expanded",
                }
            )

    summary_levels: List[Dict] = []
    for level in sorted(grouped.keys()):
        rows = sorted(grouped[level], key=lambda r: (r["hanzi"], r["pinyin"]))
        pack = {
            "id": f"zh_hsk{level}_vocab",
            "language": "zh",
            "level": level,
            "kind": "vocab",
            "version": 1,
            "standard": "HSK3.0",
            "source": "ivankra/hsk30 (expanded.csv)",
            "vocabulary": rows,
        }
        out_path = out_dir / f"zh_hsk{level}_vocab.json"
        out_path.write_text(json.dumps(pack, ensure_ascii=False, indent=2), encoding="utf-8")
        summary_levels.append(
            {
                "pack_level": level,
                "rows_written": len(rows),
                "output": str(out_path),
            }
        )

    stamp = dt.date.today().isoformat()
    report = {
        "date": stamp,
        "source": str(source_path),
        "rows_total_input": total_rows,
        "rows_skipped_empty": skipped_empty,
        "rows_skipped_bad_level": skipped_bad_level,
        "rows_skipped_duplicates": duplicate_rows,
        "levels": summary_levels,
    }
    report_path = report_dir / f"hsk30_expanded_pack_build_{stamp}.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    print("HSK30 expanded pack build complete")
    print(f"Report: {report_path}")
    for item in summary_levels:
        print(f"HSK{item['pack_level']}: {item['rows_written']} -> {item['output']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
