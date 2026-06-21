#!/usr/bin/env python3
"""Export HSK1 gap-only sentence/exercise shard jobs from generation plan.

Reads:
- docs/reports/hsk1_circle_generation_plan_*.json
- docs/specs/hsk1_circle_template_v1.json

Writes:
- docs/hsk1_sentence_gap_shards_200/sentence_shard_*.json
- docs/hsk1_exercise_gap_shards_200/exercise_shard_*.json
- docs/reports/hsk1_gap_export_YYYY-MM-DD.json
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sqlite3
from pathlib import Path
from typing import Any, Dict, List, Sequence, Tuple


DEFAULT_SENTENCE_TYPES = [
    "neutral_general",
    "spoken_daily",
    "exam_style",
    "business",
    "travel",
]
DEFAULT_EXERCISE_TYPES = [
    "meaning_select",
    "audio_select",
    "character_select",
    "order_sentence",
    "reading_micro",
]


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _read_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _chunked(values: Sequence[dict], size: int) -> List[List[dict]]:
    if size <= 0:
        return [list(values)]
    return [list(values[i : i + size]) for i in range(0, len(values), size)]


def _latest_plan_path(root: Path) -> Path | None:
    candidates = sorted((root / "docs" / "reports").glob("hsk1_circle_generation_plan_*.json"))
    return candidates[-1] if candidates else None


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


def _load_existing_sentence_samples(
    conn: sqlite3.Connection,
    word_ids: List[str],
    limit_per_word: int = 3,
) -> Dict[str, List[str]]:
    if not word_ids:
        return {}
    placeholders = ",".join("?" for _ in word_ids)
    rows = conn.execute(
        f"""
        SELECT ws.word_id, s.text
        FROM word_sentences ws
        JOIN sentences s ON s.id = ws.sentence_id
        WHERE ws.word_id IN ({placeholders})
          AND TRIM(COALESCE(s.text,'')) != ''
        ORDER BY ws.word_id ASC, ws.is_primary DESC, ws.sentence_id ASC
        """,
        tuple(word_ids),
    ).fetchall()
    out: Dict[str, List[str]] = {}
    for row in rows:
        wid = str(row[0])
        text = str(row[1] or "").strip()
        if not text:
            continue
        bucket = out.setdefault(wid, [])
        if text in bucket:
            continue
        if len(bucket) < limit_per_word:
            bucket.append(text)
    return out


def _build_snapshot_map(plan: Dict[str, Any]) -> Dict[str, Dict[str, Any]]:
    snap: Dict[str, Dict[str, Any]] = {}
    for unit in plan.get("units", []):
        for row in unit.get("words_snapshot", []):
            wid = str(row.get("word_id") or "")
            if wid and wid not in snap:
                snap[wid] = row
    return snap


def _choose_sentence_domains(
    need: int,
    required_dist: Dict[str, int],
    optional_plus: Dict[str, int],
    fallback_domains: List[str],
) -> List[str]:
    ordered_required: List[str] = []
    for domain, count in required_dist.items():
        for _ in range(max(0, int(count))):
            ordered_required.append(str(domain))
    ordered_optional: List[str] = []
    for domain, count in optional_plus.items():
        for _ in range(max(0, int(count))):
            ordered_optional.append(str(domain))

    sequence: List[str] = []
    for domain in ordered_required:
        if len(sequence) >= need:
            break
        sequence.append(domain)
    for domain in ordered_optional:
        if len(sequence) >= need:
            break
        sequence.append(domain)
    idx = 0
    while len(sequence) < need:
        if fallback_domains:
            sequence.append(fallback_domains[idx % len(fallback_domains)])
        else:
            sequence.append("neutral_general")
        idx += 1
    return sequence


def _suggest_missing_exercise_types(
    existing_types: List[str],
    need_count: int,
    preferred_order: List[str],
) -> List[str]:
    existing = set(existing_types)
    picked: List[str] = []
    for ex_type in preferred_order:
        if len(picked) >= need_count:
            break
        if ex_type not in existing and ex_type not in picked:
            picked.append(ex_type)
    idx = 0
    while len(picked) < need_count and preferred_order:
        picked.append(preferred_order[idx % len(preferred_order)])
        idx += 1
    return picked


def main() -> int:
    parser = argparse.ArgumentParser(description="Export HSK1 gap-only sentence/exercise shards")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--template", default="docs/specs/hsk1_circle_template_v1.json")
    parser.add_argument("--plan", default="", help="Optional explicit plan JSON path")
    parser.add_argument("--sentence-shard-size", type=int, default=200)
    parser.add_argument("--exercise-shard-size", type=int, default=200)
    parser.add_argument("--sentence-out-dir", default="docs/hsk1_sentence_gap_shards_200")
    parser.add_argument("--exercise-out-dir", default="docs/hsk1_exercise_gap_shards_200")
    parser.add_argument("--sentence-domains", default=",".join(DEFAULT_SENTENCE_TYPES))
    parser.add_argument("--exercise-types", default=",".join(DEFAULT_EXERCISE_TYPES))
    args = parser.parse_args()

    if args.sentence_shard_size < 1 or args.exercise_shard_size < 1:
        raise SystemExit("Shard sizes must be >= 1")

    root = _repo_root()
    db_path = root / args.db if not Path(args.db).is_absolute() else Path(args.db)
    template_path = root / args.template if not Path(args.template).is_absolute() else Path(args.template)
    if args.plan:
        plan_path = root / args.plan if not Path(args.plan).is_absolute() else Path(args.plan)
    else:
        found = _latest_plan_path(root)
        if not found:
            print("No hsk1_circle_generation_plan_*.json found in docs/reports")
            return 1
        plan_path = found

    sentence_out = root / args.sentence_out_dir if not Path(args.sentence_out_dir).is_absolute() else Path(args.sentence_out_dir)
    exercise_out = root / args.exercise_out_dir if not Path(args.exercise_out_dir).is_absolute() else Path(args.exercise_out_dir)
    sentence_out.mkdir(parents=True, exist_ok=True)
    exercise_out.mkdir(parents=True, exist_ok=True)

    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1
    if not template_path.exists():
        print(f"Template not found: {template_path}")
        return 1
    if not plan_path.exists():
        print(f"Plan not found: {plan_path}")
        return 1

    template = _read_json(template_path)
    plan = _read_json(plan_path)
    snapshot_map = _build_snapshot_map(plan)
    todo_rows = plan.get("todo", [])

    preferred_domains = _split_csv(args.sentence_domains, DEFAULT_SENTENCE_TYPES)
    preferred_ex_types = _split_csv(args.exercise_types, DEFAULT_EXERCISE_TYPES)

    dist = template.get("content_quota_per_sense", {}).get("distribution", {}) or {}
    optional_plus = template.get("content_quota_per_sense", {}).get("optional_plus", {}) or {}

    all_word_ids = sorted({str(r.get("word_id") or "") for r in todo_rows if str(r.get("word_id") or "")})
    conn = sqlite3.connect(str(db_path), timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout = 30000")
    try:
        samples = _load_existing_sentence_samples(conn, all_word_ids, limit_per_word=3)
    finally:
        conn.close()

    sentence_jobs: List[Dict[str, Any]] = []
    exercise_jobs: List[Dict[str, Any]] = []

    for row in todo_rows:
        wid = str(row.get("word_id") or "")
        if not wid:
            continue
        snap = snapshot_map.get(wid, {})
        text = str(snap.get("text") or row.get("text") or "").strip()
        pinyin = str(snap.get("pinyin") or "").strip()
        meaning = str(snap.get("meaning") or "").strip()
        sense_id = str(row.get("sense_id") or snap.get("sense_id") or f"{wid}::s01")
        unit_id = str(row.get("unit_id") or "")
        need_sentences = int(row.get("needs_sentences") or 0)
        need_ex_types = int(row.get("needs_exercise_types") or 0)

        if need_sentences > 0:
            target_domains = _choose_sentence_domains(
                need=need_sentences,
                required_dist=dist,
                optional_plus=optional_plus,
                fallback_domains=preferred_domains,
            )
            sentence_jobs.append(
                {
                    "concept_id": wid,
                    "sense_id": sense_id,
                    "unit_id": unit_id,
                    "level": "HSK1",
                    "hanzi": text,
                    "pinyin": pinyin,
                    "meaning_en": meaning,
                    "need_sentences": need_sentences,
                    "target_domains": target_domains,
                    "existing_samples_zh": samples.get(wid, []),
                }
            )

        if need_ex_types > 0:
            existing_types = list(snap.get("exercise_types", []))
            suggested_types = _suggest_missing_exercise_types(
                existing_types=existing_types,
                need_count=need_ex_types,
                preferred_order=preferred_ex_types,
            )
            exercise_jobs.append(
                {
                    "concept_id": wid,
                    "sense_id": sense_id,
                    "unit_id": unit_id,
                    "level": "HSK1",
                    "hanzi": text,
                    "pinyin": pinyin,
                    "meaning_en": meaning,
                    "current_exercise_types": existing_types,
                    "need_exercise_types": need_ex_types,
                    "suggested_new_types": suggested_types,
                }
            )

    sent_shards = _chunked(sentence_jobs, args.sentence_shard_size)
    ex_shards = _chunked(exercise_jobs, args.exercise_shard_size)
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    sent_manifest = {
        "generated_at": stamp,
        "plan": str(plan_path),
        "template": str(template_path),
        "jobs_total": len(sentence_jobs),
        "shard_size": args.sentence_shard_size,
        "shards_total": len(sent_shards),
        "shards": [],
    }
    for idx, shard in enumerate(sent_shards, start=1):
        file_name = f"sentence_shard_{idx:04d}.json"
        path = sentence_out / file_name
        payload = {
            "meta": {
                "shard_index": idx,
                "shards_total": len(sent_shards),
                "jobs_in_shard": len(shard),
                "mode": "hsk1_gap_sentences",
            },
            "jobs": shard,
        }
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        sent_manifest["shards"].append({"shard_index": idx, "file": str(path), "jobs": len(shard)})

    ex_manifest = {
        "generated_at": stamp,
        "plan": str(plan_path),
        "template": str(template_path),
        "jobs_total": len(exercise_jobs),
        "shard_size": args.exercise_shard_size,
        "shards_total": len(ex_shards),
        "shards": [],
    }
    for idx, shard in enumerate(ex_shards, start=1):
        file_name = f"exercise_shard_{idx:04d}.json"
        path = exercise_out / file_name
        payload = {
            "meta": {
                "shard_index": idx,
                "shards_total": len(ex_shards),
                "jobs_in_shard": len(shard),
                "mode": "hsk1_gap_exercises",
            },
            "jobs": shard,
        }
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        ex_manifest["shards"].append({"shard_index": idx, "file": str(path), "jobs": len(shard)})

    sent_manifest_path = sentence_out / f"manifest_{stamp}.json"
    ex_manifest_path = exercise_out / f"manifest_{stamp}.json"
    sent_manifest_path.write_text(json.dumps(sent_manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    ex_manifest_path.write_text(json.dumps(ex_manifest, ensure_ascii=False, indent=2), encoding="utf-8")

    report = {
        "generated_at": stamp,
        "db": str(db_path),
        "plan": str(plan_path),
        "template": str(template_path),
        "sentence_jobs_total": len(sentence_jobs),
        "sentence_shards_total": len(sent_shards),
        "sentence_manifest": str(sent_manifest_path),
        "exercise_jobs_total": len(exercise_jobs),
        "exercise_shards_total": len(ex_shards),
        "exercise_manifest": str(ex_manifest_path),
    }
    report_path = root / "docs" / "reports" / f"hsk1_gap_export_{dt.date.today().isoformat()}.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    print(json.dumps({"ok": True, **report}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
