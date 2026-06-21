#!/usr/bin/env python3
"""Render a readable name/prompt sheet from HSK1 image CSV files.

Usage examples:
  python3 tools/render_hsk1_image_prompt_sheet.py
  python3 tools/render_hsk1_image_prompt_sheet.py --print --limit 20
  python3 tools/render_hsk1_image_prompt_sheet.py --start 101 --limit 50
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


def load_catalog(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def load_name_map(path: Path) -> dict[str, str]:
    mapping: dict[str, str] = {}
    with path.open("r", encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            image_id = (row.get("image_id") or "").strip()
            filename = (row.get("recommended_filename") or "").strip()
            if image_id and filename:
                mapping[image_id] = filename
    return mapping


def build_blocks(
    catalog_rows: list[dict[str, str]],
    name_map: dict[str, str],
    start: int,
    limit: int | None,
    prompt_first: bool,
) -> list[str]:
    # Stable order by image_id to keep output deterministic.
    rows = sorted(catalog_rows, key=lambda r: (r.get("image_id") or ""))
    start_idx = max(1, start)
    end_idx = len(rows) if limit is None else min(len(rows), start_idx - 1 + max(limit, 0))

    blocks: list[str] = []
    for i in range(start_idx - 1, end_idx):
        row = rows[i]
        image_id = row.get("image_id", "")
        filename = name_map.get(image_id) or row.get("filename", "")
        name_en = row.get("name_en", "")
        category = row.get("category", "")
        prompt_en = row.get("prompt_en", "")
        concept_key = row.get("concept_key", "")

        if prompt_first:
            header_lines = (
                f"prompt: {prompt_en}\n"
                f"name: {filename}\n"
            )
        else:
            header_lines = (
                f"name: {filename}\n"
                f"prompt: {prompt_en}\n"
            )

        block = (
            f"[{i + 1:04d}]\n"
            f"{header_lines}"
            f"image_id: {image_id}\n"
            f"name_en: {name_en}\n"
            f"category: {category}\n"
            f"concept_key: {concept_key}\n"
        )
        blocks.append(block)
    return blocks


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--catalog",
        default="hsk1_universal_images_catalog_v2_2026-02-15.csv",
        help="Catalog CSV path",
    )
    parser.add_argument(
        "--naming",
        default="hsk1_universal_images_semantic_naming_v1_2026-02-15.csv",
        help="Semantic naming CSV path",
    )
    parser.add_argument(
        "--out",
        default="hsk1_image_prompt_name_sheet_v1_2026-02-15.txt",
        help="Output text file path",
    )
    parser.add_argument("--start", type=int, default=1, help="1-based start index")
    parser.add_argument("--limit", type=int, default=None, help="Max rows to include")
    parser.add_argument(
        "--prompt-first",
        action="store_true",
        help="Render prompt line before name line",
    )
    parser.add_argument("--print", action="store_true", dest="print_stdout", help="Also print to terminal")
    args = parser.parse_args()

    catalog_path = Path(args.catalog)
    naming_path = Path(args.naming)
    out_path = Path(args.out)

    if not catalog_path.exists():
        raise SystemExit(f"Catalog not found: {catalog_path}")
    if not naming_path.exists():
        raise SystemExit(f"Naming file not found: {naming_path}")

    catalog_rows = load_catalog(catalog_path)
    name_map = load_name_map(naming_path)
    blocks = build_blocks(catalog_rows, name_map, args.start, args.limit, args.prompt_first)

    header = (
        "HSK1 IMAGE PROMPT + NAME SHEET\n"
        f"catalog: {catalog_path}\n"
        f"naming: {naming_path}\n"
        f"rows_in_catalog: {len(catalog_rows)}\n"
        f"rows_rendered: {len(blocks)}\n"
        "============================================================\n\n"
    )
    text = header + "\n".join(blocks)
    out_path.write_text(text, encoding="utf-8")

    print(f"wrote: {out_path.resolve()}")
    print(f"rows_rendered: {len(blocks)}")
    if args.print_stdout:
        print("\n" + text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
