#!/usr/bin/env python3
"""Simple button-style navigator for HSK image generation queues.

Numeric controls:
  1 = Prev
  2 = Next
  3 = Save current (ingest 1)
  4 = Next Missing
  5 = Goto index
  6 = Toggle filter (ALL/MISSING)
  7 = Rename first dropped file to target name + save current
  8 = Manual done toggle (no file copy)
  9 = Search / next match / clear search
  0 = Quit
"""

from __future__ import annotations

import argparse
import csv
import os
import subprocess
import sys
from pathlib import Path

from hsk1_object_filter import is_memorization_object_row


DEFAULT_CATALOG = "hsk1_universal_images_catalog_v2_2026-02-15.csv"
DEFAULT_NAMING = "hsk1_universal_images_semantic_naming_v1_2026-02-15.csv"
DEFAULT_LINKS = "docs/reports/hsk1_sense_image_links_v1_2026-02-15.csv"
DEFAULT_WORD_MAP = "docs/reports/hsk1_public_word_id_map_2026-02-15.csv"
DEFAULT_CURSOR = ".hsk1_prompt_cursor"
DEFAULT_MANUAL_DONE = ".hsk1_manual_done_image_ids.txt"

SEMANTIC_DIR = Path("images omnis/vocab_images/assets_images")
SOURCE_DIR = Path("images omnis/vocab_images/chat gpt generation")
ASSETS_DIR = Path("assets/images")
STATIC_DIR = Path("backend/static/images")
MIN_IMAGE_BYTES = 128


USE_COLOR = sys.stdout.isatty() and os.environ.get("TERM", "dumb") != "dumb"
RESET = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"
RED = "\033[91m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
BLUE = "\033[94m"
MAGENTA = "\033[95m"
CYAN = "\033[96m"
WHITE = "\033[97m"


def color(text: str, style: str) -> str:
    if not USE_COLOR:
        return text
    return f"{style}{text}{RESET}"


def load_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def _is_usable_image(path: Path) -> bool:
    try:
        return (path.exists() or path.is_symlink()) and path.stat().st_size > MIN_IMAGE_BYTES
    except OSError:
        return False


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--catalog", default=DEFAULT_CATALOG, help="Catalog CSV path")
    p.add_argument("--naming", default=DEFAULT_NAMING, help="Naming CSV path")
    p.add_argument("--links", default=DEFAULT_LINKS, help="Sense-image links CSV path")
    p.add_argument("--word-map", default=DEFAULT_WORD_MAP, help="Word map CSV path")
    p.add_argument("--cursor-file", default=DEFAULT_CURSOR, help="Cursor file path")
    p.add_argument(
        "--manual-done-file",
        default=DEFAULT_MANUAL_DONE,
        help="Manual done list file path",
    )
    p.add_argument(
        "--title",
        default="HSK IMAGE BUTTONS",
        help="Header title shown in UI",
    )
    p.add_argument(
        "--category",
        default="object_scene",
        help="Category filter (default: object_scene)",
    )
    p.add_argument(
        "--all-categories",
        action="store_true",
        help="Disable category filter and show all categories",
    )
    p.add_argument(
        "--all-object-rows",
        action="store_true",
        help="When category=object_scene, disable concrete memorization filter",
    )
    p.add_argument(
        "--include-unlinked",
        action="store_true",
        help="Include rows with no primary word links",
    )
    p.add_argument(
        "--levels",
        default="",
        help="Optional comma-separated HSK levels to include (e.g. HSK1,HSK2,HSK7)",
    )
    p.add_argument(
        "--all",
        action="store_true",
        help="Start in ALL mode (do not pre-filter to missing only)",
    )
    p.add_argument(
        "--done-policy",
        choices=["semantic", "runtime", "any"],
        default="runtime",
        help=(
            "What counts as auto-done: semantic file only, runtime word image only, "
            "or either (default: runtime)"
        ),
    )
    p.add_argument(
        "--search",
        default="",
        help="Initial search query (English/Chinese/word ID/filename/image_id).",
    )
    return p.parse_args()


def read_cursor(path: Path) -> int:
    if not path.exists():
        return 1
    raw = path.read_text(encoding="utf-8").strip()
    if not raw:
        return 1
    try:
        return max(1, int(raw))
    except ValueError:
        return 1


def write_cursor(path: Path, i: int) -> None:
    path.write_text(str(max(1, i)), encoding="utf-8")


def load_manual_done(path: Path) -> set[str]:
    if not path.exists():
        return set()
    return {
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    }


def save_manual_done(path: Path, done: set[str]) -> None:
    lines = sorted(done)
    path.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")


def build_rows(catalog_path: Path, naming_path: Path) -> list[dict[str, str]]:
    catalog_rows = {
        (r.get("image_id") or "").strip(): r
        for r in load_csv(catalog_path)
        if (r.get("image_id") or "").strip()
    }
    naming_rows = {
        (r.get("image_id") or "").strip(): r
        for r in load_csv(naming_path)
        if (r.get("image_id") or "").strip()
    }
    image_ids = sorted(set(catalog_rows) | set(naming_rows))
    out: list[dict[str, str]] = []
    for image_id in image_ids:
        c = catalog_rows.get(image_id, {})
        n = naming_rows.get(image_id, {})
        out.append(
            {
                "image_id": image_id,
                "name_en": (c.get("name_en") or n.get("name_en") or "").strip(),
                "category": (c.get("category") or n.get("category") or "").strip(),
                "concept_key": (c.get("concept_key") or n.get("concept_key") or "").strip(),
                "image_size": (c.get("image_size") or "").strip(),
                "prompt_en": (c.get("prompt_en") or "").strip(),
                "recommended_filename": (n.get("recommended_filename") or "").strip(),
                "semantic_category": (n.get("semantic_category") or "").strip(),
                "semantic_subcategory": (n.get("semantic_subcategory") or "").strip(),
                "semantic_concept": (n.get("semantic_concept") or "").strip(),
                "semantic_variant": (n.get("semantic_variant") or "").strip(),
                "hsk_level": (
                    c.get("hsk_level")
                    or n.get("hsk_level")
                    or c.get("level")
                    or ""
                ).strip().upper(),
            }
        )
    return out


def build_word_maps(
    links_path: Path,
    word_map_path: Path,
) -> tuple[dict[str, list[str]], dict[str, list[str]]]:
    image_to_wordpub: dict[str, set[str]] = {}
    for r in load_csv(links_path):
        image_id = (r.get("image_id") or "").strip()
        word_pub = (r.get("word_public_id") or "").strip()
        relevance = (r.get("relevance") or "").strip().lower()
        if relevance != "primary":
            continue
        if image_id and word_pub:
            image_to_wordpub.setdefault(image_id, set()).add(word_pub)

    wordpub_info: dict[str, tuple[str, str, str]] = {}
    for r in load_csv(word_map_path):
        word_pub = (r.get("word_public_id") or "").strip()
        if not word_pub:
            continue
        wordpub_info[word_pub] = (
            (r.get("word_id") or "").strip(),
            (r.get("word") or "").strip(),
            (r.get("meaning") or "").strip(),
        )

    words_pretty: dict[str, list[str]] = {}
    image_word_ids: dict[str, list[str]] = {}
    for image_id, pubs in image_to_wordpub.items():
        pretty: list[str] = []
        ids: list[str] = []
        for wp in sorted(pubs):
            wid, wzh, men = wordpub_info.get(wp, ("", "", ""))
            if wid:
                # Show stable public IDs in UI (HSKx-W-xxxx) to avoid internal-id noise.
                pretty.append(f"{wp} {wzh} ({men})")
                ids.append(wid)
            else:
                pretty.append(wp)
        words_pretty[image_id] = pretty
        image_word_ids[image_id] = sorted(set(ids))
    return words_pretty, image_word_ids


def semantic_exists(name: str) -> bool:
    if not name:
        return False
    p = SEMANTIC_DIR / name
    return p.exists() or p.is_symlink()


def runtime_exists_for_words(word_ids: list[str]) -> bool:
    for wid in word_ids:
        if not wid:
            continue
        candidates = [f"word_{wid}.webp"]
        if wid.startswith("W") and wid[1:].isdigit():
            candidates.append(f"word_{int(wid[1:])}.webp")
        for name in candidates:
            p1 = ASSETS_DIR / name
            p2 = STATIC_DIR / name
            if _is_usable_image(p1) or _is_usable_image(p2):
                return True
    return False


def runtime_exists_exact_word(word_id: str) -> bool:
    """Compatibility helper for future filtering/reporting."""
    if not word_id:
        return False
    candidates = [f"word_{word_id}.webp"]
    if word_id.startswith("W") and word_id[1:].isdigit():
        candidates.append(f"word_{int(word_id[1:])}.webp")
    for name in candidates:
        if _is_usable_image(ASSETS_DIR / name) or _is_usable_image(STATIC_DIR / name):
            return True
    return False


def _search_blob(
    r: dict[str, str],
    words_pretty: dict[str, list[str]],
    image_word_ids: dict[str, list[str]],
) -> str:
    image_id = r.get("image_id", "")
    parts = [
        r.get("recommended_filename", ""),
        r.get("image_id", ""),
        r.get("name_en", ""),
        r.get("category", ""),
        r.get("concept_key", ""),
        " ".join(words_pretty.get(image_id, [])),
        " ".join(image_word_ids.get(image_id, [])),
    ]
    blob = " | ".join(x for x in parts if x).lower()
    # Make underscore-delimited names searchable by plain words.
    return blob + " " + blob.replace("_", " ")


def find_search_matches(
    rows: list[dict[str, str]],
    query: str,
    words_pretty: dict[str, list[str]],
    image_word_ids: dict[str, list[str]],
) -> list[int]:
    tokens = [t for t in query.lower().split() if t]
    if not tokens:
        return []
    out: list[int] = []
    for i, r in enumerate(rows, start=1):
        blob = _search_blob(r, words_pretty, image_word_ids)
        if all(tok in blob for tok in tokens):
            out.append(i)
    return out


def first_match_at_or_after(matches: list[int], current_idx: int) -> int:
    for m in matches:
        if m >= current_idx:
            return m
    return matches[0]


def next_match_after(matches: list[int], current_idx: int) -> int:
    for m in matches:
        if m > current_idx:
            return m
    return matches[0]


def prev_match_before(matches: list[int], current_idx: int) -> int:
    for m in reversed(matches):
        if m < current_idx:
            return m
    return matches[-1]


def resolve_auto_done(has_semantic: bool, has_runtime: bool, done_policy: str) -> bool:
    if done_policy == "semantic":
        return has_semantic
    if done_policy == "runtime":
        return has_runtime
    return has_semantic or has_runtime


def list_source_files() -> list[Path]:
    out: list[Path] = []
    if not SOURCE_DIR.exists():
        return out
    for p in SOURCE_DIR.iterdir():
        if not p.is_file():
            continue
        if p.name.startswith("."):
            continue
        if p.suffix.lower() not in {".webp", ".png", ".jpg", ".jpeg"}:
            continue
        out.append(p)
    out.sort(key=lambda p: (p.stat().st_mtime, p.name.lower()))
    return out


def _read_escape_tail(fd: int) -> str:
    """Read any pending bytes that belong to an escape sequence."""
    seq = ""
    try:
        import select

        while True:
            ready, _, _ = select.select([fd], [], [], 0.004)
            if not ready:
                break
            chunk = os.read(fd, 1).decode("utf-8", errors="ignore")
            if not chunk:
                break
            seq += chunk
    except Exception:
        return seq
    return seq


def read_key() -> str:
    """Read a single key press (no Enter on TTY)."""
    if not sys.stdin.isatty():
        return input("> ").strip()

    print("> ", end="", flush=True)
    try:
        import termios
        import tty

        fd = sys.stdin.fileno()
        old = termios.tcgetattr(fd)
        try:
            tty.setraw(fd)
            ch = sys.stdin.read(1)
            if ch == "\x1b":
                seq = _read_escape_tail(fd)
                if "[D" in seq:
                    ch = "1"  # left arrow -> prev
                elif "[C" in seq:
                    ch = "2"  # right arrow -> next
                else:
                    ch = ""
            if ch in ("\r", "\n"):
                # No implicit action on Enter; avoid accidental auto-advance.
                ch = ""
            # Drop buffered repeats/noise so one press maps to one action.
            termios.tcflush(fd, termios.TCIFLUSH)
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old)
    except Exception:
        ch = input().strip()

    print()
    return ch.strip()


def run_ingest_one(
    idx: int,
    *,
    catalog: Path,
    naming: Path,
    links: Path,
    word_map: Path,
    cursor_file: Path,
    category_filter: str | None,
    all_categories: bool,
    all_object_rows: bool,
    include_unlinked: bool,
    done_policy: str,
    levels: str,
) -> bool:
    cmdline = [
        "python3",
        "tools/ingest_hsk1_chatgpt_images.py",
        "ingest",
        "--start-index",
        str(idx),
        "--count",
        "1",
        "--overwrite",
        "--move-processed",
        "--catalog",
        str(catalog),
        "--naming",
        str(naming),
        "--links",
        str(links),
        "--word-map",
        str(word_map),
        "--cursor-file",
        str(cursor_file),
        "--done-policy",
        done_policy,
    ]
    if levels.strip():
        cmdline.extend(["--levels", levels.strip()])
    if all_categories:
        cmdline.append("--all-categories")
    elif category_filter:
        cmdline.extend(["--category", category_filter])
    if all_object_rows:
        cmdline.append("--all-object-rows")
    if include_unlinked:
        cmdline.append("--include-unlinked")
    print(color("Running: " + " ".join(cmdline), CYAN + BOLD))
    res = subprocess.run(cmdline, cwd=str(Path.cwd()))
    if res.returncode != 0:
        print(color("Ingest failed for current item.", RED + BOLD))
        return False
    return True


def clamp(v: int, lo: int, hi: int) -> int:
    return max(lo, min(hi, v))


def fmt_tags(r: dict[str, str]) -> str:
    tags: list[str] = []
    for k in ["semantic_category", "semantic_subcategory", "semantic_concept", "semantic_variant"]:
        val = r.get(k, "")
        if val:
            tags.append(val)
    fn = r.get("recommended_filename", "")
    if fn:
        for tok in fn.replace(".webp", "").split("_"):
            if tok and (not tok.isdigit()) and tok not in tags:
                tags.append(tok)
    return ", ".join(tags[:24])


def is_done(
    r: dict[str, str],
    manual_done: set[str],
    image_word_ids: dict[str, list[str]],
    done_policy: str,
) -> bool:
    image_id = r["image_id"]
    semantic_name = r.get("recommended_filename", "")
    has_semantic = semantic_exists(semantic_name)
    has_runtime = runtime_exists_for_words(image_word_ids.get(image_id, []))
    return (
        resolve_auto_done(has_semantic, has_runtime, done_policy)
        or (image_id in manual_done)
    )


def filter_rows(
    rows: list[dict[str, str]],
    manual_done: set[str],
    only_missing: bool,
    image_word_ids: dict[str, list[str]],
    done_policy: str,
) -> list[dict[str, str]]:
    if not only_missing:
        return rows
    return [r for r in rows if not is_done(r, manual_done, image_word_ids, done_policy)]


def filter_by_category(rows: list[dict[str, str]], category: str | None) -> list[dict[str, str]]:
    if not category:
        return rows
    return [r for r in rows if (r.get("category") or "").strip() == category]


def filter_memorization_objects(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    return [
        r
        for r in rows
        if is_memorization_object_row(
            category=r.get("category", ""),
            name_en=r.get("name_en", ""),
            concept_key=r.get("concept_key", ""),
            recommended_filename=r.get("recommended_filename", ""),
        )
    ]


def filter_by_levels(rows: list[dict[str, str]], raw_levels: str) -> list[dict[str, str]]:
    levels = {x.strip().upper() for x in (raw_levels or "").split(",") if x.strip()}
    if not levels:
        return rows
    return [r for r in rows if (r.get("hsk_level") or "").strip().upper() in levels]


def next_missing_index(
    rows: list[dict[str, str]],
    idx: int,
    manual_done: set[str],
    image_word_ids: dict[str, list[str]],
    done_policy: str,
) -> int:
    n = len(rows)
    if n == 0:
        return 1
    start = idx
    j = idx
    while True:
        j += 1
        if j > n:
            j = 1
        if not is_done(rows[j - 1], manual_done, image_word_ids, done_policy):
            return j
        if j == start:
            return idx


def display(
    rows: list[dict[str, str]],
    idx: int,
    manual_done: set[str],
    only_missing: bool,
    words_pretty: dict[str, list[str]],
    image_word_ids: dict[str, list[str]],
    done_policy: str,
    category_label: str,
    title: str,
    search_query: str = "",
    search_matches: list[int] | None = None,
) -> None:
    total = len(rows)
    r = rows[idx - 1]
    image_id = r["image_id"]
    name = r.get("recommended_filename", "") or "(missing recommended_filename)"
    has_semantic = semantic_exists(name)
    has_runtime = runtime_exists_for_words(image_word_ids.get(image_id, []))
    auto_done = resolve_auto_done(has_semantic, has_runtime, done_policy)
    done = auto_done or (image_id in manual_done)
    man_done = image_id in manual_done
    auto_sources: list[str] = []
    if has_semantic:
        auto_sources.append("semantic")
    if has_runtime:
        auto_sources.append("runtime")

    status = color("DONE", GREEN + BOLD) if done else color("MISSING", RED + BOLD)
    scope = color("MISSING-ONLY", CYAN + BOLD) if only_missing else color("ALL", YELLOW + BOLD)

    print("\n" + "=" * 72)
    print(
        f"{color(title, WHITE + BOLD)} | MODE: {scope} | "
        f"CATEGORY: {color(category_label, MAGENTA + BOLD)} | "
        f"TOTAL: {color(str(total), WHITE + BOLD)} | CURRENT: {color(str(idx), WHITE + BOLD)}"
    )
    print(
        f"STATUS: {status} | auto_done={color(str(auto_done), GREEN if auto_done else DIM)} "
        f"manual_done={color(str(man_done), GREEN if man_done else DIM)} "
        f"| policy={done_policy} | auto_source={'+'.join(auto_sources) if auto_sources else 'none'}"
    )
    if search_query:
        sm = search_matches or []
        if sm:
            current_pos = sm.index(idx) + 1 if idx in sm else 0
            pos_text = str(current_pos) if current_pos else "-"
            print(
                f"SEARCH: {color(search_query, CYAN + BOLD)} | "
                f"matches={color(str(len(sm)), GREEN + BOLD)} | current_match={pos_text}"
            )
        else:
            print(
                f"SEARCH: {color(search_query, CYAN + BOLD)} | "
                f"{color('matches=0', RED + BOLD)}"
            )
    print("-" * 72)
    print(f"{color('name:', MAGENTA + BOLD)} {name}")
    print(f"{color('image_id:', BLUE + BOLD)} {image_id}")
    print(f"{color('name_en:', BLUE + BOLD)} {r.get('name_en', '')}")
    print(
        f"{color('category:', BLUE + BOLD)} {r.get('category', '')} | "
        f"{color('concept_key:', BLUE + BOLD)} {r.get('concept_key', '')}"
    )
    print(f"{color('size:', BLUE + BOLD)} {r.get('image_size', '1024x1024')} (1:1)")
    print(f"{color('tags:', YELLOW + BOLD)} {fmt_tags(r)}")
    print(f"{color('prompt:', CYAN + BOLD)} {r.get('prompt_en', '')}")

    wl = words_pretty.get(image_id, [])
    if wl:
        print(color("words:", GREEN + BOLD))
        for x in wl[:8]:
            print(f"  - {x}")
        if len(wl) > 8:
            print(f"  - ... +{len(wl) - 8} more")
    else:
        print(color("words: NO PRIMARY WORD LINK", RED + BOLD))

    src_files = list_source_files()
    print(color("source_queue:", MAGENTA + BOLD), len(src_files))
    if done:
        print(color("Already covered. No new image needed for this row.", GREEN + BOLD))
        print(color("Tip: press [4] for next missing or [6] to switch mode.", DIM))
    elif src_files:
        src = src_files[0]
        rename_cmd = f'mv "{src}" "{SOURCE_DIR / name}"'
        print(color("next_source_file:", MAGENTA + BOLD), src.name)
        print(color("RENAME TO:", GREEN + BOLD), name)
        print(color("rename_cmd:", CYAN + BOLD), rename_cmd)
    else:
        print(color("Drop image files into: images omnis/vocab_images/chat gpt generation", DIM))

    print("-" * 72)
    print(color("Buttons:", WHITE + BOLD))
    print(f"  {color('[1] ⬅️  Previous', BLUE + BOLD)}")
    print(f"  {color('[2] ➡️  Next', CYAN + BOLD)}")
    print(f"  {color('[3] ✅  Save current (ingest 1)', GREEN + BOLD)}")
    print(f"  {color('[4] ⏭️  Next missing', YELLOW + BOLD)}")
    print(f"  {color('[5] 🔢  Go to index', MAGENTA + BOLD)}")
    print(f"  {color('[6] 🔄  Toggle MISSING-ONLY / ALL', WHITE + BOLD)}")
    print(f"  {color('[7] 🏷️  Rename first dropped file + save current', CYAN + BOLD)}")
    print(f"  {color('[8] 📌  Manual Done / Undone (no file copy)', DIM)}")
    print(f"  {color('[9] 🔎  Search / Next match / Clear', MAGENTA + BOLD)}")
    print(f"  {color('[0] 🛑  Quit', RED + BOLD)}")
    print(color("Press one key (no Enter needed).", DIM))


def main() -> int:
    args = parse_args()

    catalog = Path(args.catalog)
    naming = Path(args.naming)
    links = Path(args.links)
    word_map = Path(args.word_map)
    cursor_file = Path(args.cursor_file)
    manual_done_file = Path(args.manual_done_file)

    for req in [catalog, naming, links, word_map]:
        if not req.exists():
            raise SystemExit(f"Required file missing: {req}")
    print(color("config:", WHITE + BOLD))
    print(f"  catalog: {catalog}")
    print(f"  naming: {naming}")
    print(f"  links: {links}")
    print(f"  word_map: {word_map}")
    print(f"  done_policy: {args.done_policy}")

    all_rows = build_rows(catalog, naming)
    all_rows = filter_by_levels(all_rows, args.levels)
    category_filter = None if args.all_categories else (args.category or "").strip()
    all_rows = filter_by_category(all_rows, category_filter)
    using_object_mem_filter = bool(category_filter == "object_scene" and not args.all_object_rows)
    if using_object_mem_filter:
        all_rows = filter_memorization_objects(all_rows)
    if not all_rows:
        raise SystemExit("No rows found for the selected category filter.")

    words_pretty, image_word_ids = build_word_maps(links, word_map)
    if not args.include_unlinked:
        all_rows = [r for r in all_rows if image_word_ids.get(r.get("image_id", ""))]
    if not all_rows:
        raise SystemExit("No rows left after primary-link filtering.")
    manual_done = load_manual_done(manual_done_file)
    only_missing = not bool(args.all)
    search_query = (args.search or "").strip()

    if search_query:
        all_rows = [
            r
            for r in all_rows
            if find_search_matches([r], search_query, words_pretty, image_word_ids)
        ]
        if not all_rows:
            print(color(f'No rows match search="{search_query}".', RED + BOLD))
            return 0

    rows = filter_rows(all_rows, manual_done, only_missing, image_word_ids, args.done_policy)
    if not rows:
        print("All images marked done.")
        return 0

    idx = clamp(read_cursor(cursor_file), 1, len(rows))

    while True:
        rows = filter_rows(all_rows, manual_done, only_missing, image_word_ids, args.done_policy)
        if not rows:
            print("\nAll images done.")
            write_cursor(cursor_file, 1)
            return 0

        idx = clamp(idx, 1, len(rows))
        write_cursor(cursor_file, idx)
        search_matches = (
            find_search_matches(rows, search_query, words_pretty, image_word_ids)
            if search_query
            else []
        )
        display(
            rows,
            idx,
            manual_done,
            only_missing,
            words_pretty,
            image_word_ids,
            args.done_policy,
            (f"{category_filter}+memorization" if using_object_mem_filter else (category_filter or "ALL")),
            args.title,
            search_query=search_query,
            search_matches=search_matches,
        )
        cmd = read_key()

        if cmd == "0":
            print("bye")
            return 0
        if cmd == "1":
            if search_query and search_matches:
                idx = prev_match_before(search_matches, idx)
            else:
                idx = idx - 1 if idx > 1 else len(rows)
            continue
        if cmd == "2":
            if search_query and search_matches:
                idx = next_match_after(search_matches, idx)
            else:
                idx = idx + 1 if idx < len(rows) else 1
            continue
        if cmd == "3":
            src_files = list_source_files()
            if not src_files:
                print(color("No dropped image files found in source folder.", RED + BOLD))
                print(color("Drop one image first, then press [3] or [7].", DIM))
                continue
            cur = rows[idx - 1]
            target_name = (cur.get("recommended_filename") or "").strip()
            exact_match_exists = bool(target_name) and any(
                f.name == target_name for f in src_files
            )
            if len(src_files) > 1 and not exact_match_exists:
                print(color("Ambiguous source queue: multiple dropped files found.", RED + BOLD))
                print(
                    color(
                        "Use [7] to rename first dropped file to target name, then save.",
                        DIM,
                    )
                )
                continue
            write_cursor(cursor_file, idx)
            run_ingest_one(
                idx,
                catalog=catalog,
                naming=naming,
                links=links,
                word_map=word_map,
                cursor_file=cursor_file,
                category_filter=category_filter,
                all_categories=bool(args.all_categories),
                all_object_rows=bool(args.all_object_rows),
                include_unlinked=bool(args.include_unlinked),
                done_policy=args.done_policy,
                levels=args.levels,
            )
            idx = clamp(idx, 1, len(rows))
            continue
        if cmd == "4":
            idx = next_missing_index(rows, idx, manual_done, image_word_ids, args.done_policy)
            continue
        if cmd == "5":
            raw = input("goto index: ").strip()
            try:
                idx = clamp(int(raw), 1, len(rows))
            except ValueError:
                pass
            continue
        if cmd == "6":
            only_missing = not only_missing
            idx = 1
            continue
        if cmd == "7":
            src_files = list_source_files()
            if not src_files:
                print(color("No dropped files found in source folder.", RED + BOLD))
                continue
            cur = rows[idx - 1]
            target_name = cur.get("recommended_filename", "").strip()
            if not target_name:
                print(color("Current row has empty recommended filename.", RED + BOLD))
                continue
            src = src_files[0]
            dst = SOURCE_DIR / target_name
            if src.name == target_name:
                print(color("Source file already has target name.", YELLOW + BOLD))
            elif dst.exists():
                print(color(f"Target already exists: {dst.name} (skip rename)", YELLOW + BOLD))
            else:
                src.rename(dst)
                print(color(f"Renamed: {src.name} -> {dst.name}", GREEN + BOLD))

            # Auto-save current after rename step.
            write_cursor(cursor_file, idx)
            run_ingest_one(
                idx,
                catalog=catalog,
                naming=naming,
                links=links,
                word_map=word_map,
                cursor_file=cursor_file,
                category_filter=category_filter,
                all_categories=bool(args.all_categories),
                all_object_rows=bool(args.all_object_rows),
                include_unlinked=bool(args.include_unlinked),
                done_policy=args.done_policy,
                levels=args.levels,
            )
            idx = clamp(idx, 1, len(rows))
            continue
        if cmd == "8":
            cur = rows[idx - 1]
            image_id = cur["image_id"]
            if image_id in manual_done:
                manual_done.remove(image_id)
            else:
                manual_done.add(image_id)
            save_manual_done(manual_done_file, manual_done)
            idx = clamp(idx, 1, len(rows))
            continue
        if cmd == "9":
            raw = input("find (text=set, Enter=next, clear=clear): ").strip()
            if raw.lower() in {"clear", "/clear", "/"}:
                search_query = ""
                print(color("Search cleared.", YELLOW + BOLD))
                continue

            # New search query -> jump to first match at/after current.
            if raw:
                search_query = raw
                matches = find_search_matches(rows, search_query, words_pretty, image_word_ids)
                if not matches:
                    print(color("No matches found.", RED + BOLD))
                    continue
                idx = first_match_at_or_after(matches, idx)
                continue

            # Empty input -> jump to next match for existing query.
            if not search_query:
                print(color("No active search. Press 9 and type text.", YELLOW + BOLD))
                continue
            matches = find_search_matches(rows, search_query, words_pretty, image_word_ids)
            if not matches:
                print(color("No matches found for active search.", RED + BOLD))
                continue
            idx = next_match_after(matches, idx)
            continue

        # Unknown/empty input: no-op (prevents runaway next-swipes).
        continue


if __name__ == "__main__":
    raise SystemExit(main())
