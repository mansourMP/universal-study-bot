#!/usr/bin/env python3
"""Export missing context-translation jobs into shard files.

Target workflow:
1) Export jobs:
   python3 backend/scripts/export_missing_context_shards.py \
     --db backend/learning_path.db \
     --pack backend/content/packs/zh_hsk7_vocab.json \
     --out-dir docs/context_shards_50 \
     --shard-size 200

2) Run workers:
   python3 backend/scripts/run_deepseek_context_agents.py \
     --shards-dir docs/context_shards_50 \
     --out-dir docs/context_results \
     --agents 50 --langs-per-call 4 --max-retries 6 --resume

3) Apply results:
   python3 backend/scripts/apply_context_results.py \
     --db backend/learning_path.db \
     --pack backend/content/packs/zh_hsk7_vocab.json \
     --input-glob "docs/context_results/*.result.json" \
     --apply --source-tag deepseek_context_batch
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sqlite3
from pathlib import Path
from typing import Dict, List, Sequence, Tuple


CANON_LANGS = [
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
    values = [v.strip().lower() for v in str(raw or "").split(",") if v.strip()]
    if not values:
        values = list(fallback)
    dedup: List[str] = []
    seen = set()
    for value in values:
        if value in seen:
            continue
        seen.add(value)
        dedup.append(value)
    return dedup


def _chunk(values: Sequence[Dict], size: int) -> List[List[Dict]]:
    if size <= 0:
        return [list(values)]
    return [list(values[i : i + size]) for i in range(0, len(values), size)]


def _norm_pinyin(value: str | None) -> str:
    if not value:
        return ""
    return re.sub(r"\s+", " ", str(value)).strip().lower()


def _resolve_concept_id(conn: sqlite3.Connection, hanzi: str, pinyin: str) -> str | None:
    rows = conn.execute(
        "SELECT id, pinyin FROM concepts WHERE text = ? ORDER BY id",
        (hanzi,),
    ).fetchall()
    if not rows:
        return None
    if len(rows) == 1:
        return str(rows[0][0])

    want = _norm_pinyin(pinyin)
    if want:
        by_pinyin = [row for row in rows if _norm_pinyin(row[1]) == want]
        if len(by_pinyin) == 1:
            return str(by_pinyin[0][0])

    # Deterministic fallback.
    return str(rows[0][0])


def _fetch_existing_context_langs(
    conn: sqlite3.Connection, concept_id: str, target_langs: Sequence[str]
) -> set[str]:
    if not target_langs:
        return set()
    placeholder = ",".join("?" for _ in target_langs)
    rows = conn.execute(
        f"""
        SELECT LOWER(language_code)
        FROM concept_localizations
        WHERE concept_id = ?
          AND LOWER(language_code) IN ({placeholder})
          AND TRIM(COALESCE(context_translation, '')) != ''
        """,
        [concept_id, *target_langs],
    ).fetchall()
    return {str(row[0]).lower() for row in rows}


def main() -> int:
    parser = argparse.ArgumentParser(description="Export missing context-translation shard jobs")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--pack", default="backend/content/packs/zh_hsk7_vocab.json")
    parser.add_argument("--out-dir", default="docs/context_shards_50")
    parser.add_argument("--report-dir", default="docs/reports")
    parser.add_argument("--shard-size", type=int, default=200)
    parser.add_argument(
        "--langs",
        default="uz,es,fr,ru,ar,pt,de,it,ja,ko,hi,ur,bn,tr,pl,nl,fa,id,vi,th,ms,tl,sw,uk,ro,cs,hu,sv,da,no,el,he,pa,ta",
        help="Target language codes to fill for context translations (CSV).",
    )
    parser.add_argument(
        "--include-en-zh",
        action="store_true",
        help="Also include en/zh in target context translation jobs.",
    )
    args = parser.parse_args()

    root = _repo_root()
    db_path = root / args.db
    pack_path = root / args.pack if not Path(args.pack).is_absolute() else Path(args.pack)
    out_dir = root / args.out_dir if not Path(args.out_dir).is_absolute() else Path(args.out_dir)
    report_dir = root / args.report_dir if not Path(args.report_dir).is_absolute() else Path(args.report_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    report_dir.mkdir(parents=True, exist_ok=True)

    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1
    if not pack_path.exists():
        print(f"Pack not found: {pack_path}")
        return 1

    target_langs = _split_csv(args.langs, [])
    if args.include_en_zh:
        for code in ("en", "zh"):
            if code not in target_langs:
                target_langs.append(code)
    target_langs = [code for code in target_langs if code in CANON_LANGS]

    data = json.loads(pack_path.read_text(encoding="utf-8"))
    rows = data.get("vocabulary", [])
    if not isinstance(rows, list):
        print("Invalid pack format: `vocabulary` must be a list.")
        return 1

    conn = sqlite3.connect(str(db_path))
    jobs: List[Dict] = []
    unresolved = 0
    no_context_sentence = 0
    seen_concepts: set[str] = set()

    try:
        for idx, row in enumerate(rows):
            if not isinstance(row, dict):
                continue
            hanzi = str(row.get("hanzi") or "").strip()
            pinyin = str(row.get("pinyin") or "").strip()
            context_zh = str(row.get("context_sentence") or "").strip()
            if not hanzi:
                continue
            if not context_zh:
                no_context_sentence += 1
                continue

            concept_id = _resolve_concept_id(conn, hanzi, pinyin)
            if not concept_id:
                unresolved += 1
                continue
            if concept_id in seen_concepts:
                continue
            seen_concepts.add(concept_id)

            existing = _fetch_existing_context_langs(conn, concept_id, target_langs)
            missing = [lang for lang in target_langs if lang not in existing]
            if not missing:
                continue

            context_map = row.get("context_translation")
            if not isinstance(context_map, dict):
                context_map = {}
            context_en = str(context_map.get("en") or "").strip()

            jobs.append(
                {
                    "concept_id": concept_id,
                    "row_index": idx,
                    "hanzi": hanzi,
                    "pinyin": pinyin,
                    "context_zh": context_zh,
                    "context_en": context_en,
                    "missing_langs": missing,
                }
            )
    finally:
        conn.close()

    shards = _chunk(jobs, args.shard_size)
    for i, shard_jobs in enumerate(shards, start=1):
        out_path = out_dir / f"context_shard_{i:04d}.json"
        payload = {
            "meta": {
                "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
                "source_pack": str(pack_path),
                "target_langs": target_langs,
                "jobs": len(shard_jobs),
                "shard_index": i,
                "total_shards": len(shards),
            },
            "jobs": shard_jobs,
        }
        out_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    manifest_path = out_dir / f"manifest_{stamp}.json"
    manifest = {
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "db": str(db_path),
        "pack": str(pack_path),
        "target_langs": target_langs,
        "jobs_total": len(jobs),
        "shards_total": len(shards),
        "shard_size": args.shard_size,
        "unresolved_concepts": unresolved,
        "rows_without_context_sentence": no_context_sentence,
        "output_dir": str(out_dir),
    }
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

    report_path = report_dir / f"context_shard_export_{dt.date.today().isoformat()}.json"
    report_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

    print(json.dumps(manifest, ensure_ascii=False))
    print(f"Manifest: {manifest_path}")
    print(f"Report: {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
