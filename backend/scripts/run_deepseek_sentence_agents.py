#!/usr/bin/env python3
"""Run DeepSeek sentence workers over sentence shard files.

This script generates level-aware sentences from docs/sentence_shards_*/
and writes one result file per shard to docs/sentence_results/.

Then apply with:
  python3 backend/scripts/apply_sentence_results.py \
    --db backend/learning_path.db \
    --input-glob "docs/sentence_results/*.json" \
    --apply --max-per-word 3 --source-tag deepseek_agents_sentences
"""

from __future__ import annotations

import argparse
import asyncio
import datetime as dt
import json
import os
import random
from pathlib import Path
from typing import Any, Dict, List, Tuple
from urllib import error as urlerror
from urllib import request as urlrequest


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


ROOT = _repo_root()
DEEPSEEK_API_KEY = os.getenv("DEEPSEEK_API_KEY", "").strip()
DEEPSEEK_MODEL = os.getenv("DEEPSEEK_MODEL", "deepseek-chat").strip()
DEEPSEEK_BASE_URL = os.getenv("DEEPSEEK_API_BASE", "https://api.deepseek.com/v1").rstrip("/")

_LENGTH_RULES: Dict[str, Tuple[int, int]] = {
    "HSK1": (2, 40),
    "HSK2": (3, 50),
    "HSK3": (4, 70),
    "HSK4": (4, 75),
    "HSK5": (5, 85),
    "HSK6": (5, 90),
    "HSK7": (5, 100),
}
_CHECKPOINT_EVERY = 1


def _http_post_json(url: str, headers: Dict[str, str], payload: Dict[str, Any], timeout: float = 70.0) -> Dict[str, Any]:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urlrequest.Request(url, data=body, headers=headers, method="POST")
    try:
        with urlrequest.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urlerror.HTTPError as exc:
        data = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code}: {data}") from exc
    except urlerror.URLError as exc:
        raise RuntimeError(f"Network error: {exc}") from exc


def _chat_completion(messages: List[Dict[str, str]], temperature: float, max_tokens: int) -> str:
    payload: Dict[str, Any] = {
        "model": DEEPSEEK_MODEL,
        "messages": messages,
        "max_tokens": max_tokens,
    }
    if "reasoner" not in DEEPSEEK_MODEL:
        payload["temperature"] = temperature
    data = _http_post_json(
        url=f"{DEEPSEEK_BASE_URL}/chat/completions",
        headers={
            "Authorization": f"Bearer {DEEPSEEK_API_KEY}",
            "Content-Type": "application/json",
        },
        payload=payload,
    )
    choices = data.get("choices") or []
    if not choices:
        raise RuntimeError(f"No choices returned: {data}")
    text = str(((choices[0] or {}).get("message") or {}).get("content") or "").strip()
    if not text:
        raise RuntimeError(f"Empty content returned: {data}")
    return text


def _json_from_text(raw: str) -> Dict[str, Any]:
    text = str(raw or "").strip()
    if not text:
        raise ValueError("Empty response")
    start = text.find("{")
    end = text.rfind("}")
    if start < 0 or end <= start:
        raise ValueError(f"Response is not JSON: {text[:240]}")
    return json.loads(text[start : end + 1])


def _len_ok(level: str, text_zh: str) -> bool:
    lo, hi = _LENGTH_RULES.get(level, _LENGTH_RULES["HSK7"])
    n = len(str(text_zh or ""))
    return lo <= n <= hi


def _build_messages(job: Dict[str, Any]) -> List[Dict[str, str]]:
    concept_id = str(job.get("concept_id", "")).strip()
    hanzi = str(job.get("hanzi", "")).strip()
    pinyin = str(job.get("pinyin", "")).strip()
    meaning_en = str(job.get("meaning_en", "")).strip()
    meaning_primary_en = str(job.get("meaning_primary_en", "")).strip() or meaning_en
    level = str(job.get("level", "HSK7")).strip()
    need_sentences = int(job.get("need_sentences", 1))
    target_domains = job.get("target_domains") or ["casual", "business", "exam", "tech", "social"]
    if not isinstance(target_domains, list):
        target_domains = ["casual", "business", "exam", "tech", "social"]
    target_domains = [str(x).strip().lower() for x in target_domains if str(x).strip()]
    if not target_domains:
        target_domains = ["casual", "business", "exam", "tech", "social"]
    existing_samples = job.get("existing_samples_zh") or []
    if not isinstance(existing_samples, list):
        existing_samples = []
    existing_text = "\n".join(f"- {str(s)}" for s in existing_samples[:3]) or "(none)"
    lo, hi = _LENGTH_RULES.get(level, _LENGTH_RULES["HSK7"])
    domains_text = ", ".join(target_domains)
    domain_rule = (
        f"Prefer one sentence per domain in this order: {domains_text}. "
        "If need_sentences is smaller, prioritize the earlier domains."
    )

    return [
        {
            "role": "system",
            "content": (
                "You generate Chinese learning sentences in strict JSON only. "
                "No markdown, no prose. "
                "Critical: use only the TARGET SENSE, avoid other meanings for polysemous words. "
                "Keep outputs natural, useful, and level-appropriate."
            ),
        },
        {
            "role": "user",
            "content": (
                f"Generate {need_sentences} new sentences for ONE concept.\n"
                f"concept_id: {concept_id}\n"
                f"hanzi focus: {hanzi}\n"
                f"pinyin focus: {pinyin}\n"
                f"english meaning (raw): {meaning_en}\n"
                f"TARGET SENSE (single meaning): {meaning_primary_en}\n"
                f"level: {level}\n"
                f"zh length range: {lo}..{hi} chars\n"
                f"target domains: {domains_text}\n"
                f"existing sentences (avoid duplicates):\n{existing_text}\n\n"
                "Requirements:\n"
                "- Include the focus word naturally in each sentence.\n"
                "- Stay strictly on TARGET SENSE only; do not use alternate meanings.\n"
                "- Make learner-useful content for adults (not childish).\n"
                "- Mix style context/dialogue and diversify register.\n"
                f"- {domain_rule}\n"
                "- Return exactly JSON:\n"
                "{\n"
                '  "sentences":[\n'
                '    {"style":"context|dialogue","domain":"casual|business|exam|tech|social","tags":"imported|domain_xxx|sense_locked","text_zh":"...","pinyin":"...","translation_en":"..."}\n'
                "  ]\n"
                "}\n"
            ),
        },
    ]


def _extract_sentences(payload: Dict[str, Any], level: str) -> List[Dict[str, str]]:
    rows = payload.get("sentences")
    if not isinstance(rows, list):
        raise ValueError("Missing sentences array")
    out: List[Dict[str, str]] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        style = str(row.get("style", "")).strip().lower() or "context"
        text_zh = str(row.get("text_zh", "")).strip()
        pinyin = str(row.get("pinyin", "")).strip()
        translation_en = str(row.get("translation_en", "")).strip()
        if not text_zh or not pinyin or not translation_en:
            continue
        if not _len_ok(level, text_zh):
            continue
        out.append(
            {
                "style": style,
                "domain": str(row.get("domain", "")).strip().lower(),
                "tags": str(row.get("tags", "")).strip(),
                "text_zh": text_zh,
                "pinyin": pinyin,
                "translation_en": translation_en,
            }
        )
    return out


async def _generate_job(
    job: Dict[str, Any],
    max_retries: int,
    temperature: float,
    max_tokens: int,
    semaphore: asyncio.Semaphore,
) -> Tuple[List[Dict[str, str]], str]:
    level = str(job.get("level", "HSK7")).strip()
    last_error = ""
    for attempt in range(1, max_retries + 1):
        try:
            async with semaphore:
                response_text = await asyncio.to_thread(
                    _chat_completion,
                    _build_messages(job),
                    temperature,
                    max_tokens,
                )
            payload = _json_from_text(response_text)
            sentences = _extract_sentences(payload, level=level)
            if not sentences:
                raise ValueError("No valid sentences parsed")
            return sentences, ""
        except Exception as exc:  # noqa: PERF203
            last_error = str(exc)
            sleep_s = min(15.0, 1.3**attempt + random.uniform(0.0, 0.8))
            await asyncio.sleep(sleep_s)
    return [], last_error or "generation failed"


async def _process_shard(
    shard_path: Path,
    out_path: Path,
    max_retries: int,
    temperature: float,
    max_tokens: int,
    semaphore: asyncio.Semaphore,
    resume: bool,
) -> Dict[str, Any]:
    payload = json.loads(shard_path.read_text(encoding="utf-8"))
    jobs = payload.get("jobs") or []
    if not isinstance(jobs, list):
        jobs = []

    items_map: Dict[str, Dict[str, Any]] = {}
    failures_map: Dict[str, Dict[str, Any]] = {}

    if resume and out_path.exists():
        try:
            existing = json.loads(out_path.read_text(encoding="utf-8"))
            for row in existing.get("items", []):
                cid = str((row or {}).get("concept_id", "")).strip()
                if cid:
                    items_map[cid] = row
            for row in existing.get("failures", []):
                cid = str((row or {}).get("concept_id", "")).strip()
                if cid:
                    failures_map[cid] = row
        except Exception:
            print(f"[{shard_path.name}] Warning: could not read existing result file; starting fresh.", flush=True)

    total_jobs = len(jobs)
    todo_jobs: List[Dict[str, Any]] = []
    for job in jobs:
        if not isinstance(job, dict):
            continue
        concept_id = str(job.get("concept_id", "")).strip()
        if not concept_id:
            continue
        if concept_id in items_map:
            continue
        todo_jobs.append(job)

    print(
        f"[{shard_path.name}] Starting processing {len(todo_jobs)}/{total_jobs} jobs...",
        flush=True,
    )
    # Persist initial state immediately so resume/monitoring has visible progress files.
    _save_shard(out_path, shard_path, items_map, failures_map)

    completed = 0
    for job in todo_jobs:
        concept_id = str(job.get("concept_id", "")).strip()
        if not concept_id:
            continue

        if completed % _CHECKPOINT_EVERY == 0:
            print(
                f"[{shard_path.name}] Progress: {completed}/{len(todo_jobs)} jobs...",
                flush=True,
            )

        sentences, error = await _generate_job(
            job=job,
            max_retries=max_retries,
            temperature=temperature,
            max_tokens=max_tokens,
            semaphore=semaphore,
        )
        if sentences:
            need = int(job.get("need_sentences", 1))
            items_map[concept_id] = {
                "concept_id": concept_id,
                "sentences": sentences[: max(1, need)],
            }
            if concept_id in failures_map:
                del failures_map[concept_id]
        else:
            failures_map[concept_id] = {
                "concept_id": concept_id,
                "hanzi": str(job.get("hanzi", "")).strip(),
                "error": error or "unknown",
            }

        completed += 1
        if completed % _CHECKPOINT_EVERY == 0:
            _save_shard(out_path, shard_path, items_map, failures_map)

    _save_shard(out_path, shard_path, items_map, failures_map)
    return {
        "source_shard": str(shard_path),
        "items": len(items_map),
        "failures": len(failures_map),
    }


def _save_shard(
    out_path: Path,
    shard_path: Path,
    items_map: Dict[str, Dict[str, Any]],
    failures_map: Dict[str, Dict[str, Any]],
) -> None:
    payload = {
        "meta": {
            "source_shard": str(shard_path),
            "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
            "items": len(items_map),
            "failures": len(failures_map),
            "model": DEEPSEEK_MODEL,
        },
        "items": list(items_map.values()),
        "failures": list(failures_map.values()),
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = out_path.with_suffix(".tmp")
    tmp_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp_path.replace(out_path)


async def _run(args: argparse.Namespace) -> int:
    if not DEEPSEEK_API_KEY:
        print("DEEPSEEK_API_KEY is missing")
        return 1

    shards_dir = ROOT / args.shards_dir if not Path(args.shards_dir).is_absolute() else Path(args.shards_dir)
    out_dir = ROOT / args.out_dir if not Path(args.out_dir).is_absolute() else Path(args.out_dir)
    if not shards_dir.exists():
        print(f"Shards dir not found: {shards_dir}")
        return 1
    out_dir.mkdir(parents=True, exist_ok=True)

    shard_files = sorted(shards_dir.glob("sentence_shard_*.json"))
    if not shard_files:
        print(f"No sentence_shard_*.json in {shards_dir}")
        return 1

    semaphore = asyncio.Semaphore(args.agents)
    tasks: List[asyncio.Task] = []
    metas: List[Dict[str, Any]] = []

    for shard in shard_files:
        out_file = out_dir / f"{shard.stem}.result.json"
        tasks.append(
            asyncio.create_task(
                _process_shard(
                    shard_path=shard,
                    out_path=out_file,
                    max_retries=args.max_retries,
                    temperature=args.temperature,
                    max_tokens=args.max_tokens,
                    semaphore=semaphore,
                    resume=args.resume,
                )
            )
        )

    if not tasks:
        print("Nothing to do (all shard results already exist).")
        return 0

    for idx, task in enumerate(asyncio.as_completed(tasks), start=1):
        meta = await task
        metas.append(meta)
        print(
            f"[{idx}/{len(tasks)}] shard done: items={meta['items']} failures={meta['failures']}"
        )

    summary = {
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "shards_processed": len(metas),
        "items_total": sum(int(m["items"]) for m in metas),
        "failures_total": sum(int(m["failures"]) for m in metas),
        "out_dir": str(out_dir),
        "model": DEEPSEEK_MODEL,
    }
    summary_path = out_dir / f"summary_{dt.date.today().isoformat()}.json"
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False))
    print(f"Summary: {summary_path}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Run DeepSeek sentence agents on shard files")
    parser.add_argument("--shards-dir", default="docs/sentence_shards_50")
    parser.add_argument("--out-dir", default="docs/sentence_results")
    parser.add_argument("--agents", type=int, default=50)
    parser.add_argument("--max-retries", type=int, default=5)
    parser.add_argument("--temperature", type=float, default=0.3)
    parser.add_argument("--max-tokens", type=int, default=520)
    parser.add_argument("--resume", action="store_true")
    args = parser.parse_args()

    if args.agents < 1:
        raise SystemExit("--agents must be >= 1")
    # if args.agents > 200:
    #    raise SystemExit("--agents too high; keep <= 200")
    if args.max_retries < 1:
        raise SystemExit("--max-retries must be >= 1")

    return asyncio.run(_run(args))


if __name__ == "__main__":
    raise SystemExit(main())
