#!/usr/bin/env python3
"""Translate missing concept localizations in parallel (DeepSeek/OpenAI/Gemini).

Primary goal:
- Fill missing `concept_localizations` rows for HSK3.0 concepts quickly.
- Preserve existing translations by default (no overwrite unless requested).
- Backfill `concepts.meaning` and primary `concept_senses` when English is missing.

Usage examples:
  python3 backend/scripts/translate_hsk3_localizations.py --db backend/learning_path.db
  python3 backend/scripts/translate_hsk3_localizations.py --db backend/learning_path.db --apply --workers 12
  python3 backend/scripts/translate_hsk3_localizations.py --db backend/learning_path.db --apply --workers 15 --limit 500
"""

from __future__ import annotations

import argparse
import asyncio
import datetime as dt
import json
import os
import random
import re
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple
from urllib import error as urlerror
from urllib import request as urlrequest


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


ROOT = _repo_root()


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

DEEPSEEK_API_KEY = os.getenv("DEEPSEEK_API_KEY", "").strip()
DEEPSEEK_MODEL = os.getenv("DEEPSEEK_MODEL", "deepseek-chat").strip()
DEEPSEEK_BASE_URL = os.getenv("DEEPSEEK_API_BASE", "https://api.deepseek.com/v1").rstrip("/")

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "").strip()
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini").strip()
OPENAI_BASE_URL = os.getenv("OPENAI_API_BASE", "https://api.openai.com/v1").rstrip("/")

GEMINI_API_KEY = os.getenv("GOOGLE_API_KEY", "").strip()
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-1.5-flash").strip()


def _require_provider_credentials(provider: str) -> None:
    if provider == "deepseek" and not DEEPSEEK_API_KEY:
        raise RuntimeError("DEEPSEEK_API_KEY is missing")
    if provider == "openai" and not OPENAI_API_KEY:
        raise RuntimeError("OPENAI_API_KEY is missing")
    if provider == "gemini" and not GEMINI_API_KEY:
        raise RuntimeError("GOOGLE_API_KEY is missing")


def _http_post_json(url: str, headers: Dict[str, str], payload: Dict, timeout: float = 45.0) -> Dict:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urlrequest.Request(url, data=body, headers=headers, method="POST")
    try:
        with urlrequest.urlopen(req, timeout=timeout) as response:
            data = response.read().decode("utf-8")
            return json.loads(data)
    except urlerror.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code}: {raw}") from exc
    except urlerror.URLError as exc:
        raise RuntimeError(f"Network error: {exc}") from exc


def _openai_compatible_call(
    base_url: str,
    api_key: str,
    model: str,
    messages: List[Dict[str, str]],
    temperature: float,
    max_tokens: int,
) -> str:
    payload: Dict = {
        "model": model,
        "messages": messages,
        "max_tokens": max_tokens,
    }
    if "reasoner" not in model:
        payload["temperature"] = temperature
    data = _http_post_json(
        url=f"{base_url}/chat/completions",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        payload=payload,
    )
    choices = data.get("choices") or []
    if not choices:
        raise RuntimeError(f"No choices returned: {data}")
    text = str(((choices[0] or {}).get("message") or {}).get("content") or "").strip()
    if not text:
        raise RuntimeError(f"Empty response text: {data}")
    return text


def _gemini_call(
    model: str,
    api_key: str,
    messages: List[Dict[str, str]],
    temperature: float,
    max_tokens: int,
) -> str:
    system_parts: List[str] = []
    contents: List[Dict] = []
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
    payload: Dict = {
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
            f"{model}:generateContent?key={api_key}"
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
        raise RuntimeError(f"Empty response text: {data}")
    return text


async def _run_provider_call(
    provider: str,
    messages: List[Dict[str, str]],
    temperature: float,
    max_tokens: int,
    allow_fallback: bool,
) -> Tuple[str, str, str]:
    providers = [provider]
    if allow_fallback:
        for candidate in ("deepseek", "gemini", "openai"):
            if candidate not in providers:
                providers.append(candidate)

    errors: List[str] = []
    for item in providers:
        try:
            _require_provider_credentials(item)
            if item == "deepseek":
                text = await asyncio.to_thread(
                    _openai_compatible_call,
                    DEEPSEEK_BASE_URL,
                    DEEPSEEK_API_KEY,
                    DEEPSEEK_MODEL,
                    messages,
                    temperature,
                    max_tokens,
                )
                return text, "deepseek", DEEPSEEK_MODEL
            if item == "openai":
                text = await asyncio.to_thread(
                    _openai_compatible_call,
                    OPENAI_BASE_URL,
                    OPENAI_API_KEY,
                    OPENAI_MODEL,
                    messages,
                    temperature,
                    max_tokens,
                )
                return text, "openai", OPENAI_MODEL
            if item == "gemini":
                text = await asyncio.to_thread(
                    _gemini_call,
                    GEMINI_MODEL,
                    GEMINI_API_KEY,
                    messages,
                    temperature,
                    max_tokens,
                )
                return text, "gemini", GEMINI_MODEL
        except Exception as exc:  # noqa: PERF203
            errors.append(f"{item}: {exc}")
            continue
    raise RuntimeError("No provider succeeded: " + " | ".join(errors))


@dataclass(frozen=True)
class ConceptJob:
    concept_id: str
    hanzi: str
    pinyin: str
    anchor_english: str
    missing_langs: Tuple[str, ...]
    existing_langs: Tuple[str, ...]
    level: str
    current_meaning: str
    current_primary_gloss: str


def _split_csv(raw: str, fallback: Sequence[str]) -> List[str]:
    values = [v.strip() for v in str(raw or "").split(",") if v.strip()]
    if not values:
        return list(fallback)
    deduped: List[str] = []
    seen = set()
    for value in values:
        key = value.lower()
        if key in seen:
            continue
        seen.add(key)
        deduped.append(value)
    return deduped


def _chunked(values: Sequence[str], size: int) -> List[List[str]]:
    if size <= 0:
        return [list(values)]
    return [list(values[i : i + size]) for i in range(0, len(values), size)]


def _ensure_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS concept_localizations (
            concept_id TEXT NOT NULL,
            language_code TEXT NOT NULL,
            meaning TEXT,
            context_translation TEXT,
            source_pack TEXT,
            updated_at TEXT DEFAULT (datetime('now')),
            PRIMARY KEY (concept_id, language_code)
        );

        CREATE INDEX IF NOT EXISTS idx_cl_concept
            ON concept_localizations(concept_id);
        CREATE INDEX IF NOT EXISTS idx_cl_lang
            ON concept_localizations(language_code);
        """
    )


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
        cid = str(row["concept_id"])
        lang = str(row["language_code"]).lower()
        meaning = str(row["meaning"] or "").strip()
        if not meaning:
            continue
        out.setdefault(cid, {})[lang] = meaning
    return out


def _build_jobs(
    concepts: Sequence[sqlite3.Row],
    existing_localizations: Dict[str, Dict[str, str]],
    target_langs: Sequence[str],
    overwrite: bool,
    anchor_mode: str,
) -> List[ConceptJob]:
    target = [lang.lower() for lang in target_langs]
    jobs: List[ConceptJob] = []
    for row in concepts:
        concept_id = str(row["concept_id"])
        hanzi = str(row["hanzi"] or "").strip()
        if not hanzi:
            continue
        pinyin = str(row["pinyin"] or "").strip()
        current_meaning = str(row["current_meaning"] or "").strip()
        current_primary_gloss = str(row["current_primary_gloss"] or "").strip()
        level = str(row["level"] or "").strip()
        existing = existing_localizations.get(concept_id, {})
        existing_langs = tuple(sorted(existing.keys()))
        if anchor_mode == "empty":
            anchor_english = ""
        else:
            anchor_english = existing.get("en") or current_primary_gloss or current_meaning
        if not overwrite:
            missing = [lang for lang in target if not existing.get(lang, "").strip()]
        else:
            missing = list(target)
        if "en" not in missing and not (anchor_english or "").strip():
            missing = ["en", *missing]
        if not missing:
            continue
        jobs.append(
            ConceptJob(
                concept_id=concept_id,
                hanzi=hanzi,
                pinyin=pinyin,
                anchor_english=(anchor_english or "").strip(),
                missing_langs=tuple(missing),
                existing_langs=existing_langs,
                level=level,
                current_meaning=current_meaning,
                current_primary_gloss=current_primary_gloss,
            )
        )
    return jobs


def _json_from_text(raw: str) -> Dict:
    text = (raw or "").strip()
    if not text:
        raise ValueError("Empty model response")
    start = text.find("{")
    end = text.rfind("}")
    if start < 0 or end < 0 or end <= start:
        raise ValueError(f"Model response is not JSON: {text[:240]}")
    snippet = text[start : end + 1]
    payload = json.loads(snippet)
    if not isinstance(payload, dict):
        raise ValueError("Model JSON payload must be an object")
    return payload


def _extract_translations(payload: Dict, missing_langs: Sequence[str]) -> Dict[str, str]:
    def _normalize_single_gloss(text: str) -> str:
        value = str(text or "").strip()
        if not value:
            return ""
        value = value.replace("```", "").strip()
        value = re.sub(r"\s+", " ", value)
        # Keep only one primary sense.
        for sep in (";", "；", "/", "\n", "、", "|"):
            if sep in value:
                value = value.split(sep, 1)[0].strip()
        if "," in value:
            parts = [p.strip() for p in value.split(",") if p.strip()]
            if len(parts) > 1:
                value = parts[0]
        return value.strip(" .;，、；:：")

    translations_raw = payload.get("translations", payload)
    if not isinstance(translations_raw, dict):
        raise ValueError("Response must contain object `translations` or root map")
    out: Dict[str, str] = {}
    for lang in missing_langs:
        value = translations_raw.get(lang)
        if value is None:
            continue
        text = _normalize_single_gloss(str(value))
        if text:
            out[lang] = text
    return out


def _build_messages(job: ConceptJob, languages: Sequence[str]) -> List[Dict[str, str]]:
    langs = ", ".join(languages)
    anchor = job.anchor_english or "(none)"
    return [
        {
            "role": "system",
            "content": (
                "You are a strict Chinese vocabulary localization engine. "
                "Return only valid JSON with no markdown."
            ),
        },
        {
            "role": "user",
            "content": (
                "Translate ONE Chinese vocabulary concept into requested languages.\n"
                f"concept_id: {job.concept_id}\n"
                f"hanzi: {job.hanzi}\n"
                f"pinyin: {job.pinyin or '(none)'}\n"
                f"primary_english_anchor: {anchor}\n"
                f"target_language_codes: [{langs}]\n\n"
                "Rules:\n"
                "- Use one primary sense only (exam-friendly, neutral).\n"
                "- Each translation must be a short phrase (max ~8 words).\n"
                "- No numbering, no explanations, no examples.\n"
                "- Keep language natural and learner-safe.\n\n"
                "Return exactly this JSON schema:\n"
                "{\n"
                '  "translations": {\n'
                '    "en": "primary gloss in English if requested",\n'
                '    "es": "translation if requested"\n'
                "  }\n"
                "}"
            ),
        },
    ]


async def _translate_with_retries(
    job: ConceptJob,
    provider: str,
    allow_fallback: bool,
    temperature: float,
    max_tokens: int,
    max_retries: int,
    langs_per_call: int,
) -> Tuple[Dict[str, str], str, str]:
    all_translations: Dict[str, str] = {}
    used_provider = provider
    used_model = ""
    last_error: str = ""

    lang_chunks = _chunked(list(job.missing_langs), langs_per_call)
    for lang_chunk in lang_chunks:
        chunk_error = ""
        for attempt in range(1, max_retries + 1):
            try:
                reply, used_provider, used_model = await _run_provider_call(
                    provider=provider,
                    messages=_build_messages(job, lang_chunk),
                    temperature=temperature,
                    max_tokens=max_tokens,
                    allow_fallback=allow_fallback,
                )
                payload = _json_from_text(reply)
                translations = _extract_translations(payload, lang_chunk)
                if not translations:
                    raise ValueError("Parsed response contains no requested language translations")
                all_translations.update(translations)
                chunk_error = ""
                break
            except Exception as exc:  # noqa: PERF203
                chunk_error = str(exc)
                last_error = chunk_error
                backoff = min(15.0, (1.4 ** attempt) + random.uniform(0.0, 0.9))
                await asyncio.sleep(backoff)
        if chunk_error:
            # Skip this chunk and continue others; caller still fails if nothing translated.
            print(
                f"[warn] partial-translation concept={job.concept_id} "
                f"chunk={','.join(lang_chunk)} error={chunk_error}"
            )

    if not all_translations:
        raise RuntimeError(last_error or "Unknown translation failure")
    return all_translations, used_provider, used_model


def _upsert_translations(
    conn: sqlite3.Connection,
    job: ConceptJob,
    translations: Dict[str, str],
    source_pack: str,
    overwrite: bool,
    overwrite_meaning: bool,
    overwrite_primary_sense: bool,
) -> Tuple[int, bool, bool]:
    inserted = 0
    updated_concepts_meaning = False
    inserted_primary_sense = False
    for lang, meaning in translations.items():
        lang_code = lang.lower().strip()
        text = meaning.strip()
        if not lang_code or not text:
            continue

        existing = conn.execute(
            """
            SELECT meaning
            FROM concept_localizations
            WHERE concept_id = ? AND language_code = ?
            LIMIT 1
            """,
            (job.concept_id, lang_code),
        ).fetchone()
        existing_text = str(existing[0] or "").strip() if existing else ""
        if existing_text and not overwrite:
            continue

        conn.execute(
            """
            INSERT INTO concept_localizations
                (concept_id, language_code, meaning, context_translation, source_pack, updated_at)
            VALUES (?, ?, ?, '', ?, datetime('now'))
            ON CONFLICT(concept_id, language_code) DO UPDATE SET
                meaning = excluded.meaning,
                source_pack = excluded.source_pack,
                updated_at = datetime('now')
            """,
            (job.concept_id, lang_code, text, source_pack),
        )
        inserted += 1

        if lang_code == "en":
            if overwrite_meaning or not (job.current_meaning or "").strip():
                conn.execute(
                    "UPDATE concepts SET meaning = ? WHERE id = ?",
                    (text, job.concept_id),
                )
                updated_concepts_meaning = True

    # Ensure at least one primary sense exists when EN is now available.
    has_sense = conn.execute(
        "SELECT 1 FROM concept_senses WHERE concept_id = ? LIMIT 1",
        (job.concept_id,),
    ).fetchone()
    en_text = (
        translations.get("en")
        or job.anchor_english
        or job.current_primary_gloss
        or job.current_meaning
    )
    if not has_sense and str(en_text or "").strip():
        conn.execute(
            """
            INSERT OR IGNORE INTO concept_senses
                (sense_id, concept_id, ordinal, gloss, is_primary, source)
            VALUES (?, ?, 1, ?, 1, 'ai_localization')
            """,
            (f"{job.concept_id}::s01", job.concept_id, str(en_text).strip()),
        )
        inserted_primary_sense = True
    elif overwrite_primary_sense and str(en_text or "").strip():
        target_gloss = str(en_text).strip()
        same_gloss_row = conn.execute(
            """
            SELECT sense_id
            FROM concept_senses
            WHERE concept_id = ? AND gloss = ?
            ORDER BY is_primary DESC, ordinal ASC, sense_id ASC
            LIMIT 1
            """,
            (job.concept_id, target_gloss),
        ).fetchone()
        if same_gloss_row is not None:
            sid = str(same_gloss_row[0])
            conn.execute(
                "UPDATE concept_senses SET is_primary = 0 WHERE concept_id = ?",
                (job.concept_id,),
            )
            conn.execute(
                """
                UPDATE concept_senses
                SET is_primary = 1, source = ?
                WHERE sense_id = ?
                """,
                (source_pack, sid),
            )
            return inserted, updated_concepts_meaning, inserted_primary_sense

        primary_row = conn.execute(
            """
            SELECT sense_id
            FROM concept_senses
            WHERE concept_id = ? AND is_primary = 1
            ORDER BY ordinal ASC, sense_id ASC
            LIMIT 1
            """,
            (job.concept_id,),
        ).fetchone()
        if primary_row is not None:
            conn.execute(
                """
                UPDATE concept_senses
                SET gloss = ?, source = ?
                WHERE sense_id = ?
                """,
                (target_gloss, source_pack, str(primary_row[0])),
            )
        else:
            fallback_row = conn.execute(
                """
                SELECT sense_id
                FROM concept_senses
                WHERE concept_id = ?
                ORDER BY ordinal ASC, sense_id ASC
                LIMIT 1
                """,
                (job.concept_id,),
            ).fetchone()
            if fallback_row is not None:
                sid = str(fallback_row[0])
                conn.execute(
                    "UPDATE concept_senses SET is_primary = 0 WHERE concept_id = ?",
                    (job.concept_id,),
                )
                conn.execute(
                    """
                    UPDATE concept_senses
                    SET gloss = ?, is_primary = 1, source = ?
                    WHERE sense_id = ?
                    """,
                    (target_gloss, source_pack, sid),
                )

    return inserted, updated_concepts_meaning, inserted_primary_sense


def _sample_jobs(jobs: Sequence[ConceptJob], count: int = 12) -> List[Dict]:
    sample: List[Dict] = []
    for job in jobs[:count]:
        sample.append(
            {
                "concept_id": job.concept_id,
                "hanzi": job.hanzi,
                "pinyin": job.pinyin,
                "level": job.level,
                "missing_langs": list(job.missing_langs),
                "anchor_english": job.anchor_english,
            }
        )
    return sample


async def _run_apply(
    conn: sqlite3.Connection,
    jobs: Sequence[ConceptJob],
    provider: str,
    allow_fallback: bool,
    temperature: float,
    max_tokens: int,
    langs_per_call: int,
    workers: int,
    max_retries: int,
    source_pack: str,
    overwrite: bool,
    overwrite_meaning: bool,
    overwrite_primary_sense: bool,
) -> Dict[str, int]:
    queue: asyncio.Queue[ConceptJob | None] = asyncio.Queue()
    write_lock = asyncio.Lock()
    stats = {
        "jobs_total": len(jobs),
        "jobs_done": 0,
        "jobs_failed": 0,
        "localizations_written": 0,
        "concepts_meaning_updated": 0,
        "primary_senses_inserted": 0,
    }

    for job in jobs:
        queue.put_nowait(job)
    for _ in range(workers):
        queue.put_nowait(None)

    async def _worker(worker_id: int) -> None:
        while True:
            job = await queue.get()
            if job is None:
                queue.task_done()
                return
            try:
                translations, used_provider, used_model = await _translate_with_retries(
                    job=job,
                    provider=provider,
                    allow_fallback=allow_fallback,
                    temperature=temperature,
                    max_tokens=max_tokens,
                    max_retries=max_retries,
                    langs_per_call=langs_per_call,
                )
                async with write_lock:
                    written, concept_updated, sense_inserted = _upsert_translations(
                        conn=conn,
                        job=job,
                        translations=translations,
                        source_pack=f"{source_pack}:{used_provider}:{used_model}",
                        overwrite=overwrite,
                        overwrite_meaning=overwrite_meaning,
                        overwrite_primary_sense=overwrite_primary_sense,
                    )
                    conn.commit()
                    stats["localizations_written"] += written
                    if concept_updated:
                        stats["concepts_meaning_updated"] += 1
                    if sense_inserted:
                        stats["primary_senses_inserted"] += 1
                    stats["jobs_done"] += 1
                    if stats["jobs_done"] % 50 == 0:
                        print(
                            f"[progress] done={stats['jobs_done']}/{stats['jobs_total']} "
                            f"failed={stats['jobs_failed']} writes={stats['localizations_written']}"
                        )
            except Exception as exc:  # noqa: PERF203
                async with write_lock:
                    stats["jobs_failed"] += 1
                    stats["jobs_done"] += 1
                    print(
                        f"[worker-{worker_id}] FAIL concept={job.concept_id} hanzi={job.hanzi} error={exc}"
                    )
            finally:
                queue.task_done()

    workers_tasks = [asyncio.create_task(_worker(i + 1)) for i in range(workers)]
    await queue.join()
    await asyncio.gather(*workers_tasks)
    return stats


def _group_counts(items: Iterable[str]) -> Dict[str, int]:
    out: Dict[str, int] = {}
    for item in items:
        out[item] = out.get(item, 0) + 1
    return dict(sorted(out.items(), key=lambda kv: kv[0]))


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Parallel translation of missing concept localizations (HSK3.0-first)."
    )
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--standard", default="HSK3.0")
    parser.add_argument("--levels", default=",".join(DEFAULT_LEVELS))
    parser.add_argument("--target-langs", default=",".join(DEFAULT_TARGET_LANGS))
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--offset", type=int, default=0)
    parser.add_argument("--provider", default="deepseek", choices=["deepseek", "gemini", "openai"])
    parser.add_argument("--allow-fallback", action="store_true")
    parser.add_argument("--temperature", type=float, default=0.2)
    parser.add_argument("--max-tokens", type=int, default=420)
    parser.add_argument("--max-retries", type=int, default=3)
    parser.add_argument("--langs-per-call", type=int, default=8)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--overwrite-concepts-meaning", action="store_true")
    parser.add_argument(
        "--overwrite-primary-sense",
        action="store_true",
        help="When EN is available, overwrite existing primary sense gloss to match.",
    )
    parser.add_argument(
        "--anchor-mode",
        choices=["existing", "empty"],
        default="existing",
        help="Use existing EN anchors or force empty anchors for clean regeneration.",
    )
    parser.add_argument("--apply", action="store_true", help="Run model calls and write DB changes")
    parser.add_argument("--report-dir", default="docs/reports")
    parser.add_argument("--source-tag", default="ai_hsk3_localization_batch")
    args = parser.parse_args()

    if args.workers < 1:
        raise SystemExit("--workers must be >= 1")
    if args.workers > 40:
        raise SystemExit("--workers too high. Keep <= 40 to avoid heavy provider throttling.")
    if args.max_retries < 1:
        raise SystemExit("--max-retries must be >= 1")
    if args.langs_per_call < 1:
        raise SystemExit("--langs-per-call must be >= 1")
    if args.langs_per_call > 50:
        raise SystemExit("--langs-per-call too high. Keep <= 50")

    levels = _split_csv(args.levels, DEFAULT_LEVELS)
    target_langs = [lang.lower() for lang in _split_csv(args.target_langs, DEFAULT_TARGET_LANGS)]

    db_path = ROOT / args.db if not Path(args.db).is_absolute() else Path(args.db)
    report_dir = ROOT / args.report_dir if not Path(args.report_dir).is_absolute() else Path(args.report_dir)
    report_dir.mkdir(parents=True, exist_ok=True)
    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        _ensure_schema(conn)
        concepts = _fetch_scope_concepts(conn, args.standard, levels)
        existing_localizations = _fetch_existing_localizations(
            conn=conn,
            standard=args.standard,
            levels=levels,
            target_langs=target_langs,
        )
        jobs = _build_jobs(
            concepts=concepts,
            existing_localizations=existing_localizations,
            target_langs=target_langs,
            overwrite=args.overwrite,
            anchor_mode=args.anchor_mode,
        )

        if args.offset:
            jobs = jobs[args.offset :]
        if args.limit and args.limit > 0:
            jobs = jobs[: args.limit]

        plan = {
            "date": dt.datetime.now(dt.timezone.utc).isoformat(),
            "db": str(db_path),
            "standard": args.standard,
            "levels": levels,
            "target_langs": target_langs,
            "provider": args.provider,
            "allow_fallback": args.allow_fallback,
            "workers": args.workers,
            "langs_per_call": args.langs_per_call,
            "overwrite": args.overwrite,
            "overwrite_concepts_meaning": args.overwrite_concepts_meaning,
            "overwrite_primary_sense": args.overwrite_primary_sense,
            "anchor_mode": args.anchor_mode,
            "apply": args.apply,
            "scope_concepts_total": len(concepts),
            "jobs_total": len(jobs),
            "jobs_by_level": _group_counts(job.level for job in jobs),
            "sample_jobs": _sample_jobs(jobs),
        }

        if not args.apply:
            plan_path = report_dir / f"localization_plan_{dt.date.today().isoformat()}.json"
            plan_path.write_text(json.dumps(plan, ensure_ascii=False, indent=2), encoding="utf-8")
            print("Plan generated (no API calls, no DB writes).")
            print(f"Scope concepts: {len(concepts)}")
            print(f"Pending jobs: {len(jobs)}")
            print(f"Report: {plan_path}")
            return 0

        print(
            f"Starting translation apply run: jobs={len(jobs)} workers={args.workers} "
            f"provider={args.provider} fallback={args.allow_fallback}"
        )
        stats = asyncio.run(
            _run_apply(
                conn=conn,
                jobs=jobs,
                provider=args.provider,
                allow_fallback=args.allow_fallback,
                temperature=args.temperature,
                max_tokens=args.max_tokens,
                langs_per_call=args.langs_per_call,
                workers=args.workers,
                max_retries=args.max_retries,
                source_pack=args.source_tag,
                overwrite=args.overwrite,
                overwrite_meaning=args.overwrite_concepts_meaning,
                overwrite_primary_sense=args.overwrite_primary_sense,
            )
        )

        report = {**plan, **stats}
        report_path = report_dir / f"localization_apply_{dt.date.today().isoformat()}.json"
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print("Translation apply run complete.")
        print(f"Jobs done: {stats['jobs_done']} failed: {stats['jobs_failed']}")
        print(f"Localization rows written: {stats['localizations_written']}")
        print(f"Report: {report_path}")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
