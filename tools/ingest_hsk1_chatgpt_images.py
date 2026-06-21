#!/usr/bin/env python3
"""Ingest ChatGPT-generated HSK1 images into semantic + runtime locations.

Workflow:
1) Put generated images into:
     images omnis/vocab_images/chat gpt generation
2) Preview mapping (source file -> prompt/name/word ids)
3) Ingest and copy to:
   - images omnis/vocab_images/assets_images/{semantic_name}.webp
   - assets/images/word_{Wxxxxx}.webp
   - backend/static/images/word_{Wxxxxx}.webp

The script uses the same cursor file as hsk1_prompt_navigator.py, so it
assigns dropped files to the next image rows in deterministic order.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
import shutil
from pathlib import Path

from hsk1_object_filter import is_memorization_object_row

IMAGE_EXTS = {".webp", ".png", ".jpg", ".jpeg"}
MIN_IMAGE_BYTES = 128


def load_catalog(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    return sorted(rows, key=lambda r: (r.get("image_id") or ""))


def filter_by_category(rows: list[dict[str, str]], category: str | None) -> list[dict[str, str]]:
    if not category:
        return rows
    return [r for r in rows if (r.get("category") or "").strip() == category]


def filter_by_levels(rows: list[dict[str, str]], raw_levels: str) -> list[dict[str, str]]:
    levels = {x.strip().upper() for x in (raw_levels or "").split(",") if x.strip()}
    if not levels:
        return rows

    def row_level(r: dict[str, str]) -> str:
        return (r.get("hsk_level") or r.get("level") or "").strip().upper()

    return [r for r in rows if row_level(r) in levels]


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
            name = (row.get("recommended_filename") or "").strip()
            if image_id and name:
                out[image_id] = name
    return out


def load_wordpub_to_wordid(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    with path.open("r", encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            word_public_id = (row.get("word_public_id") or "").strip()
            word_id = (row.get("word_id") or "").strip()
            if word_public_id and word_id:
                out[word_public_id] = word_id
    return out


def load_image_to_wordpub(path: Path) -> dict[str, set[str]]:
    out: dict[str, set[str]] = {}
    with path.open("r", encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            image_id = (row.get("image_id") or "").strip()
            word_public_id = (row.get("word_public_id") or "").strip()
            relevance = (row.get("relevance") or "").strip().lower()
            if relevance != "primary":
                continue
            if image_id and word_public_id:
                out.setdefault(image_id, set()).add(word_public_id)
    return out


def read_cursor(path: Path) -> int:
    if not path.exists():
        return 1
    raw = path.read_text(encoding="utf-8").strip()
    if not raw:
        return 1
    try:
        idx = int(raw)
    except ValueError:
        return 1
    return max(1, idx)


def write_cursor(path: Path, value: int) -> None:
    path.write_text(str(max(1, value)), encoding="utf-8")


def files_same_content(a: Path, b: Path) -> bool:
    if (not a.exists()) or (not b.exists()):
        return False
    if a.stat().st_size != b.stat().st_size:
        return False
    h1 = hashlib.sha256()
    h2 = hashlib.sha256()
    with a.open("rb") as fa, b.open("rb") as fb:
        while True:
            ba = fa.read(1024 * 1024)
            bb = fb.read(1024 * 1024)
            if not ba and not bb:
                break
            h1.update(ba)
            h2.update(bb)
    return h1.digest() == h2.digest()


def is_usable_image(path: Path) -> bool:
    try:
        return (path.exists() or path.is_symlink()) and path.stat().st_size > MIN_IMAGE_BYTES
    except OSError:
        return False


def list_drop_files(source_dir: Path, order: str) -> list[Path]:
    if not source_dir.exists():
        return []
    out: list[Path] = []
    for p in source_dir.iterdir():
        if not p.is_file():
            continue
        if p.name.startswith("."):
            continue
        if p.suffix.lower() not in IMAGE_EXTS:
            continue
        out.append(p)
    if order == "name":
        out.sort(key=lambda p: p.name.lower())
    else:
        # Oldest first gives deterministic "queue" behavior.
        out.sort(key=lambda p: (p.stat().st_mtime, p.name.lower()))
    return out


def resolve_word_ids(
    image_id: str,
    image_to_wordpub: dict[str, set[str]],
    wordpub_to_wordid: dict[str, str],
) -> list[str]:
    out = {
        wordpub_to_wordid[wp]
        for wp in image_to_wordpub.get(image_id, set())
        if wordpub_to_wordid.get(wp)
    }
    return sorted(out)


def build_assignments(
    rows: list[dict[str, str]],
    name_map: dict[str, str],
    drop_files: list[Path],
    image_to_wordpub: dict[str, set[str]],
    wordpub_to_wordid: dict[str, str],
    start_index: int,
    count: int | None,
) -> list[dict[str, object]]:
    if start_index < 1:
        start_index = 1
    if start_index > len(rows):
        return []
    pool = list(drop_files)
    wanted_total = len(pool) if count is None else max(0, count)

    assignments: list[dict[str, object]] = []
    row_pos = start_index - 1
    while pool and len(assignments) < wanted_total:
        if row_pos >= len(rows):
            break
        row = rows[row_pos]
        image_id = (row.get("image_id") or "").strip()
        semantic_name = (name_map.get(image_id) or "").strip()
        if not semantic_name:
            semantic_name = (row.get("filename") or "").strip()
        # Prefer exact-name match from source queue when available.
        src = None
        if semantic_name:
            for i, cand in enumerate(pool):
                if cand.name == semantic_name:
                    src = cand
                    del pool[i]
                    break
        if src is None:
            src = pool.pop(0)
        word_ids = resolve_word_ids(image_id, image_to_wordpub, wordpub_to_wordid)
        assignments.append(
            {
                "index": row_pos + 1,
                "row": row,
                "image_id": image_id,
                "semantic_name": semantic_name,
                "word_ids": word_ids,
                "source_file": src,
            }
        )
        row_pos += 1
    return assignments


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def write_webp(src: Path, dst: Path, overwrite: bool) -> str:
    if dst.exists() or dst.is_symlink():
        if not overwrite:
            return "exists_skip"
        if src.suffix.lower() == ".webp" and files_same_content(src, dst):
            return "same_skip"
        dst.unlink()
    ensure_parent(dst)
    if src.suffix.lower() == ".webp":
        shutil.copy2(src, dst)
        return "copied_webp"

    # Non-webp source: convert via Pillow.
    try:
        from PIL import Image  # type: ignore
    except Exception as e:  # pragma: no cover - runtime dependency
        raise RuntimeError(
            f"Cannot convert {src.name} to webp (Pillow not installed): {e}"
        ) from e

    with Image.open(src) as im:
        im.save(dst, format="WEBP", quality=95, method=6)
    return "converted_to_webp"


def copy_file(src: Path, dst: Path, overwrite: bool) -> str:
    if dst.exists() or dst.is_symlink():
        if not overwrite:
            return "exists_skip"
        dst.unlink()
    ensure_parent(dst)
    shutil.copy2(src, dst)
    return "copied"


def render_assignment(a: dict[str, object], prompt_first: bool) -> str:
    row = a["row"]  # type: ignore[assignment]
    prompt = (row.get("prompt_en") or "").strip()  # type: ignore[attr-defined]
    semantic_name = str(a["semantic_name"])
    source = str(a["source_file"])
    word_ids = a["word_ids"]  # type: ignore[assignment]
    idx = int(a["index"])
    image_id = str(a["image_id"])
    name_en = (row.get("name_en") or "").strip()  # type: ignore[attr-defined]

    top = (
        f"prompt: {prompt}\nname: {semantic_name}\n"
        if prompt_first
        else f"name: {semantic_name}\nprompt: {prompt}\n"
    )
    return (
        f"[{idx:04d}] image_id={image_id}\n"
        f"{top}"
        f"source: {source}\n"
        f"name_en: {name_en}\n"
        f"word_ids: {', '.join(word_ids) if word_ids else 'NONE'}\n"
    )


def rebuild_assets_index(folder: Path, db_path: Path) -> Path:
    import re
    import sqlite3

    out = folder / "assets_images_word_index.csv"
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    pat = re.compile(r"^word_(W\d+)\.webp$")
    rows: list[dict[str, str]] = []
    for p in sorted(folder.iterdir()):
        if not p.is_file() and not p.is_symlink():
            continue
        if p.name == out.name:
            continue
        target_name = p.resolve().name if p.is_symlink() else p.name
        m = pat.match(target_name)
        word_id = m.group(1) if m else ""
        zh = ""
        en = ""
        if word_id:
            row = cur.execute(
                "SELECT text, meaning FROM concepts WHERE id=?",
                (word_id,),
            ).fetchone()
            if row:
                zh = row[0] or ""
                en = row[1] or ""
        rows.append(
            {
                "semantic_filename": p.name,
                "word_id": word_id,
                "word_zh": zh,
                "meaning_en": en,
                "source_target": str(p.resolve()) if p.is_symlink() else str(p.resolve()),
            }
        )
    with out.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(
            f,
            fieldnames=[
                "semantic_filename",
                "word_id",
                "word_zh",
                "meaning_en",
                "source_target",
            ],
        )
        w.writeheader()
        w.writerows(rows)
    return out


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("cmd", choices=["preview", "ingest"])
    p.add_argument(
        "--source-dir",
        default="images omnis/vocab_images/chat gpt generation",
        help="Folder where you drop raw generated images",
    )
    p.add_argument(
        "--semantic-dir",
        default="images omnis/vocab_images/assets_images",
        help="Semantic-name output folder",
    )
    p.add_argument("--assets-dir", default="assets/images", help="Runtime assets folder")
    p.add_argument(
        "--static-dir",
        default="backend/static/images",
        help="Backend static images folder",
    )
    p.add_argument(
        "--catalog",
        default="hsk1_universal_images_catalog_v2_2026-02-15.csv",
        help="Catalog CSV with prompt_en",
    )
    p.add_argument(
        "--naming",
        default="hsk1_universal_images_semantic_naming_v1_2026-02-15.csv",
        help="Naming CSV with recommended_filename",
    )
    p.add_argument(
        "--links",
        default="docs/reports/hsk1_sense_image_links_v1_2026-02-15.csv",
        help="Sense-image links CSV",
    )
    p.add_argument(
        "--word-map",
        default="docs/reports/hsk1_public_word_id_map_2026-02-15.csv",
        help="Word public-id -> word_id CSV",
    )
    p.add_argument(
        "--category",
        default="object_scene",
        help="Category filter (default: object_scene)",
    )
    p.add_argument(
        "--all-categories",
        action="store_true",
        help="Disable category filter and use all categories",
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
    p.add_argument("--cursor-file", default=".hsk1_prompt_cursor")
    p.add_argument(
        "--start-index",
        type=int,
        default=None,
        help="Override cursor start index (1-based)",
    )
    p.add_argument(
        "--count",
        type=int,
        default=None,
        help="How many dropped files to process (default: all dropped files)",
    )
    p.add_argument(
        "--missing-only",
        action="store_true",
        default=True,
        help="Use missing-only queue (default: on)",
    )
    p.add_argument(
        "--all",
        action="store_true",
        help="Use full queue (disable missing-only)",
    )
    p.add_argument(
        "--order",
        choices=["mtime", "name"],
        default="mtime",
        help="How to order files from source-dir before assignment",
    )
    p.add_argument("--prompt-first", action="store_true")
    p.add_argument("--overwrite", action="store_true")
    p.add_argument(
        "--move-processed",
        action="store_true",
        help="Move consumed source files to <source-dir>/_processed",
    )
    p.add_argument(
        "--db",
        default="backend/learning_path.db",
        help="DB path for assets index rebuild",
    )
    p.add_argument(
        "--done-policy",
        choices=["semantic", "runtime", "any"],
        default="runtime",
        help=(
            "What counts as already done when building missing-only queue: "
            "semantic file only, runtime word image only, or either (default: runtime)"
        ),
    )
    return p.parse_args()


def row_auto_done(
    image_id: str,
    semantic_name: str,
    word_ids: list[str],
    semantic_dir: Path,
    assets_dir: Path,
    static_dir: Path,
    done_policy: str,
) -> bool:
    has_semantic = False
    if semantic_name:
        sp = semantic_dir / semantic_name
        if sp.exists() or sp.is_symlink():
            has_semantic = True
    has_runtime = False
    for wid in word_ids:
        if not wid:
            continue
        candidates = [f"word_{wid}.webp"]
        if wid.startswith("W") and wid[1:].isdigit():
            candidates.append(f"word_{int(wid[1:])}.webp")
        for name in candidates:
            p1 = assets_dir / name
            p2 = static_dir / name
            if is_usable_image(p1) or is_usable_image(p2):
                has_runtime = True
                break
        if has_runtime:
            break
    if done_policy == "semantic":
        return has_semantic
    if done_policy == "runtime":
        return has_runtime
    return has_semantic or has_runtime


def main() -> int:
    args = parse_args()
    source_dir = Path(args.source_dir)
    semantic_dir = Path(args.semantic_dir)
    assets_dir = Path(args.assets_dir)
    static_dir = Path(args.static_dir)
    catalog = Path(args.catalog)
    naming = Path(args.naming)
    links = Path(args.links)
    word_map = Path(args.word_map)
    cursor_file = Path(args.cursor_file)
    db_path = Path(args.db)

    for need in [catalog, naming, links, word_map]:
        if not need.exists():
            raise SystemExit(f"Required file not found: {need}")

    all_rows = load_catalog(catalog)
    all_rows = filter_by_levels(all_rows, args.levels)
    source_rows = len(all_rows)
    category_filter = None if args.all_categories else (args.category or "").strip()
    name_map = load_name_map(naming)
    rows = filter_by_category(all_rows, category_filter)
    using_object_mem_filter = bool(category_filter == "object_scene" and not args.all_object_rows)
    if using_object_mem_filter:
        rows = filter_memorization_objects(rows, name_map)
    image_to_wordpub = load_image_to_wordpub(links)
    if (not args.include_unlinked) and category_filter == "object_scene":
        rows = [r for r in rows if image_to_wordpub.get((r.get("image_id") or "").strip())]
    if not rows:
        raise SystemExit("No rows found for selected category filter.")
    category_rows = len(rows)
    wordpub_to_wordid = load_wordpub_to_wordid(word_map)
    drop_files = list_drop_files(source_dir, order=args.order)

    use_missing_only = bool(args.missing_only) and (not bool(args.all))

    # Build queue rows (all or missing-only), aligned with button navigator behavior.
    queue_rows = rows
    if use_missing_only:
        filtered: list[dict[str, str]] = []
        for r in rows:
            image_id = (r.get("image_id") or "").strip()
            semantic_name = (name_map.get(image_id) or "").strip() or (r.get("filename") or "").strip()
            word_ids = resolve_word_ids(image_id, image_to_wordpub, wordpub_to_wordid)
            if not row_auto_done(
                image_id=image_id,
                semantic_name=semantic_name,
                word_ids=word_ids,
                semantic_dir=semantic_dir,
                assets_dir=assets_dir,
                static_dir=static_dir,
                done_policy=args.done_policy,
            ):
                filtered.append(r)
        queue_rows = filtered

    start_index = args.start_index if args.start_index else read_cursor(cursor_file)
    if queue_rows:
        start_index = max(1, min(start_index, len(queue_rows)))
    else:
        start_index = 1
    assignments = build_assignments(
        rows=queue_rows,
        name_map=name_map,
        drop_files=drop_files,
        image_to_wordpub=image_to_wordpub,
        wordpub_to_wordid=wordpub_to_wordid,
        start_index=start_index,
        count=args.count,
    )

    category_label = (
        f"{category_filter}+memorization" if using_object_mem_filter else (category_filter or "ALL")
    )
    print(f"category_filter: {category_label}")
    print(f"source_rows: {source_rows}")
    print(f"category_rows: {category_rows}")
    print(f"queue_mode: {'MISSING-ONLY' if use_missing_only else 'ALL'}")
    print(f"done_policy: {args.done_policy}")
    print(f"levels_filter: {args.levels or '(none)'}")
    print(f"queue_rows: {len(queue_rows)}")
    print(f"drop_files_found: {len(drop_files)}")
    print(f"cursor_start: {start_index}")
    print(f"planned_assignments: {len(assignments)}")

    if not assignments:
        print("Nothing to process.")
        return 0 if args.cmd == "preview" else 2

    if args.cmd == "preview":
        for a in assignments:
            print(render_assignment(a, prompt_first=args.prompt_first))
        return 0

    # ingest
    semantic_dir.mkdir(parents=True, exist_ok=True)
    assets_dir.mkdir(parents=True, exist_ok=True)
    static_dir.mkdir(parents=True, exist_ok=True)
    processed_dir = source_dir / "_processed"
    if args.move_processed:
        processed_dir.mkdir(parents=True, exist_ok=True)

    report_rows: list[dict[str, str]] = []
    last_success_index = start_index - 1

    for a in assignments:
        idx = int(a["index"])
        image_id = str(a["image_id"])
        semantic_name = str(a["semantic_name"])
        source_file = Path(str(a["source_file"]))
        row = a["row"]  # type: ignore[assignment]
        prompt = (row.get("prompt_en") or "").strip()  # type: ignore[attr-defined]
        word_ids: list[str] = list(a["word_ids"])  # type: ignore[assignment]

        if not semantic_name:
            raise SystemExit(f"Missing semantic name for image_id={image_id} at index={idx}")

        semantic_dst = semantic_dir / semantic_name
        semantic_mode = write_webp(source_file, semantic_dst, overwrite=args.overwrite)

        for wid in word_ids:
            assets_dst = assets_dir / f"word_{wid}.webp"
            static_dst = static_dir / f"word_{wid}.webp"
            copy_file(semantic_dst, assets_dst, overwrite=args.overwrite)
            copy_file(semantic_dst, static_dst, overwrite=args.overwrite)

        moved_to = ""
        if args.move_processed:
            move_dst = processed_dir / source_file.name
            if move_dst.exists():
                if files_same_content(source_file, move_dst):
                    source_file.unlink()
                    moved_to = f"duplicate_discarded:{move_dst.name}"
                else:
                    stem = move_dst.stem
                    suffix = move_dst.suffix
                    n = 2
                    while True:
                        cand = processed_dir / f"{stem}__{n}{suffix}"
                        if not cand.exists():
                            move_dst = cand
                            break
                        n += 1
                    shutil.move(str(source_file), str(move_dst))
                    moved_to = str(move_dst)
            else:
                shutil.move(str(source_file), str(move_dst))
                moved_to = str(move_dst)

        report_rows.append(
            {
                "index": str(idx),
                "image_id": image_id,
                "semantic_filename": semantic_name,
                "word_ids": "|".join(word_ids),
                "source_file": str(source_file),
                "prompt_en": prompt,
                "semantic_write_mode": semantic_mode,
                "moved_to": moved_to,
            }
        )
        last_success_index = idx
        write_cursor(cursor_file, idx + 1)
        print(
            f"[{idx:04d}] ok image_id={image_id} semantic={semantic_name} words={','.join(word_ids) if word_ids else 'NONE'}"
        )

    ts = dt.datetime.now(dt.UTC).strftime("%Y-%m-%dT%H-%M-%SZ")
    reports_dir = source_dir / "_reports"
    reports_dir.mkdir(parents=True, exist_ok=True)
    report_path = reports_dir / f"ingest_report_{ts}.csv"
    with report_path.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(
            f,
            fieldnames=[
                "index",
                "image_id",
                "semantic_filename",
                "word_ids",
                "source_file",
                "prompt_en",
                "semantic_write_mode",
                "moved_to",
            ],
        )
        w.writeheader()
        w.writerows(report_rows)

    index_path = rebuild_assets_index(semantic_dir, db_path)
    summary = {
        "ok": True,
        "processed": len(report_rows),
        "cursor_start": start_index,
        "cursor_end": last_success_index + 1,
        "report_csv": str(report_path.resolve()),
        "assets_index_csv": str(index_path.resolve()),
        "semantic_dir": str(semantic_dir.resolve()),
        "assets_dir": str(assets_dir.resolve()),
        "static_dir": str(static_dir.resolve()),
    }
    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
