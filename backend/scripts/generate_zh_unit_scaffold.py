#!/usr/bin/env python3
"""Generate a unit-by-unit scaffold CSV from curriculum blueprint."""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _rotation(items: list[str], idx: int) -> str:
    if not items:
        return "Theme Placeholder"
    return items[idx % len(items)]


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate ZH unit scaffold")
    parser.add_argument("--blueprint", default="docs/specs/zh_curriculum_blueprint_v1.json")
    parser.add_argument("--out", default="")
    args = parser.parse_args()

    repo_root = _repo_root()
    blueprint_path = repo_root / args.blueprint
    if not blueprint_path.exists():
        print(f"Blueprint not found: {blueprint_path}")
        return 1

    data = json.loads(blueprint_path.read_text(encoding="utf-8"))
    sections = data.get("sections", [])
    totals = data.get("totals", {})
    circles = totals.get("circles_per_unit", 7)
    wmin = totals.get("new_words_per_unit_min", 12)
    wmax = totals.get("new_words_per_unit_max", 18)

    out_path = (
        Path(args.out)
        if args.out
        else repo_root / "docs" / "reports" / f"zh_unit_scaffold_{dt.date.today().isoformat()}.csv"
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)

    unit_no = 1
    rows = []
    for section_idx, section in enumerate(sections):
        sid = section.get("id", f"S{section_idx+1:02d}")
        title = section.get("title", f"Section {section_idx+1}")
        cefr = section.get("cefr_band", "")
        hsk = section.get("hsk_band", "")
        count = int(section.get("unit_count", 0))
        themes = section.get("theme_bank", [])

        for i in range(count):
            theme = _rotation(themes, i)
            cycle = i // max(1, len(themes)) + 1
            unit_title = f"{theme} - Cycle {cycle}"
            rows.append(
                {
                    "unit_number": unit_no,
                    "section_id": sid,
                    "section_title": title,
                    "cefr_band": cefr,
                    "hsk_band": hsk,
                    "theme": theme,
                    "unit_title": unit_title,
                    "new_words_min": wmin,
                    "new_words_max": wmax,
                    "circles_per_unit": circles,
                    "status": "planned",
                    "notes": "",
                }
            )
            unit_no += 1

    with out_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "unit_number",
                "section_id",
                "section_title",
                "cefr_band",
                "hsk_band",
                "theme",
                "unit_title",
                "new_words_min",
                "new_words_max",
                "circles_per_unit",
                "status",
                "notes",
            ],
        )
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {out_path}")
    print(f"Units: {len(rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
