#!/usr/bin/env python3
"""Build draft expansion units from promotion batch + scaffold.

This does not write into DB or manifest. It generates a draft JSON file for review.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _read_csv(path: Path) -> list[dict]:
    with path.open("r", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def main() -> int:
    parser = argparse.ArgumentParser(description="Build expansion unit draft")
    parser.add_argument("--promotion-csv", default="docs/reports/path_promotion_batch_2026-02-09.csv")
    parser.add_argument("--scaffold-csv", default="docs/reports/zh_unit_scaffold_2026-02-09.csv")
    parser.add_argument("--start-unit", type=int, default=49)
    parser.add_argument("--unit-count", type=int, default=20)
    parser.add_argument("--words-per-unit", type=int, default=15)
    parser.add_argument("--out", default="")
    args = parser.parse_args()

    repo_root = _repo_root()
    promotion_path = repo_root / args.promotion_csv
    scaffold_path = repo_root / args.scaffold_csv

    if not promotion_path.exists():
        print(f"Promotion CSV not found: {promotion_path}")
        return 1
    if not scaffold_path.exists():
        print(f"Scaffold CSV not found: {scaffold_path}")
        return 1

    promotion_rows = _read_csv(promotion_path)
    scaffold_rows = _read_csv(scaffold_path)
    scaffold_map = {
        int(r["unit_number"]): r
        for r in scaffold_rows
        if r.get("unit_number")
    }

    required_words = args.unit_count * args.words_per_unit
    if len(promotion_rows) < required_words:
        print(
            f"Not enough promotion words: have {len(promotion_rows)}, need {required_words}"
        )
        return 1

    selected = promotion_rows[:required_words]
    units = []
    for idx in range(args.unit_count):
        u_num = args.start_unit + idx
        chunk = selected[idx * args.words_per_unit : (idx + 1) * args.words_per_unit]
        meta = scaffold_map.get(u_num, {})
        units.append(
            {
                "unit_number": u_num,
                "section_id": meta.get("section_id", ""),
                "section_title": meta.get("section_title", ""),
                "cefr_band": meta.get("cefr_band", ""),
                "hsk_band": meta.get("hsk_band", ""),
                "title": meta.get("unit_title", f"Unit {u_num} Draft"),
                "theme": meta.get("theme", ""),
                "words_target": args.words_per_unit,
                "word_ids": [r["concept_id"] for r in chunk],
                "source": "promotion_batch",
            }
        )

    payload = {
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "start_unit": args.start_unit,
        "unit_count": args.unit_count,
        "words_per_unit": args.words_per_unit,
        "promotion_source": str(args.promotion_csv),
        "scaffold_source": str(args.scaffold_csv),
        "units": units,
    }

    out_path = (
        Path(args.out)
        if args.out
        else repo_root / "docs" / "reports" / f"expansion_units_draft_{dt.date.today().isoformat()}.json"
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"Wrote {out_path}")
    print(f"Units: {len(units)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
