#!/usr/bin/env python3
"""Navigate HSK1 image prompts one-by-one with next/prev commands.

Examples:
  python3 tools/hsk1_prompt_navigator.py show
  python3 tools/hsk1_prompt_navigator.py next
  python3 tools/hsk1_prompt_navigator.py prev
  python3 tools/hsk1_prompt_navigator.py goto 120
  python3 tools/hsk1_prompt_navigator.py reset
"""

from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path

from hsk1_object_filter import is_memorization_object_row


def load_catalog(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def filter_by_category(rows: list[dict[str, str]], category: str | None) -> list[dict[str, str]]:
    if not category:
        return rows
    return [r for r in rows if (r.get("category") or "").strip() == category]


def filter_memorization_objects(
    rows: list[dict[str, str]],
    name_map: dict[str, str],
) -> list[dict[str, str]]:
    out: list[dict[str, str]] = []
    for r in rows:
        image_id = (r.get("image_id") or "").strip()
        filename = (name_map.get(image_id) or "").strip()
        if is_memorization_object_row(
            category=r.get("category", ""),
            name_en=r.get("name_en", ""),
            concept_key=r.get("concept_key", ""),
            recommended_filename=filename,
        ):
            out.append(r)
    return out


def load_name_map(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    with path.open("r", encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            image_id = (row.get("image_id") or "").strip()
            filename = (row.get("recommended_filename") or "").strip()
            if image_id and filename:
                out[image_id] = filename
    return out


def parse_dirs(value: str) -> list[Path]:
    return [Path(x.strip()) for x in value.split(",") if x.strip()]


def collect_existing_filenames(dirs: list[Path]) -> set[str]:
    out: set[str] = set()
    for d in dirs:
        if not d.exists():
            continue
        for p in d.rglob("*"):
            if p.is_file() and p.suffix.lower() in {".webp", ".png", ".jpg", ".jpeg"}:
                out.add(p.name)
    return out


def load_wordpub_to_wordid(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not path.exists():
        return out
    with path.open("r", encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            out[(row.get("word_public_id") or "").strip()] = (row.get("word_id") or "").strip()
    return out


def load_image_to_wordpub(path: Path) -> dict[str, set[str]]:
    out: dict[str, set[str]] = {}
    if not path.exists():
        return out
    with path.open("r", encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            image_id = (row.get("image_id") or "").strip()
            word_pub = (row.get("word_public_id") or "").strip()
            relevance = (row.get("relevance") or "").strip().lower()
            if relevance != "primary":
                continue
            if image_id and word_pub:
                out.setdefault(image_id, set()).add(word_pub)
    return out


def build_covered_image_ids(
    rows: list[dict[str, str]],
    name_map: dict[str, str],
    existing_files: set[str],
    legacy_match: str,
    wordpub_to_wordid: dict[str, str],
    image_to_wordpub: dict[str, set[str]],
) -> set[str]:
    covered: set[str] = set()
    row_ids = {(r.get("image_id") or "").strip() for r in rows if (r.get("image_id") or "").strip()}

    # Direct filename matches (current + recommended)
    for r in rows:
        image_id = (r.get("image_id") or "").strip()
        if not image_id:
            continue
        current_name = (r.get("filename") or "").strip()
        recommended_name = (name_map.get(image_id) or "").strip()
        if (current_name and current_name in existing_files) or (
            recommended_name and recommended_name in existing_files
        ):
            covered.add(image_id)

    if legacy_match == "none":
        return covered

    pat_w = re.compile(r"^word_(W\d+)\.webp$", re.IGNORECASE)
    pat_n = re.compile(r"^word_(\d+)\.webp$", re.IGNORECASE)
    existing_word_w = {m.group(1).upper() for n in existing_files for m in [pat_w.match(n)] if m}
    existing_word_num = {int(m.group(1)) for n in existing_files for m in [pat_n.match(n)] if m}

    for image_id, word_pubs in image_to_wordpub.items():
        if image_id not in row_ids:
            continue
        if image_id in covered:
            continue
        for word_pub in word_pubs:
            word_id = wordpub_to_wordid.get(word_pub, "")
            if not word_id:
                continue
            if word_id in existing_word_w:
                covered.add(image_id)
                break
            if legacy_match == "all" and word_id.startswith("W") and word_id[1:].isdigit():
                if int(word_id[1:]) in existing_word_num:
                    covered.add(image_id)
                    break

    return covered


def read_cursor(path: Path) -> int:
    if not path.exists():
        return 1
    raw = path.read_text(encoding="utf-8").strip()
    if not raw:
        return 1
    try:
        return int(raw)
    except ValueError:
        return 1


def write_cursor(path: Path, value: int) -> None:
    path.write_text(str(value), encoding="utf-8")


def clamp(value: int, lo: int, hi: int) -> int:
    return max(lo, min(hi, value))


def render_item(idx_1based: int, row: dict[str, str], filename: str, prompt_first: bool) -> str:
    prompt = row.get("prompt_en", "")
    image_id = row.get("image_id", "")
    name_en = row.get("name_en", "")
    category = row.get("category", "")
    concept_key = row.get("concept_key", "")

    if prompt_first:
        head = f"prompt: {prompt}\nname: {filename}\n"
    else:
        head = f"name: {filename}\nprompt: {prompt}\n"

    return (
        f"[{idx_1based:04d}]\n"
        f"{head}"
        f"image_id: {image_id}\n"
        f"name_en: {name_en}\n"
        f"category: {category}\n"
        f"concept_key: {concept_key}\n"
    )


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
        "--category",
        default="object_scene",
        help="Category filter (default: object_scene)",
    )
    parser.add_argument(
        "--all-categories",
        action="store_true",
        help="Disable category filter and show all categories",
    )
    parser.add_argument(
        "--all-object-rows",
        action="store_true",
        help="When category=object_scene, disable concrete memorization filter",
    )
    parser.add_argument(
        "--include-unlinked",
        action="store_true",
        help="Include rows with no primary word links",
    )
    parser.add_argument(
        "--cursor-file",
        default=".hsk1_prompt_cursor",
        help="File storing current 1-based cursor index",
    )
    parser.add_argument(
        "--missing-only",
        action="store_true",
        default=True,
        help="Show only images that are not already present in image directories (default: on)",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Show full catalog (disable missing-only filter)",
    )
    parser.add_argument(
        "--existing-dirs",
        default="images omnis/vocab_images/assets_images,assets/images,backend/static/images",
        help="Comma-separated directories to scan for existing image files",
    )
    parser.add_argument(
        "--legacy-match",
        choices=["none", "w", "all"],
        default="w",
        help="How to treat legacy files: none, word_Wxxxxx only, or word_Wxxxxx + word_N",
    )
    parser.add_argument(
        "--word-map",
        default="docs/reports/hsk1_public_word_id_map_2026-02-15.csv",
        help="Word public-id mapping CSV (used for legacy matching)",
    )
    parser.add_argument(
        "--links",
        default="docs/reports/hsk1_sense_image_links_v1_2026-02-15.csv",
        help="Sense-image links CSV (used for legacy matching)",
    )
    parser.add_argument(
        "--prompt-first",
        action="store_true",
        help="Print prompt before filename",
    )

    sub = parser.add_subparsers(dest="cmd", required=True)
    p_show = sub.add_parser("show")
    p_show.add_argument("--prompt-first", action="store_true")
    p_next = sub.add_parser("next")
    p_next.add_argument("--step", type=int, default=1)
    p_next.add_argument("--prompt-first", action="store_true")
    p_prev = sub.add_parser("prev")
    p_prev.add_argument("--step", type=int, default=1)
    p_prev.add_argument("--prompt-first", action="store_true")
    p_goto = sub.add_parser("goto")
    p_goto.add_argument("index", type=int)
    p_goto.add_argument("--prompt-first", action="store_true")
    p_reset = sub.add_parser("reset")
    p_reset.add_argument("--prompt-first", action="store_true")
    sub.add_parser("count")

    args = parser.parse_args()

    catalog_path = Path(args.catalog)
    naming_path = Path(args.naming)
    cursor_path = Path(args.cursor_file)

    if not catalog_path.exists():
        raise SystemExit(f"Catalog not found: {catalog_path}")
    if not naming_path.exists():
        raise SystemExit(f"Naming file not found: {naming_path}")

    all_rows = sorted(load_catalog(catalog_path), key=lambda r: (r.get("image_id") or ""))
    if not all_rows:
        raise SystemExit("No rows in catalog.")
    source_total = len(all_rows)
    name_map = load_name_map(naming_path)
    category_filter = None if args.all_categories else (args.category or "").strip()
    rows = filter_by_category(all_rows, category_filter)
    using_object_mem_filter = bool(category_filter == "object_scene" and not args.all_object_rows)
    if using_object_mem_filter:
        rows = filter_memorization_objects(rows, name_map)
    image_to_wordpub = load_image_to_wordpub(Path(args.links))
    if (not args.include_unlinked) and category_filter == "object_scene":
        rows = [r for r in rows if image_to_wordpub.get((r.get("image_id") or "").strip())]
    if not rows:
        raise SystemExit("No rows in catalog for selected category filter.")
    category_total = len(rows)

    use_missing_only = bool(args.missing_only) and (not bool(args.all))

    covered_count = 0
    if use_missing_only:
        existing_files = collect_existing_filenames(parse_dirs(args.existing_dirs))
        covered_ids = build_covered_image_ids(
            rows=rows,
            name_map=name_map,
            existing_files=existing_files,
            legacy_match=args.legacy_match,
            wordpub_to_wordid=load_wordpub_to_wordid(Path(args.word_map)),
            image_to_wordpub=image_to_wordpub,
        )
        covered_count = len(covered_ids)
        rows = [r for r in rows if (r.get("image_id") or "") not in covered_ids]

    total = len(rows)
    category_label = (
        f"{category_filter}+memorization" if using_object_mem_filter else (category_filter or "ALL")
    )

    if total == 0:
        print(
            f"TOTAL_MISSING: 0 | COVERED: {covered_count} | "
            f"CATEGORY_TOTAL: {category_total} | SOURCE_TOTAL: {source_total} | "
            f"CATEGORY: {category_label}"
        )
        return 0

    cur = clamp(read_cursor(cursor_path), 1, total)

    if args.cmd == "count":
        if use_missing_only:
            print(
                f"TOTAL_MISSING: {total} | COVERED: {covered_count} | "
                f"CATEGORY_TOTAL: {category_total} | SOURCE_TOTAL: {source_total} | "
                f"CATEGORY: {category_label}"
            )
        else:
            print(
                f"TOTAL: {total} | CATEGORY_TOTAL: {category_total} | "
                f"SOURCE_TOTAL: {source_total} | CATEGORY: {category_label}"
            )
        return 0
    if args.cmd == "reset":
        cur = 1
    elif args.cmd == "next":
        cur = clamp(cur + max(1, args.step), 1, total)
    elif args.cmd == "prev":
        cur = clamp(cur - max(1, args.step), 1, total)
    elif args.cmd == "goto":
        cur = clamp(args.index, 1, total)
    elif args.cmd == "show":
        pass

    write_cursor(cursor_path, cur)
    row = rows[cur - 1]
    filename = name_map.get(row.get("image_id", ""), row.get("filename", ""))
    if use_missing_only:
        print(
            f"TOTAL_MISSING: {total} | COVERED: {covered_count} | "
            f"CATEGORY_TOTAL: {category_total} | SOURCE_TOTAL: {source_total} | "
            f"CATEGORY: {category_label} | CURRENT: {cur}"
        )
    else:
        print(
            f"TOTAL: {total} | CATEGORY_TOTAL: {category_total} | SOURCE_TOTAL: {source_total} | "
            f"CATEGORY: {category_label} | CURRENT: {cur}"
        )
    prompt_first = bool(getattr(args, "prompt_first", False))
    print(render_item(cur, row, filename, prompt_first))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
