#!/usr/bin/env python3
"""Fill missing language translations in fast_results.db partial rows.

Use when super_generator_v2 stalls with rows that have < 36 languages.
The script reads expected missing_langs per concept from shard files,
then calls DeepSeek only for missing languages and merges results.
"""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import time
from pathlib import Path
from typing import Any, Dict, List, Tuple
from urllib import error as urlerror
from urllib import request as urlrequest


DEEPSEEK_MODEL = os.getenv("DEEPSEEK_MODEL", "deepseek-chat").strip()
DEEPSEEK_BASE_URL = os.getenv("DEEPSEEK_API_BASE", "https://api.deepseek.com/v1").rstrip("/")
DEEPSEEK_API_KEY = os.getenv("DEEPSEEK_API_KEY", "").strip()


def _chunked(values: List[str], size: int) -> List[List[str]]:
    if size <= 0:
        return [values]
    return [values[i : i + size] for i in range(0, len(values), size)]


def _http_post_json(url: str, headers: Dict[str, str], payload: Dict[str, Any], timeout: float = 60.0) -> Dict[str, Any]:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urlrequest.Request(url, data=body, headers=headers, method="POST")
    with urlrequest.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _json_from_text(raw: str) -> Dict[str, Any]:
    text = str(raw or "").strip()
    start = text.find("{")
    end = text.rfind("}")
    if start < 0 or end <= start:
        raise ValueError(f"Response is not JSON: {text[:240]}")
    return json.loads(text[start : end + 1])


def _chat(messages: List[Dict[str, str]], max_tokens: int, temperature: float) -> str:
    payload: Dict[str, Any] = {
        "model": DEEPSEEK_MODEL,
        "messages": messages,
        "max_tokens": max_tokens,
    }
    if "reasoner" not in DEEPSEEK_MODEL:
        payload["temperature"] = temperature
    data = _http_post_json(
        f"{DEEPSEEK_BASE_URL}/chat/completions",
        {
            "Authorization": f"Bearer {DEEPSEEK_API_KEY}",
            "Content-Type": "application/json",
        },
        payload,
    )
    choices = data.get("choices") or []
    if not choices:
        raise RuntimeError(f"No choices: {data}")
    msg = (choices[0] or {}).get("message") or {}
    content = str(msg.get("content") or "").strip()
    if not content:
        raise RuntimeError(f"Empty content: {data}")
    return content


def _build_messages(concept_id: str, hanzi: str, pinyin: str, anchor_english: str, langs: List[str]) -> List[Dict[str, str]]:
    lang_text = ", ".join(langs)
    return [
        {
            "role": "system",
            "content": "You are a strict Chinese vocabulary localization engine. Return only valid JSON.",
        },
        {
            "role": "user",
            "content": (
                "Translate ONE Chinese vocabulary concept.\\n"
                f"concept_id: {concept_id}\\n"
                f"hanzi: {hanzi}\\n"
                f"pinyin: {pinyin or '(none)'}\\n"
                f"anchor_english: {anchor_english or '(none)'}\\n"
                f"target_language_codes: [{lang_text}]\\n\\n"
                "Rules:\\n"
                "- One primary meaning per language (no lists).\\n"
                "- Keep translation short, neutral, exam-safe.\\n"
                "- Return exact JSON: { \"translations\": { \"en\": \"...\" } }"
            ),
        },
    ]


def _extract_translations(payload: Dict[str, Any], langs: List[str]) -> Dict[str, str]:
    raw = payload.get("translations", payload)
    if not isinstance(raw, dict):
        return {}
    out: Dict[str, str] = {}
    for lang in langs:
        value = raw.get(lang)
        if value is None:
            continue
        text = str(value).strip()
        if text:
            out[lang] = text
    return out


def _load_job_map(shards_dir: Path) -> Dict[str, Dict[str, Any]]:
    job_map: Dict[str, Dict[str, Any]] = {}
    for shard in sorted(shards_dir.glob("localization_shard_*.json")):
        try:
            payload = json.loads(shard.read_text(encoding="utf-8"))
        except Exception:
            continue
        for job in payload.get("jobs", []):
            cid = str(job.get("concept_id", "")).strip()
            if cid and cid not in job_map:
                job_map[cid] = job
    return job_map


def _load_partials(conn: sqlite3.Connection, job_map: Dict[str, Dict[str, Any]]) -> List[Tuple[str, str, Dict[str, str], List[str], str, str]]:
    rows = conn.execute("SELECT concept_id, hanzi, data FROM translations").fetchall()
    partials: List[Tuple[str, str, Dict[str, str], List[str], str, str]] = []
    for concept_id, hanzi, data_raw in rows:
        cid = str(concept_id)
        try:
            data = json.loads(data_raw or "{}")
        except Exception:
            data = {}
        if not isinstance(data, dict):
            data = {}

        job = job_map.get(cid, {})
        expected = [str(x).lower() for x in (job.get("missing_langs") or []) if str(x).strip()]
        if not expected:
            continue

        missing = [lang for lang in expected if not str(data.get(lang, "")).strip()]
        if missing:
            partials.append(
                (
                    cid,
                    str(hanzi or job.get("hanzi") or ""),
                    data,
                    missing,
                    str(job.get("pinyin") or ""),
                    str(job.get("anchor_english") or ""),
                )
            )
    return partials


def _fill_missing_for_word(
    *,
    concept_id: str,
    hanzi: str,
    pinyin: str,
    anchor_english: str,
    missing_langs: List[str],
    langs_per_call: int,
    max_retries: int,
    max_tokens: int,
    temperature: float,
) -> Dict[str, str]:
    found: Dict[str, str] = {}
    for chunk in _chunked(missing_langs, langs_per_call):
        ok = False
        for attempt in range(1, max_retries + 1):
            try:
                raw = _chat(
                    _build_messages(concept_id, hanzi, pinyin, anchor_english, chunk),
                    max_tokens=max_tokens,
                    temperature=temperature,
                )
                payload = _json_from_text(raw)
                parsed = _extract_translations(payload, chunk)
                if not parsed:
                    raise RuntimeError("No translations parsed")
                found.update(parsed)
                ok = True
                break
            except Exception as exc:
                if attempt == max_retries:
                    print(f"  chunk failed concept={concept_id} langs={chunk} err={exc}")
                time.sleep(min(8.0, 0.8 * attempt))
        if not ok:
            continue
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description="Fix partial translations in fast_results.db")
    parser.add_argument("--db", default="fast_results.db")
    parser.add_argument("--shards-dir", default="docs/translation_shards_50")
    parser.add_argument("--langs-per-call", type=int, default=4)
    parser.add_argument("--max-retries", type=int, default=8)
    parser.add_argument("--max-tokens", type=int, default=420)
    parser.add_argument("--temperature", type=float, default=0.1)
    parser.add_argument("--max-passes", type=int, default=5)
    args = parser.parse_args()

    if not DEEPSEEK_API_KEY:
        print("DEEPSEEK_API_KEY missing in env")
        return 2

    root = Path.cwd()
    db_path = root / args.db
    shards_dir = root / args.shards_dir
    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 2
    if not shards_dir.exists():
        print(f"Shards dir not found: {shards_dir}")
        return 2

    job_map = _load_job_map(shards_dir)
    if not job_map:
        print("No jobs loaded from shards")
        return 2

    conn = sqlite3.connect(str(db_path))
    try:
        for p in range(1, max(1, args.max_passes) + 1):
            partials = _load_partials(conn, job_map)
            print(f"pass={p} partials={len(partials)}")
            if not partials:
                break

            updated = 0
            for cid, hanzi, existing, missing, pinyin, anchor in partials:
                print(f"- {cid} {hanzi} missing={missing}")
                add = _fill_missing_for_word(
                    concept_id=cid,
                    hanzi=hanzi,
                    pinyin=pinyin,
                    anchor_english=anchor,
                    missing_langs=missing,
                    langs_per_call=max(1, args.langs_per_call),
                    max_retries=max(1, args.max_retries),
                    max_tokens=max(64, args.max_tokens),
                    temperature=args.temperature,
                )
                if add:
                    merged = dict(existing)
                    merged.update(add)
                    conn.execute(
                        "UPDATE translations SET data=? WHERE concept_id=?",
                        (json.dumps(merged, ensure_ascii=False), cid),
                    )
                    updated += 1
            conn.commit()
            print(f"pass={p} updated={updated}")

        remaining = _load_partials(conn, job_map)
        print(f"remaining_partials={len(remaining)}")
        if remaining:
            for cid, hanzi, _, missing, _, _ in remaining[:20]:
                print(f"remain {cid} {hanzi} missing={missing}")
            return 1
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
