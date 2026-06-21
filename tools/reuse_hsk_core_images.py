#!/usr/bin/env python3
"""Build/apply safe image reuse for HSK core queues.

Goal:
- Reuse existing images for missing rows when English meaning matches exactly
  (normalized), so generation workload drops without breaking current runtime.

This tool can:
1) `preview` -> produce a reuse plan CSV + summary only.
2) `apply`   -> execute plan (copy/symlink semantic + runtime word files).
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import os
import re
import shutil
from dataclasses import dataclass
from pathlib import Path


DEFAULT_CATALOG = "docs/reports/hsk_core_images_queue_v1_catalog_2026-02-17.csv"
DEFAULT_NAMING = "docs/reports/hsk_core_images_queue_v1_naming_2026-02-17.csv"
DEFAULT_LINKS = "docs/reports/hsk_core_images_queue_v1_links_2026-02-17.csv"
DEFAULT_WORD_MAP = "docs/reports/hsk_core_images_queue_v1_word_map_2026-02-17.csv"

DEFAULT_SEMANTIC_DIR = "images omnis/vocab_images/assets_images"
DEFAULT_ASSETS_DIR = "assets/images"
DEFAULT_STATIC_DIR = "backend/static/images"
DEFAULT_REPORT_DIR = "docs/reports"
MIN_IMAGE_BYTES = 128


@dataclass(frozen=True)
class RowInfo:
    image_id: str
    category: str
    recommended_filename: str
    word_public_id: str
    word_id: str
    word_zh: str
    meaning_en: str
    meaning_norm: str
    semantic_exists: bool
    runtime_exists: bool


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("cmd", choices=["preview", "apply"])
    p.add_argument("--catalog", default=DEFAULT_CATALOG)
    p.add_argument("--naming", default=DEFAULT_NAMING)
    p.add_argument("--links", default=DEFAULT_LINKS)
    p.add_argument("--word-map", default=DEFAULT_WORD_MAP)
    p.add_argument("--semantic-dir", default=DEFAULT_SEMANTIC_DIR)
    p.add_argument("--assets-dir", default=DEFAULT_ASSETS_DIR)
    p.add_argument("--static-dir", default=DEFAULT_STATIC_DIR)
    p.add_argument("--report-dir", default=DEFAULT_REPORT_DIR)
    p.add_argument(
        "--alias-csv",
        default="docs/specs/image_reuse_aliases_v1.csv",
        help=(
            "Optional alias mapping CSV with columns: target_meaning,source_meaning,reason "
            "(normalized internally)"
        ),
    )
    p.add_argument(
        "--category",
        default="",
        help="Optional category filter (e.g. object_scene). Empty = all",
    )
    p.add_argument(
        "--semantic-mode",
        choices=["copy", "symlink"],
        default="copy",
        help="How to create semantic target files in apply mode",
    )
    p.add_argument(
        "--max-rows",
        type=int,
        default=0,
        help="Optional limit on number of planned/apply rows (0 = no limit)",
    )
    p.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing targets if present",
    )
    return p.parse_args()


def load_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def normalize_meaning(text: str) -> str:
    s = (text or "").strip().lower()
    s = re.sub(r"\b(to|a|an|the)\b", " ", s)
    s = re.sub(r"[^a-z0-9 ]+", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def is_usable_image(path: Path) -> bool:
    try:
        return path.is_file() and path.stat().st_size > MIN_IMAGE_BYTES
    except OSError:
        return False


def runtime_names_for_word_id(word_id: str) -> list[str]:
    out = [f"word_{word_id}.webp"]
    if word_id.startswith("W") and word_id[1:].isdigit():
        out.append(f"word_{int(word_id[1:])}.webp")
    return out


def runtime_exists(word_id: str, assets_dir: Path, static_dir: Path) -> bool:
    if not word_id:
        return False
    for name in runtime_names_for_word_id(word_id):
        if is_usable_image(assets_dir / name) or is_usable_image(static_dir / name):
            return True
    return False


def first_runtime_source_path(word_id: str, assets_dir: Path, static_dir: Path) -> Path | None:
    for name in runtime_names_for_word_id(word_id):
        p1 = assets_dir / name
        if is_usable_image(p1):
            return p1
        p2 = static_dir / name
        if is_usable_image(p2):
            return p2
    return None


def build_rows(
    *,
    naming_path: Path,
    links_path: Path,
    word_map_path: Path,
    semantic_dir: Path,
    assets_dir: Path,
    static_dir: Path,
    category_filter: str,
) -> list[RowInfo]:
    naming_rows = load_csv(naming_path)
    links_rows = load_csv(links_path)
    word_rows = load_csv(word_map_path)

    image_to_word_pub = {
        (r.get("image_id") or "").strip(): (r.get("word_public_id") or "").strip()
        for r in links_rows
        if (r.get("image_id") or "").strip()
    }
    word_pub_to_word = {
        (r.get("word_public_id") or "").strip(): r
        for r in word_rows
        if (r.get("word_public_id") or "").strip()
    }

    out: list[RowInfo] = []
    for nr in naming_rows:
        image_id = (nr.get("image_id") or "").strip()
        if not image_id:
            continue
        category = (nr.get("category") or "").strip()
        if category_filter and category != category_filter:
            continue

        rec_name = (nr.get("recommended_filename") or "").strip()
        word_pub = image_to_word_pub.get(image_id, "")
        wr = word_pub_to_word.get(word_pub, {})
        word_id = (wr.get("word_id") or "").strip()
        word_zh = (wr.get("word") or "").strip()
        meaning = (wr.get("meaning") or "").strip()
        norm = normalize_meaning(meaning)
        sem_exists = bool(rec_name) and is_usable_image(semantic_dir / rec_name)
        run_exists = runtime_exists(word_id, assets_dir, static_dir)

        out.append(
            RowInfo(
                image_id=image_id,
                category=category,
                recommended_filename=rec_name,
                word_public_id=word_pub,
                word_id=word_id,
                word_zh=word_zh,
                meaning_en=meaning,
                meaning_norm=norm,
                semantic_exists=sem_exists,
                runtime_exists=run_exists,
            )
        )
    return out


def resolve_source_image_path(
    row: RowInfo,
    semantic_dir: Path,
    assets_dir: Path,
    static_dir: Path,
) -> Path | None:
    if row.recommended_filename:
        p = semantic_dir / row.recommended_filename
        if p.exists():
            return p
    return first_runtime_source_path(row.word_id, assets_dir, static_dir)


def plan_reuse(
    rows: list[RowInfo],
    semantic_dir: Path,
    assets_dir: Path,
    static_dir: Path,
    alias_map: dict[str, list[tuple[str, str]]],
) -> list[dict[str, str]]:
    covered = [r for r in rows if (r.semantic_exists or r.runtime_exists)]
    missing = [r for r in rows if not (r.semantic_exists or r.runtime_exists)]

    sources_by_norm: dict[str, list[RowInfo]] = {}
    for r in covered:
        if r.meaning_norm:
            sources_by_norm.setdefault(r.meaning_norm, []).append(r)

    plan: list[dict[str, str]] = []
    for t in missing:
        if not t.meaning_norm:
            continue
        src_candidates = sources_by_norm.get(t.meaning_norm, [])
        reason = "exact_meaning_norm_match"
        if not src_candidates:
            alias_targets = alias_map.get(t.meaning_norm, [])
            for source_norm, alias_reason in alias_targets:
                src_candidates = sources_by_norm.get(source_norm, [])
                if src_candidates:
                    reason = alias_reason or "manual_alias_match"
                    break
        if not src_candidates:
            continue
        src = None
        for cand in src_candidates:
            if cand.word_id and cand.word_id != t.word_id:
                src = cand
                break
        if src is None:
            src = src_candidates[0]
        src_path = resolve_source_image_path(src, semantic_dir, assets_dir, static_dir)
        if src_path is None:
            continue
        plan.append(
            {
                "target_image_id": t.image_id,
                "target_word_public_id": t.word_public_id,
                "target_word_id": t.word_id,
                "target_word_zh": t.word_zh,
                "target_meaning_en": t.meaning_en,
                "target_filename": t.recommended_filename,
                "source_image_id": src.image_id,
                "source_word_public_id": src.word_public_id,
                "source_word_id": src.word_id,
                "source_word_zh": src.word_zh,
                "source_meaning_en": src.meaning_en,
                "source_filename": src.recommended_filename,
                "source_path": str(src_path),
                "reason": reason,
            }
        )
    return plan


def load_alias_map(path: Path) -> dict[str, list[tuple[str, str]]]:
    out: dict[str, list[tuple[str, str]]] = {}
    if not path.exists():
        return out
    rows = load_csv(path)
    for r in rows:
        t = normalize_meaning((r.get("target_meaning") or "").strip())
        s = normalize_meaning((r.get("source_meaning") or "").strip())
        reason = (r.get("reason") or "").strip() or "manual_alias_match"
        if not t or not s:
            continue
        out.setdefault(t, []).append((s, reason))
    return out


def copy_or_link(
    src: Path,
    dst: Path,
    *,
    mode: str,
    overwrite: bool,
) -> str:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() or dst.is_symlink():
        if not overwrite:
            return "exists_skip"
        if dst.is_dir():
            raise RuntimeError(f"Cannot overwrite directory target: {dst}")
        dst.unlink()
    if mode == "symlink":
        try:
            rel = os.path.relpath(src, start=dst.parent)
            dst.symlink_to(rel)
            return "linked"
        except Exception:
            shutil.copy2(src, dst)
            return "copied_fallback"
    shutil.copy2(src, dst)
    return "copied"


def apply_plan(
    plan: list[dict[str, str]],
    *,
    semantic_dir: Path,
    assets_dir: Path,
    static_dir: Path,
    semantic_mode: str,
    overwrite: bool,
) -> list[dict[str, str]]:
    out: list[dict[str, str]] = []
    for row in plan:
        src = Path(row["source_path"])
        target_filename = row["target_filename"]
        target_word_id = row["target_word_id"]
        if not src.exists() or not target_filename or not target_word_id:
            out.append(
                {
                    **row,
                    "semantic_action": "invalid_skip",
                    "assets_action": "invalid_skip",
                    "static_action": "invalid_skip",
                }
            )
            continue

        sem_dst = semantic_dir / target_filename
        sem_action = copy_or_link(src, sem_dst, mode=semantic_mode, overwrite=overwrite)

        runtime_name = f"word_{target_word_id}.webp"
        assets_action = copy_or_link(sem_dst, assets_dir / runtime_name, mode="copy", overwrite=overwrite)
        static_action = copy_or_link(sem_dst, static_dir / runtime_name, mode="copy", overwrite=overwrite)

        out.append(
            {
                **row,
                "semantic_action": sem_action,
                "assets_action": assets_action,
                "static_action": static_action,
            }
        )
    return out


def write_csv(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        with path.open("w", encoding="utf-8", newline="") as f:
            f.write("")
        return
    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)


def main() -> int:
    args = parse_args()

    catalog = Path(args.catalog)
    naming = Path(args.naming)
    links = Path(args.links)
    word_map = Path(args.word_map)
    semantic_dir = Path(args.semantic_dir)
    assets_dir = Path(args.assets_dir)
    static_dir = Path(args.static_dir)
    report_dir = Path(args.report_dir)
    alias_csv = Path(args.alias_csv)
    for p in [catalog, naming, links, word_map]:
        if not p.exists():
            raise SystemExit(f"Required file missing: {p}")

    rows = build_rows(
        naming_path=naming,
        links_path=links,
        word_map_path=word_map,
        semantic_dir=semantic_dir,
        assets_dir=assets_dir,
        static_dir=static_dir,
        category_filter=(args.category or "").strip(),
    )
    total = len(rows)
    covered = sum(1 for r in rows if (r.semantic_exists or r.runtime_exists))
    missing = total - covered

    alias_map = load_alias_map(alias_csv)
    plan = plan_reuse(rows, semantic_dir, assets_dir, static_dir, alias_map)
    if args.max_rows and args.max_rows > 0:
        plan = plan[: args.max_rows]

    ts = dt.datetime.now(dt.UTC).strftime("%Y-%m-%dT%H-%M-%SZ")
    base = f"hsk_core_image_reuse_{ts}"
    plan_csv = report_dir / f"{base}_plan.csv"
    apply_csv = report_dir / f"{base}_applied.csv"

    write_csv(plan_csv, plan)

    summary = {
        "ok": True,
        "mode": args.cmd,
        "category_filter": (args.category or "ALL"),
        "total_rows": total,
        "covered_now": covered,
        "missing_now": missing,
        "reusable_by_exact_meaning": len(plan),
        "missing_after_reuse": max(0, missing - len(plan)),
        "plan_csv": str(plan_csv.resolve()),
        "alias_csv_used": str(alias_csv.resolve()) if alias_csv.exists() else "",
        "alias_rows": sum(len(v) for v in alias_map.values()),
    }

    if args.cmd == "apply":
        applied = apply_plan(
            plan,
            semantic_dir=semantic_dir,
            assets_dir=assets_dir,
            static_dir=static_dir,
            semantic_mode=args.semantic_mode,
            overwrite=bool(args.overwrite),
        )
        write_csv(apply_csv, applied)
        summary["applied_csv"] = str(apply_csv.resolve())
        summary["applied_rows"] = len(applied)

    print(summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
