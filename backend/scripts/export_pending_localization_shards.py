#!/usr/bin/env python3
"""Export pending localization jobs into shard files for multi-agent generation.

This script is designed for external worker orchestration (Gemini CLI, etc.):
- Reads pending concepts from DB for target standard/levels.
- Computes missing languages per concept.
- Writes JSON shard files (e.g., 100 concepts each).

Workers can process shards independently and output translation result files.
Use `apply_localization_results.py` to merge worker outputs safely.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sqlite3
from pathlib import Path
from typing import Dict, List, Sequence, Tuple


DEFAULT_LEVELS = ["HSK1", "HSK2", "HSK3", "HSK4", "HSK5", "HSK6", "HSK7"]
DEFAULT_TARGET_LANGS = [
    "en",
    "uz",
    "es",
    "fr",
    "ru",
    "ar",
    "pt",
    "de",
    "it",
    "ja",
    "ko",
    "hi",
    "ur",
    "bn",
    "tr",
    "pl",
    "nl",
    "fa",
    "id",
    "vi",
    "th",
    "ms",
    "tl",
    "sw",
    "uk",
    "ro",
    "cs",
    "hu",
    "sv",
    "da",
    "no",
    "el",
    "he",
    "pa",
    "ta",
    "zh",
]


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _split_csv(raw: str, fallback: Sequence[str]) -> List[str]:
    values = [v.strip() for v in str(raw or "").split(",") if v.strip()]
    if not values:
        return list(fallback)
    out: List[str] = []
    seen = set()
    for value in values:
        key = value.lower()
        if key in seen:
            continue
        seen.add(key)
        out.append(value)
    return out


def _in_clause(values: Sequence[str]) -> Tuple[str, List[str]]:
    placeholders = ",".join("?" for _ in values)
    return f"({placeholders})", list(values)


def _fetch_scope_concepts(
    conn: sqlite3.Connection,
    standard: str,
    levels: Sequence[str],
) -> List[sqlite3.Row]:
    level_clause, level_params = _in_clause(levels)
    sql = f"""
        SELECT DISTINCT
            c.id AS concept_id,
            c.text AS hanzi,
            COALESCE(c.pinyin, '') AS pinyin,
            COALESCE(c.meaning, '') AS current_meaning,
            COALESCE((
                SELECT cs.gloss
                FROM concept_senses cs
                WHERE cs.concept_id = c.id
                ORDER BY cs.is_primary DESC, cs.ordinal ASC, cs.sense_id ASC
                LIMIT 1
            ), '') AS current_primary_gloss,
            ccm.level AS level
        FROM concept_curriculum_map ccm
        JOIN concepts c ON c.id = ccm.concept_id
        WHERE ccm.standard = ?
          AND ccm.level IN {level_clause}
        ORDER BY c.id ASC
    """
    return conn.execute(sql, [standard, *level_params]).fetchall()


def _fetch_existing_localizations(
    conn: sqlite3.Connection,
    standard: str,
    levels: Sequence[str],
    target_langs: Sequence[str],
) -> Dict[str, Dict[str, str]]:
    level_clause, level_params = _in_clause(levels)
    lang_clause, lang_params = _in_clause([lang.lower() for lang in target_langs])
    sql = f"""
        SELECT DISTINCT
            cl.concept_id,
            LOWER(cl.language_code) AS language_code,
            COALESCE(cl.meaning, '') AS meaning
        FROM concept_localizations cl
        JOIN concept_curriculum_map ccm ON ccm.concept_id = cl.concept_id
        WHERE ccm.standard = ?
          AND ccm.level IN {level_clause}
          AND LOWER(cl.language_code) IN {lang_clause}
          AND TRIM(COALESCE(cl.meaning, '')) <> ''
    """
    rows = conn.execute(sql, [standard, *level_params, *lang_params]).fetchall()
    out: Dict[str, Dict[str, str]] = {}
    for row in rows:
        concept_id = str(row["concept_id"])
        lang = str(row["language_code"]).lower()
        meaning = str(row["meaning"] or "").strip()
        if not meaning:
            continue
        out.setdefault(concept_id, {})[lang] = meaning
    return out


def _chunked(values: Sequence[dict], size: int) -> List[List[dict]]:
    if size <= 0:
        return [list(values)]
    return [list(values[i : i + size]) for i in range(0, len(values), size)]


def main() -> int:
    parser = argparse.ArgumentParser(description="Export pending localization jobs into shards")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--standard", default="HSK3.0")
    parser.add_argument("--levels", default=",".join(DEFAULT_LEVELS))
    parser.add_argument("--target-langs", default=",".join(DEFAULT_TARGET_LANGS))
    parser.add_argument("--shard-size", type=int, default=100)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--offset", type=int, default=0)
    parser.add_argument("--out-dir", default="docs/translation_shards")
    parser.add_argument(
        "--force-refresh",
        action="store_true",
        help="Export jobs for all target languages even if existing localizations are present.",
    )
    parser.add_argument(
        "--anchor-mode",
        choices=["existing", "empty"],
        default="existing",
        help="How to populate anchor_english for workers.",
    )
    args = parser.parse_args()

    if args.shard_size < 1:
        raise SystemExit("--shard-size must be >= 1")

    root = _repo_root()
    db_path = root / args.db if not Path(args.db).is_absolute() else Path(args.db)
    out_dir = root / args.out_dir if not Path(args.out_dir).is_absolute() else Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1

    levels = _split_csv(args.levels, DEFAULT_LEVELS)
    target_langs = [x.lower() for x in _split_csv(args.target_langs, DEFAULT_TARGET_LANGS)]

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout=5000")
    try:
        concepts = _fetch_scope_concepts(conn, args.standard, levels)
        existing = _fetch_existing_localizations(conn, args.standard, levels, target_langs)

        jobs: List[dict] = []
        for row in concepts:
            concept_id = str(row["concept_id"])
            hanzi = str(row["hanzi"] or "").strip()
            if not hanzi:
                continue
            pinyin = str(row["pinyin"] or "").strip()
            level = str(row["level"] or "").strip()
            current_meaning = str(row["current_meaning"] or "").strip()
            current_primary_gloss = str(row["current_primary_gloss"] or "").strip()

            existing_langs = existing.get(concept_id, {})
            if args.force_refresh:
                missing = list(target_langs)
            else:
                missing = [lang for lang in target_langs if not existing_langs.get(lang, "").strip()]
            if not missing:
                continue

            if args.anchor_mode == "empty":
                anchor_english = ""
            else:
                anchor_english = (
                    existing_langs.get("en")
                    or current_primary_gloss
                    or current_meaning
                )

            jobs.append(
                {
                    "concept_id": concept_id,
                    "hanzi": hanzi,
                    "pinyin": pinyin,
                    "level": level,
                    "anchor_english": anchor_english,
                    "missing_langs": missing,
                    "existing_langs": sorted(existing_langs.keys()),
                }
            )

        if args.offset > 0:
            jobs = jobs[args.offset :]
        if args.limit > 0:
            jobs = jobs[: args.limit]

        shards = _chunked(jobs, args.shard_size)
        stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")

        manifest = {
            "generated_at": stamp,
            "db": str(db_path),
            "standard": args.standard,
            "levels": levels,
            "target_langs": target_langs,
            "jobs_total": len(jobs),
            "shard_size": args.shard_size,
            "shards_total": len(shards),
            "force_refresh": bool(args.force_refresh),
            "anchor_mode": args.anchor_mode,
            "shards": [],
        }

        for idx, shard in enumerate(shards, start=1):
            shard_name = f"localization_shard_{idx:04d}.json"
            shard_path = out_dir / shard_name
            payload = {
                "meta": {
                    "shard_index": idx,
                    "shards_total": len(shards),
                    "jobs_in_shard": len(shard),
                    "target_langs": target_langs,
                },
                "jobs": shard,
            }
            shard_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
            manifest["shards"].append(
                {
                    "shard_index": idx,
                    "file": str(shard_path),
                    "jobs": len(shard),
                }
            )

        manifest_path = out_dir / f"manifest_{stamp}.json"
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

        print(f"Jobs: {len(jobs)}")
        print(f"Shards: {len(shards)}")
        print(f"Manifest: {manifest_path}")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
