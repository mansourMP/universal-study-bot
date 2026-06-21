#!/usr/bin/env python3
"""Run DeepSeek translation workers over localization shard files.

This script is the "controller" for parallel agent-style translation:
- Reads shard files from docs/translation_shards_*/
- Calls DeepSeek for each concept job (chunked by languages)
- Writes one result file per shard to docs/translation_results/

Then apply to DB with:
  python3 backend/scripts/apply_localization_results.py \
    --db backend/learning_path.db \
    --input-glob "docs/translation_results/*.json" \
    --apply --source-tag deepseek_agents
"""

from __future__ import annotations

import argparse
import asyncio
import datetime as dt
import json
import os
import random
from pathlib import Path
from typing import Any, Dict, List, Sequence, Tuple
from urllib import error as urlerror
from urllib import request as urlrequest


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


ROOT = _repo_root()
DEEPSEEK_API_KEY = os.getenv("DEEPSEEK_API_KEY", "").strip()
DEEPSEEK_MODEL = os.getenv("DEEPSEEK_MODEL", "deepseek-chat").strip()
DEEPSEEK_BASE_URL = os.getenv("DEEPSEEK_API_BASE", "https://api.deepseek.com/v1").rstrip("/")


def _json_from_text(raw: str) -> Dict[str, Any]:
    text = str(raw or "").strip()
    if not text:
        raise ValueError("Empty response")
    start = text.find("{")
    end = text.rfind("}")
    if start < 0 or end <= start:
        raise ValueError(f"Response is not JSON: {text[:240]}")
    return json.loads(text[start : end + 1])


def _chunked(values: Sequence[str], size: int) -> List[List[str]]:
    if size <= 0:
        return [list(values)]
    return [list(values[i : i + size]) for i in range(0, len(values), size)]


def _http_post_json(url: str, headers: Dict[str, str], payload: Dict[str, Any], timeout: float = 60.0) -> Dict[str, Any]:
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


def _extract_translations(payload: Dict[str, Any], langs: Sequence[str]) -> Dict[str, str]:
    raw = payload.get("translations", payload)
    if not isinstance(raw, dict):
        raise ValueError("Missing translations object")
    out: Dict[str, str] = {}
    for lang in langs:
        value = raw.get(lang)
        if value is None:
            continue
        text = str(value).strip()
        if text:
            out[lang] = text
    return out


def _build_messages(job: Dict[str, Any], langs: Sequence[str]) -> List[Dict[str, str]]:
    concept_id = str(job.get("concept_id", "")).strip()
    hanzi = str(job.get("hanzi", "")).strip()
    pinyin = str(job.get("pinyin", "")).strip()
    anchor = str(job.get("anchor_english", "")).strip() or "(none)"
    lang_text = ", ".join(langs)
    return [
        {
            "role": "system",
            "content": (
                "You are a strict Chinese vocabulary localization engine. "
                "Return only valid JSON. No markdown."
            ),
        },
        {
            "role": "user",
            "content": (
                "Translate ONE Chinese vocabulary concept.\n"
                f"concept_id: {concept_id}\n"
                f"hanzi: {hanzi}\n"
                f"pinyin: {pinyin or '(none)'}\n"
                f"anchor_english: {anchor}\n"
                f"target_language_codes: [{lang_text}]\n\n"
                "Rules:\n"
                "- One primary meaning per language (no multi-meaning lists).\n"
                "- Keep each translation short, neutral, exam-safe.\n"
                "- Return exact JSON format:\n"
                "{ \"translations\": { \"en\": \"...\", \"uz\": \"...\" } }"
            ),
        },
    ]


async def _process_chunk(
    chunk: List[str],
    job: Dict[str, Any],
    max_retries: int,
    temperature: float,
    max_tokens: int,
    semaphore: asyncio.Semaphore,
    chunk_index: int,
) -> Tuple[Dict[str, str], str]:
    for attempt in range(1, max_retries + 1):
        try:
            async with semaphore:
                # LOG START (Only when actually running / inside semaphore)
                if attempt == 1 and chunk_index == 0:
                     cid = job.get("concept_id", "?")
                     hanzi = job.get("hanzi", "?")
                     print(f"🚀 [Item {cid}] Generating EVERYTHING for: {hanzi}", flush=True)

                response_text = await asyncio.to_thread(
                    _chat_completion,
                    _build_messages(job, chunk),
                    temperature,
                    max_tokens,
                )
            payload = _json_from_text(response_text)
            translated = _extract_translations(payload, chunk)
            if not translated:
                raise ValueError("No translations parsed for chunk")
            return translated, ""
        except Exception as exc:
            sleep_s = min(15.0, 1.3**attempt + random.uniform(0.0, 0.8))
            await asyncio.sleep(sleep_s)
    return {}, f"Failed chunk {chunk}: retries exhausted"


async def _translate_job(
    job: Dict[str, Any],
    langs_per_call: int,
    max_retries: int,
    temperature: float,
    max_tokens: int,
    semaphore: asyncio.Semaphore,
) -> Tuple[Dict[str, str], str]:
    # LOG START (Only when actually running)
    cid = job.get("concept_id", "?")
    hanzi = job.get("hanzi", "?")
    # print(f"🚀 [Item {cid}] Generating EVERYTHING for: {hanzi}", flush=True)

    missing_langs = [str(x).lower() for x in (job.get("missing_langs") or []) if str(x).strip()]
    chunks = _chunked(missing_langs, langs_per_call)
    
    tasks = [
        _process_chunk(chunk, job, max_retries, temperature, max_tokens, semaphore, i)
        for i, chunk in enumerate(chunks)
    ]
    results = await asyncio.gather(*tasks)

    all_translations: Dict[str, str] = {}
    errors = []
    
    for trans, err in results:
        if trans:
            all_translations.update(trans)
        if err:
            errors.append(err)

    if not all_translations and errors:
        return {}, "; ".join(errors)
    
    return all_translations, ""


async def _process_shard(
    shard_path: Path,
    out_path: Path,
    langs_per_call: int,
    max_retries: int,
    temperature: float,
    max_tokens: int,
    semaphore: asyncio.Semaphore,
) -> Dict[str, Any]:
    payload = json.loads(shard_path.read_text(encoding="utf-8"))
    jobs = payload.get("jobs") or []
    if not isinstance(jobs, list):
        jobs = []

    # --- SMART RESUME: Load existing partial work ---
    items_map: Dict[str, Any] = {}
    failures_map: Dict[str, Any] = {}
    
    if out_path.exists():
        try:
            existing = json.loads(out_path.read_text(encoding="utf-8"))
            for i in existing.get("items", []):
                items_map[i["concept_id"]] = i
            # We don't load failures, we retry them
        except Exception:
            print(f"[{shard_path.name}] Warn: Corrupt result file, starting fresh.", flush=True)

    # Filter jobs that are already done
    todo_jobs = [j for j in jobs if j.get("concept_id") not in items_map]
    
    if not todo_jobs and jobs:
        print(f"[{shard_path.name}] All {len(jobs)} jobs already done.", flush=True)
        return {
            "items": len(items_map),
            "failures": 0
        }

    print(f"[{shard_path.name}] Processing {len(todo_jobs)}/{len(jobs)} jobs (Streaming)...", flush=True)

    # Process as they complete (Stream)
    completed_count = 0
    
    # RE-IMPLEMENTING TASK LAUNCH TO RETURN CONTEXT
    # We use a helper coroutine
    async def process_wrapper(j):
        res, err = await _translate_job(
            j, langs_per_call, max_retries, temperature, max_tokens, semaphore
        )
        return j, res, err

    wrapped_tasks = [process_wrapper(j) for j in todo_jobs]
    
    for future in asyncio.as_completed(wrapped_tasks):
        job, translations, error = await future
        concept_id = str(job.get("concept_id", "")).strip()
        hanzi = str(job.get("hanzi", "")).strip()
        
        completed_count += 1
        
        if translations:
            print(f"✅ [Item {concept_id}] {hanzi} completed.", flush=True)
            items_map[concept_id] = {"concept_id": concept_id, "translations": translations}
            if concept_id in failures_map:
                del failures_map[concept_id]
        else:
            print(f"❌ [Item {concept_id}] {hanzi} FAILED: {error}", flush=True)
            failures_map[concept_id] = {
                "concept_id": concept_id,
                "hanzi": str(job.get("hanzi", "")).strip(),
                "error": error or "unknown",
            }

        # --- INCREMENTAL SAVE (Every 5 changes) ---
        if completed_count % 5 == 0:
            print(f"💾 [Shard {shard_path.name}] Saving batch (Progress: {len(items_map)}/{len(jobs)})...", flush=True)
            _save_shard(out_path, shard_path, items_map, failures_map)

    # Final Save
    _save_shard(out_path, shard_path, items_map, failures_map)

    return {
        "source_shard": str(shard_path),
        "items": len(items_map),
        "failures": len(failures_map),
    }

def _save_shard(out_path, shard_path, items_map, failures_map):
    out_payload = {
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
    # Atomic write pattern to prevent corruption
    tmp_path = out_path.with_suffix(".tmp")
    tmp_path.write_text(json.dumps(out_payload, ensure_ascii=False, indent=2), encoding="utf-8")
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

    shard_files = sorted(shards_dir.glob("localization_shard_*.json"))
    if not shard_files:
        print(f"No localization_shard_*.json in {shards_dir}")
        return 1

    semaphore = asyncio.Semaphore(args.agents)
    tasks: List[asyncio.Task] = []
    metas: List[Dict[str, Any]] = []

    for shard in shard_files:
        out_file = out_dir / f"{shard.stem}.result.json"
        # We NO LONGER skip if exists, because _process_shard handles partial resume
        # if args.resume and out_file.exists():
        #     continue
        tasks.append(
            asyncio.create_task(
                _process_shard(
                    shard_path=shard,
                    out_path=out_file,
                    langs_per_call=args.langs_per_call,
                    max_retries=args.max_retries,
                    temperature=args.temperature,
                    max_tokens=args.max_tokens,
                    semaphore=semaphore,
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
    parser = argparse.ArgumentParser(description="Run DeepSeek translation agents on shard files")
    parser.add_argument("--shards-dir", default="docs/translation_shards_50")
    parser.add_argument("--out-dir", default="docs/translation_results")
    parser.add_argument("--agents", type=int, default=50)
    parser.add_argument("--langs-per-call", type=int, default=6)
    parser.add_argument("--max-retries", type=int, default=5)
    parser.add_argument("--temperature", type=float, default=0.2)
    parser.add_argument("--max-tokens", type=int, default=420)
    parser.add_argument("--resume", action="store_true")
    args = parser.parse_args()

    if args.agents < 1:
        raise SystemExit("--agents must be >= 1")
    # if args.agents > 200:
    #    raise SystemExit("--agents too high; keep <= 200")
    if args.langs_per_call < 1:
        raise SystemExit("--langs-per-call must be >= 1")
    if args.max_retries < 1:
        raise SystemExit("--max-retries must be >= 1")

    return asyncio.run(_run(args))


if __name__ == "__main__":
    raise SystemExit(main())

