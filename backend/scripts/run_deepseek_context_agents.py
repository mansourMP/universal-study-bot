#!/usr/bin/env python3
"""Run provider workers to translate missing context sentences.

Input:
- docs/context_shards_*/context_shard_*.json

Output:
- docs/context_results/context_shard_*.result.json
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
GEMINI_API_KEY = os.getenv("GOOGLE_API_KEY", "").strip()
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-1.5-flash").strip()
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "").strip()
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4.1-mini").strip()
OPENAI_BASE_URL = os.getenv("OPENAI_API_BASE", "https://api.openai.com/v1").rstrip("/")
_CHECKPOINT_EVERY = 1


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


def _chat_completion_deepseek(messages: List[Dict[str, str]], temperature: float, max_tokens: int) -> str:
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


def _chat_completion_openai(messages: List[Dict[str, str]], temperature: float, max_tokens: int) -> str:
    payload: Dict[str, Any] = {
        "model": OPENAI_MODEL,
        "messages": messages,
        "max_tokens": max_tokens,
    }
    if "reasoner" not in OPENAI_MODEL:
        payload["temperature"] = temperature
    data = _http_post_json(
        url=f"{OPENAI_BASE_URL}/chat/completions",
        headers={
            "Authorization": f"Bearer {OPENAI_API_KEY}",
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


def _chat_completion_gemini(messages: List[Dict[str, str]], temperature: float, max_tokens: int) -> str:
    system_parts: List[str] = []
    contents: List[Dict[str, Any]] = []
    for msg in messages:
        role = str(msg.get("role", "user")).strip().lower()
        content = str(msg.get("content", "")).strip()
        if not content:
            continue
        if role == "system":
            system_parts.append(content)
            continue
        contents.append(
            {
                "role": "model" if role == "assistant" else "user",
                "parts": [{"text": content}],
            }
        )
    if not contents:
        contents = [{"role": "user", "parts": [{"text": "Translate."}]}]
    payload: Dict[str, Any] = {
        "contents": contents,
        "generationConfig": {
            "temperature": temperature,
            "maxOutputTokens": max_tokens,
        },
    }
    if system_parts:
        payload["systemInstruction"] = {"parts": [{"text": "\n\n".join(system_parts)}]}
    data = _http_post_json(
        url=(
            "https://generativelanguage.googleapis.com/v1beta/models/"
            f"{GEMINI_MODEL}:generateContent?key={GEMINI_API_KEY}"
        ),
        headers={"Content-Type": "application/json"},
        payload=payload,
    )
    candidates = data.get("candidates") or []
    if not candidates:
        raise RuntimeError(f"No candidates returned: {data}")
    parts = ((candidates[0] or {}).get("content") or {}).get("parts") or []
    text = "\n".join(str(p.get("text") or "") for p in parts).strip()
    if not text:
        raise RuntimeError(f"Empty content returned: {data}")
    return text


def _chat_completion(provider: str, messages: List[Dict[str, str]], temperature: float, max_tokens: int) -> str:
    if provider == "deepseek":
        return _chat_completion_deepseek(messages, temperature, max_tokens)
    if provider == "openai":
        return _chat_completion_openai(messages, temperature, max_tokens)
    if provider == "gemini":
        return _chat_completion_gemini(messages, temperature, max_tokens)
    raise RuntimeError(f"Unsupported provider: {provider}")


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
    context_zh = str(job.get("context_zh", "")).strip()
    context_en = str(job.get("context_en", "")).strip()
    lang_text = ", ".join(langs)
    return [
        {
            "role": "system",
            "content": (
                "You are a strict localization engine for Chinese learning context sentences. "
                "Return only valid JSON. No markdown."
            ),
        },
        {
            "role": "user",
            "content": (
                "Translate ONE Chinese sentence into target languages.\n"
                f"concept_id: {concept_id}\n"
                f"focus_word: {hanzi}\n"
                f"focus_pinyin: {pinyin or '(none)'}\n"
                f"context_zh: {context_zh}\n"
                f"context_en_hint: {context_en or '(none)'}\n"
                f"target_language_codes: [{lang_text}]\n\n"
                "Rules:\n"
                "- Translate the full sentence naturally.\n"
                "- Preserve sentence meaning and tone.\n"
                "- Keep punctuation natural in each language.\n"
                "- Return exact JSON format:\n"
                '{ "translations": { "es": "...", "fr": "..." } }'
            ),
        },
    ]


async def _process_chunk(
    chunk: List[str],
    job: Dict[str, Any],
    provider: str,
    max_retries: int,
    temperature: float,
    max_tokens: int,
    semaphore: asyncio.Semaphore,
) -> Tuple[Dict[str, str], str]:
    for attempt in range(1, max_retries + 1):
        try:
            async with semaphore:
                response_text = await asyncio.to_thread(
                    _chat_completion,
                    provider,
                    _build_messages(job, chunk),
                    temperature,
                    max_tokens,
                )
            payload = _json_from_text(response_text)
            translated = _extract_translations(payload, chunk)
            if not translated:
                raise ValueError("No translations parsed for chunk")
            return translated, ""
        except Exception as exc:  # noqa: PERF203
            sleep_s = min(15.0, 1.3**attempt + random.uniform(0.0, 0.8))
            await asyncio.sleep(sleep_s)
            last_err = str(exc)
    return {}, last_err


async def _translate_job(
    job: Dict[str, Any],
    provider: str,
    langs_per_call: int,
    max_retries: int,
    temperature: float,
    max_tokens: int,
    semaphore: asyncio.Semaphore,
) -> Tuple[Dict[str, str], str]:
    missing_langs = [str(x).lower() for x in (job.get("missing_langs") or []) if str(x).strip()]
    chunks = _chunked(missing_langs, langs_per_call)

    tasks = [
        _process_chunk(chunk, job, provider, max_retries, temperature, max_tokens, semaphore)
        for chunk in chunks
    ]
    results = await asyncio.gather(*tasks)

    all_translations: Dict[str, str] = {}
    errors: List[str] = []
    for trans, err in results:
        if trans:
            all_translations.update(trans)
        if err:
            errors.append(err)

    if not all_translations and errors:
        return {}, "; ".join(errors)
    return all_translations, ""


def _save_shard(
    out_path: Path,
    shard_path: Path,
    provider: str,
    items_map: Dict[str, Any],
    failures_map: Dict[str, Any],
) -> None:
    out_payload = {
        "meta": {
            "source_shard": str(shard_path),
            "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
            "items": len(items_map),
            "failures": len(failures_map),
            "provider": provider,
            "model": (
                DEEPSEEK_MODEL
                if provider == "deepseek"
                else (OPENAI_MODEL if provider == "openai" else GEMINI_MODEL)
            ),
        },
        "items": list(items_map.values()),
        "failures": list(failures_map.values()),
    }
    tmp_path = out_path.with_suffix(".tmp")
    tmp_path.write_text(json.dumps(out_payload, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp_path.replace(out_path)


async def _process_shard(
    shard_path: Path,
    out_path: Path,
    provider: str,
    langs_per_call: int,
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

    items_map: Dict[str, Any] = {}
    failures_map: Dict[str, Any] = {}
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
            print(f"[{shard_path.name}] Warning: failed to read prior result; restarting shard.", flush=True)

    todo_jobs: List[Dict[str, Any]] = []
    for job in jobs:
        cid = str((job or {}).get("concept_id", "")).strip()
        if not cid:
            continue
        if cid in items_map:
            continue
        todo_jobs.append(job)

    print(
        f"[{shard_path.name}] Starting processing {len(todo_jobs)}/{len(jobs)} jobs...",
        flush=True,
    )
    _save_shard(out_path, shard_path, provider, items_map, failures_map)

    done = 0
    for job in todo_jobs:
        cid = str(job.get("concept_id", "")).strip()
        hanzi = str(job.get("hanzi", "")).strip()
        row_index = int(job.get("row_index", -1))

        translations, err = await _translate_job(
            job=job,
            provider=provider,
            langs_per_call=langs_per_call,
            max_retries=max_retries,
            temperature=temperature,
            max_tokens=max_tokens,
            semaphore=semaphore,
        )
        done += 1

        if translations:
            items_map[cid] = {
                "concept_id": cid,
                "row_index": row_index,
                "translations": translations,
            }
            failures_map.pop(cid, None)
        else:
            failures_map[cid] = {
                "concept_id": cid,
                "row_index": row_index,
                "hanzi": hanzi,
                "error": err or "unknown",
            }

        if done % _CHECKPOINT_EVERY == 0:
            print(f"[{shard_path.name}] Progress: {done}/{len(todo_jobs)} jobs...", flush=True)
            _save_shard(out_path, shard_path, provider, items_map, failures_map)

    _save_shard(out_path, shard_path, provider, items_map, failures_map)
    return {
        "source_shard": str(shard_path),
        "items": len(items_map),
        "failures": len(failures_map),
    }


async def _run(args: argparse.Namespace) -> int:
    provider = str(args.provider).strip().lower()
    if provider not in {"deepseek", "openai", "gemini"}:
        print(f"Unsupported provider: {provider}")
        return 1
    if provider == "deepseek" and not DEEPSEEK_API_KEY:
        print("DEEPSEEK_API_KEY is missing")
        return 1
    if provider == "openai" and not OPENAI_API_KEY:
        print("OPENAI_API_KEY is missing")
        return 1
    if provider == "gemini" and not GEMINI_API_KEY:
        print("GOOGLE_API_KEY is missing")
        return 1

    shards_dir = ROOT / args.shards_dir if not Path(args.shards_dir).is_absolute() else Path(args.shards_dir)
    out_dir = ROOT / args.out_dir if not Path(args.out_dir).is_absolute() else Path(args.out_dir)
    if not shards_dir.exists():
        print(f"Shards dir not found: {shards_dir}")
        return 1
    out_dir.mkdir(parents=True, exist_ok=True)

    shard_files = sorted(shards_dir.glob("context_shard_*.json"))
    if not shard_files:
        print(f"No context_shard_*.json in {shards_dir}")
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
                    provider=provider,
                    langs_per_call=args.langs_per_call,
                    max_retries=args.max_retries,
                    temperature=args.temperature,
                    max_tokens=args.max_tokens,
                    semaphore=semaphore,
                    resume=args.resume,
                )
            )
        )

    for idx, task in enumerate(asyncio.as_completed(tasks), start=1):
        meta = await task
        metas.append(meta)
        print(
            f"[{idx}/{len(tasks)}] shard done: items={meta['items']} failures={meta['failures']}",
            flush=True,
        )

    summary = {
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "shards_processed": len(metas),
        "items_total": sum(int(m["items"]) for m in metas),
        "failures_total": sum(int(m["failures"]) for m in metas),
        "out_dir": str(out_dir),
        "provider": provider,
        "model": (
            DEEPSEEK_MODEL
            if provider == "deepseek"
            else (OPENAI_MODEL if provider == "openai" else GEMINI_MODEL)
        ),
    }
    summary_path = out_dir / f"summary_{dt.date.today().isoformat()}.json"
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False))
    print(f"Summary: {summary_path}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Run context-translation workers")
    parser.add_argument("--shards-dir", default="docs/context_shards_50")
    parser.add_argument("--out-dir", default="docs/context_results")
    parser.add_argument("--provider", default="deepseek", choices=["deepseek", "openai", "gemini"])
    parser.add_argument("--agents", type=int, default=50)
    parser.add_argument("--langs-per-call", type=int, default=4)
    parser.add_argument("--max-retries", type=int, default=6)
    parser.add_argument("--temperature", type=float, default=0.2)
    parser.add_argument("--max-tokens", type=int, default=520)
    parser.add_argument("--resume", action="store_true")
    args = parser.parse_args()

    if args.agents < 1:
        raise SystemExit("--agents must be >= 1")
    if args.langs_per_call < 1:
        raise SystemExit("--langs-per-call must be >= 1")
    if args.max_retries < 1:
        raise SystemExit("--max-retries must be >= 1")

    return asyncio.run(_run(args))


if __name__ == "__main__":
    raise SystemExit(main())
