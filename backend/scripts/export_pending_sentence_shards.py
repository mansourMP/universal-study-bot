#!/usr/bin/env python3
"""Export sentence-generation jobs into shard files for multi-agent workflows.

Each job asks workers to create N additional example sentences for a concept.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sqlite3
from pathlib import Path
from typing import Dict, List, Sequence, Tuple


DEFAULT_LEVELS = ["HSK1", "HSK2", "HSK3", "HSK4", "HSK5", "HSK6", "HSK7"]
DEFAULT_DOMAINS = ["casual", "business", "exam", "tech", "social"]


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


def _chunked(values: Sequence[dict], size: int) -> List[List[dict]]:
    if size <= 0:
        return [list(values)]
    return [list(values[i : i + size]) for i in range(0, len(values), size)]


def _primary_gloss(raw: str) -> str:
    text = str(raw or "").replace("；", ";").replace("，", ",").strip()
    if not text:
        return ""
    for delim in (";", ",", "/"):
        if delim in text:
            head = text.split(delim, 1)[0].strip()
            if head:
                return head
    return text


def main() -> int:
    parser = argparse.ArgumentParser(description="Export pending sentence jobs into shards")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--standard", default="HSK3.0")
    parser.add_argument("--levels", default=",".join(DEFAULT_LEVELS))
    parser.add_argument("--target-per-word", type=int, default=2)
    parser.add_argument(
        "--domains",
        default=",".join(DEFAULT_DOMAINS),
        help="Comma-separated target sentence domains.",
    )
    parser.add_argument("--shard-size", type=int, default=200)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--offset", type=int, default=0)
    parser.add_argument("--out-dir", default="docs/sentence_shards_200")
    args = parser.parse_args()

    if args.target_per_word < 1:
        raise SystemExit("--target-per-word must be >= 1")
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
    domains = _split_csv(args.domains, DEFAULT_DOMAINS)

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout=5000")
    try:
        level_clause, level_params = _in_clause(levels)
        sql = f"""
            WITH scoped AS (
              SELECT DISTINCT c.id AS concept_id, c.text, COALESCE(c.pinyin,'') AS pinyin,
                              COALESCE(c.meaning,'') AS meaning, ccm.level
              FROM concept_curriculum_map ccm
              JOIN concepts c ON c.id = ccm.concept_id
              WHERE ccm.standard = ?
                AND ccm.level IN {level_clause}
            ),
            counts AS (
              SELECT s.concept_id, COUNT(ws.sentence_id) AS sentence_count
              FROM scoped s
              LEFT JOIN word_sentences ws ON ws.word_id = s.concept_id
              GROUP BY s.concept_id
            ),
            existing AS (
              SELECT ws.word_id AS concept_id,
                     GROUP_CONCAT(sentences.text, ' || ') AS sample_texts
              FROM word_sentences ws
              JOIN sentences ON sentences.id = ws.sentence_id
              GROUP BY ws.word_id
            )
            SELECT s.concept_id, s.text, s.pinyin, s.meaning, s.level,
                   COALESCE(c.sentence_count,0) AS sentence_count,
                   COALESCE(e.sample_texts,'') AS sample_texts
            FROM scoped s
            LEFT JOIN counts c ON c.concept_id = s.concept_id
            LEFT JOIN existing e ON e.concept_id = s.concept_id
            WHERE COALESCE(c.sentence_count,0) < ?
            ORDER BY s.concept_id
        """
        rows = conn.execute(sql, [args.standard, *level_params, args.target_per_word]).fetchall()

        jobs: List[Dict] = []
        for row in rows:
            have = int(row["sentence_count"])
            need = max(args.target_per_word - have, 0)
            if need <= 0:
                continue
            sample_texts = str(row["sample_texts"] or "")
            samples = [x.strip() for x in sample_texts.split(" || ") if x.strip()][:3]
            jobs.append(
                {
                    "concept_id": str(row["concept_id"]),
                    "hanzi": str(row["text"] or "").strip(),
                    "pinyin": str(row["pinyin"] or "").strip(),
                    "meaning_en": str(row["meaning"] or "").strip(),
                    "meaning_primary_en": _primary_gloss(str(row["meaning"] or "").strip()),
                    "level": str(row["level"] or "").strip(),
                    "existing_sentence_count": have,
                    "need_sentences": need,
                    "target_domains": domains,
                    "existing_samples_zh": samples,
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
            "domains": domains,
            "target_per_word": args.target_per_word,
            "jobs_total": len(jobs),
            "shard_size": args.shard_size,
            "shards_total": len(shards),
            "shards": [],
        }

        for idx, shard in enumerate(shards, start=1):
            shard_name = f"sentence_shard_{idx:04d}.json"
            shard_path = out_dir / shard_name
            payload = {
                "meta": {
                    "shard_index": idx,
                    "shards_total": len(shards),
                    "jobs_in_shard": len(shard),
                    "target_per_word": args.target_per_word,
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
