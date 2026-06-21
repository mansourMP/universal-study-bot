#!/usr/bin/env python3
"""Generate lesson+image readiness reports for selected HSK levels.

Outputs:
- <prefix>_lesson_image_status_<date>.csv   (all concepts)
- <prefix>_lesson_image_missing_<date>.csv  (missing/tiny only)
- <prefix>_lesson_image_summary_<date>.json (counts + unit stats)

This script is non-destructive: it does not modify DB content.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import sqlite3
from pathlib import Path
from typing import Iterable

DEFAULT_DB = Path("backend/learning_path.db")
DEFAULT_OUT_DIR = Path("docs/reports")
DEFAULT_LEVELS = ["HSK1"]
DEFAULT_PREFIX = "hsk_lessons"
MIN_IMAGE_BYTES = 128


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Build lesson+image readiness reports")
    p.add_argument("--db", default=str(DEFAULT_DB), help="Path to learning_path.db")
    p.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR), help="Directory for output files")
    p.add_argument(
        "--levels",
        default=",".join(DEFAULT_LEVELS),
        help="Comma-separated levels (e.g. HSK1 or HSK1,HSK2,HSK3)",
    )
    p.add_argument("--prefix", default=DEFAULT_PREFIX, help="Output filename prefix")
    p.add_argument(
        "--catalog",
        default="",
        help="Optional catalog CSV (from build_hsk_core_image_queue.py). If omitted, prompt/name fields stay blank.",
    )
    p.add_argument(
        "--naming",
        default="",
        help="Optional naming CSV (from build_hsk_core_image_queue.py). If omitted, prompt/name fields stay blank.",
    )
    p.add_argument(
        "--min-image-bytes",
        type=int,
        default=MIN_IMAGE_BYTES,
        help="Minimum image size threshold to count as usable runtime image",
    )
    return p.parse_args()


def parse_levels(raw: str) -> list[str]:
    levels = [x.strip().upper() for x in raw.split(",") if x.strip()]
    return levels or DEFAULT_LEVELS


def load_csv_index(path: Path, key: str) -> dict[str, dict[str, str]]:
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    out: dict[str, dict[str, str]] = {}
    for r in rows:
        k = (r.get(key) or "").strip()
        if not k:
            continue
        out[k] = r
    return out


def runtime_candidates(word_id: str) -> list[str]:
    wid = (word_id or "").strip()
    if not wid:
        return []
    names = [f"word_{wid}.webp"]
    if wid.startswith("W") and wid[1:].isdigit():
        names.append(f"word_{int(wid[1:])}.webp")
    return names


def image_probe(word_id: str, min_bytes: int, roots: Iterable[Path]) -> tuple[str, int, str]:
    """Return (status, max_size_bytes, found_path).

    status:
      - ok: usable runtime image exists
      - tiny: image exists but <= min_bytes
      - missing: no runtime image found
    """
    max_size = 0
    found_path = ""
    any_found = False

    for name in runtime_candidates(word_id):
        for root in roots:
            p = root / name
            if p.exists() or p.is_symlink():
                any_found = True
                try:
                    size = p.stat().st_size
                except OSError:
                    size = 0
                if size > max_size:
                    max_size = size
                    found_path = str(p)
                if size > min_bytes:
                    return ("ok", size, str(p))
    if any_found:
        return ("tiny", max_size, found_path)
    return ("missing", 0, "")


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[1]
    db_path = (repo_root / args.db).resolve()
    out_dir = (repo_root / args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    levels = parse_levels(args.levels)

    if not db_path.exists():
        raise SystemExit(f"DB not found: {db_path}")

    today = dt.date.today().isoformat()
    status_path = out_dir / f"{args.prefix}_lesson_image_status_{today}.csv"
    missing_path = out_dir / f"{args.prefix}_lesson_image_missing_{today}.csv"
    summary_path = out_dir / f"{args.prefix}_lesson_image_summary_{today}.json"

    catalog_index: dict[str, dict[str, str]] = {}
    naming_index: dict[str, dict[str, str]] = {}

    if args.catalog:
        catalog_index = load_csv_index((repo_root / args.catalog).resolve(), "word_id")
    if args.naming:
        # naming file can be keyed by image_id; also includes concept via concept_key.
        # We join indirectly using image_id from catalog, so keep this by image_id.
        naming_index = load_csv_index((repo_root / args.naming).resolve(), "image_id")

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row

    try:
        placeholders = ",".join("?" for _ in levels)
        rows = conn.execute(
            f"""
            SELECT
                m.level,
                c.id AS word_id,
                c.text AS word_zh,
                COALESCE(
                    (
                        SELECT cl.meaning
                        FROM concept_localizations cl
                        WHERE cl.concept_id = c.id
                          AND cl.language_code = 'en'
                        ORDER BY cl.rowid DESC
                        LIMIT 1
                    ),
                    c.meaning,
                    ''
                ) AS meaning_en,
                COALESCE(
                    (
                        SELECT GROUP_CONCAT(DISTINCT uc.unit_id)
                        FROM unit_concepts uc
                        WHERE uc.concept_id = c.id
                          AND uc.unit_id LIKE 'UNIT_%'
                    ),
                    ''
                ) AS unit_ids
            FROM concept_curriculum_map m
            JOIN concepts c ON c.id = m.concept_id
            WHERE m.standard='HSK3.0'
              AND m.band='core'
              AND m.level IN ({placeholders})
            GROUP BY m.level, c.id
            ORDER BY m.level, c.id
            """,
            levels,
        ).fetchall()

        unit_stats_rows = conn.execute(
            f"""
            SELECT level, COUNT(*) AS units
            FROM units
            WHERE level IN ({placeholders})
            GROUP BY level
            ORDER BY level
            """,
            levels,
        ).fetchall()
    finally:
        conn.close()

    assets_dir = repo_root / "assets" / "images"
    static_dir = repo_root / "backend" / "static" / "images"

    status_rows: list[dict[str, str]] = []
    missing_rows: list[dict[str, str]] = []

    counts_by_level: dict[str, dict[str, int]] = {
        lvl: {"total": 0, "ok": 0, "tiny": 0, "missing": 0} for lvl in levels
    }

    for r in rows:
        level = (r["level"] or "").strip().upper()
        word_id = (r["word_id"] or "").strip()
        word_zh = (r["word_zh"] or "").strip()
        meaning_en = (r["meaning_en"] or "").strip()
        unit_ids = (r["unit_ids"] or "").strip()

        status, size_bytes, found_path = image_probe(
            word_id,
            args.min_image_bytes,
            (assets_dir, static_dir),
        )

        cat = catalog_index.get(word_id, {})
        image_id = (cat.get("image_id") or "").strip()
        prompt_en = (cat.get("prompt_en") or "").strip()
        recommended_filename = ""
        if image_id and naming_index:
            recommended_filename = (naming_index.get(image_id, {}).get("recommended_filename") or "").strip()

        row = {
            "level": level,
            "word_id": word_id,
            "word_zh": word_zh,
            "meaning_en": meaning_en,
            "unit_ids": unit_ids,
            "image_status": status,
            "runtime_size_bytes": str(size_bytes),
            "runtime_path": found_path,
            "image_id": image_id,
            "recommended_filename": recommended_filename,
            "prompt_en": prompt_en,
        }

        status_rows.append(row)
        counts_by_level[level]["total"] += 1
        counts_by_level[level][status] += 1

        if status in {"missing", "tiny"}:
            missing_rows.append(row)

    fields = [
        "level",
        "word_id",
        "word_zh",
        "meaning_en",
        "unit_ids",
        "image_status",
        "runtime_size_bytes",
        "runtime_path",
        "image_id",
        "recommended_filename",
        "prompt_en",
    ]

    with status_path.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(status_rows)

    with missing_path.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(missing_rows)

    unit_stats = {str(r["level"]): int(r["units"] or 0) for r in unit_stats_rows}

    payload = {
        "ok": True,
        "generated_at": dt.datetime.now(dt.UTC).isoformat(),
        "db": str(db_path),
        "levels": levels,
        "counts_by_level": counts_by_level,
        "unit_counts_by_level": unit_stats,
        "status_csv": str(status_path),
        "missing_csv": str(missing_path),
        "status_rows": len(status_rows),
        "missing_rows": len(missing_rows),
        "min_image_bytes": args.min_image_bytes,
    }

    summary_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(payload, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
