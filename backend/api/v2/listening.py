"""
listening.py - v2 Listening API endpoints

Endpoints:
- GET /api/v2/listening/levels
- GET /api/v2/listening/lessons
- GET /api/v2/listening/lessons/{lesson_id}
"""

from __future__ import annotations

import math
import re
import sqlite3
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Path as ApiPath, Query
from pydantic import BaseModel, Field

from auth import check_user_rate_limit, verify_api_key
from cache_manager_v2 import CACHE

router = APIRouter(prefix="/api/v2/listening", tags=["listening"])

LP_DB_PATH = Path(__file__).parent.parent.parent / "learning_path.db"
V2_DB_PATH = Path(__file__).parent.parent.parent / "vocabulary_v2.db"
LISTENING_SCHEMA_VERSION = "1.0"

_LESSON_ID_RE = re.compile(r"^LIS_HSK(?P<level>\d)_(?P<index>\d{3})$")
_PERSONA_ROTATION = (
    "hsk",
    "casual",
    "professional",
    "cultural",
    "digital",
    "survival",
    "creator_01",
    "artist_01",
    "mentor_01",
)


class ListeningPreviewTerm(BaseModel):
    word: str
    meaning: str
    pinyin: str


class ListeningLaunch(BaseModel):
    intent: str = "drill"
    focus_dimension: str = "listening"
    exercise_count: int
    forced_ids: List[str]
    target_min_seconds: int
    target_max_seconds: int


class ListeningLessonDto(BaseModel):
    id: str
    level: int
    label: str
    lesson_number: int
    title: str
    range: str
    word_start: int
    word_end: int
    word_count: int
    question_count: int
    duration_sec: int
    persona_id: str
    focus_dimension: str = "listening"
    intent: str = "drill"
    forced_ids: List[str] = Field(default_factory=list)
    preview_terms: List[ListeningPreviewTerm] = Field(default_factory=list)
    launch: ListeningLaunch


class ListeningLevelsGroupDto(BaseModel):
    level: int
    label: str
    total_words: int
    lesson_count: int
    description: str


class ListeningLevelsResponse(BaseModel):
    schema_version: str
    target_lang: str
    source_lang: str
    chunk_size: int
    groups: List[ListeningLevelsGroupDto]


class ListeningLessonsResponse(BaseModel):
    schema_version: str
    target_lang: str
    source_lang: str
    level: int
    label: str
    chunk_size: int
    total_words: int
    lessons: List[ListeningLessonDto]


class ListeningLessonDetailResponse(BaseModel):
    schema_version: str
    lesson: ListeningLessonDto
    mission: ListeningLaunch


def _normalize_hsk_level(level: int) -> int:
    # HSK 7-9 is represented as level 7 in current backend mapping.
    return 7 if level >= 7 else level


def _hsk_level_key(level: int) -> str:
    return f"HSK{_normalize_hsk_level(level)}"


def _label_for_level(level: int) -> str:
    return "HSK 7-9" if level == 7 else f"HSK {level}"


def _question_count_for_chunk(index: int) -> int:
    # Stable 5-7 question rhythm.
    return 5 + (index % 3)


def _duration_for_chunk(index: int) -> int:
    # 2:00 / 2:30 / 3:00 pattern.
    return 120 + ((index % 3) * 30)


def _get_lp_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(str(LP_DB_PATH))
    conn.row_factory = sqlite3.Row
    return conn


def _get_v2_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(str(V2_DB_PATH))
    conn.row_factory = sqlite3.Row
    return conn


def _fetch_zh_level_words(
    level: int,
    source_lang: str = "en",
) -> List[Dict[str, Any]]:
    conn = _get_lp_conn()
    try:
        level_key = _hsk_level_key(level)
        rows = conn.execute(
            """
            SELECT DISTINCT
                c.id AS word_id,
                c.text AS word,
                COALESCE(c.pinyin, '') AS pinyin,
                COALESCE(
                    (
                        SELECT cl.meaning
                        FROM concept_localizations cl
                        WHERE cl.concept_id = c.id
                          AND cl.language_code = ?
                        ORDER BY cl.rowid DESC
                        LIMIT 1
                    ),
                    c.meaning,
                    ''
                ) AS meaning
            FROM concept_curriculum_map m
            JOIN concepts c ON c.id = m.concept_id
            WHERE m.standard = 'HSK3.0'
              AND m.level = ?
              AND m.band = 'core'
            ORDER BY c.id
            """,
            (source_lang, level_key),
        ).fetchall()
        return [dict(row) for row in rows]
    finally:
        conn.close()


def _fetch_non_zh_level_words(
    target_lang: str,
    level: int,
    source_lang: str = "en",
) -> List[Dict[str, Any]]:
    conn = _get_v2_conn()
    try:
        rows = conn.execute(
            """
            SELECT
                c.id AS word_id,
                c.word AS word,
                COALESCE(c.pronunciation, '') AS pinyin,
                COALESCE(t.translation, c.word, '') AS meaning
            FROM concepts c
            LEFT JOIN translations t
              ON c.id = t.concept_id
             AND t.native_lang = ?
            WHERE c.target_lang = ?
              AND c.level = ?
            ORDER BY c.id
            """,
            (source_lang, target_lang, level),
        ).fetchall()
        return [dict(row) for row in rows]
    finally:
        conn.close()


def _build_lessons_from_words(
    words: List[Dict[str, Any]],
    *,
    level: int,
    chunk_size: int,
) -> List[Dict[str, Any]]:
    lessons: List[Dict[str, Any]] = []
    if not words:
        return lessons

    total = len(words)
    lesson_count = int(math.ceil(total / chunk_size))
    level_key = _hsk_level_key(level)
    for idx in range(lesson_count):
        start_idx = idx * chunk_size
        end_idx_exclusive = min(total, (idx + 1) * chunk_size)
        chunk = words[start_idx:end_idx_exclusive]
        if not chunk:
            continue

        lesson_number = idx + 1
        question_count = _question_count_for_chunk(idx)
        duration_sec = _duration_for_chunk(idx)
        persona_id = _PERSONA_ROTATION[idx % len(_PERSONA_ROTATION)]
        word_ids = [str(item.get("word_id") or "").strip() for item in chunk]
        word_ids = [wid for wid in word_ids if wid]
        preview_terms = [
            {
                "word": str(item.get("word") or ""),
                "meaning": str(item.get("meaning") or ""),
                "pinyin": str(item.get("pinyin") or ""),
            }
            for item in chunk[:3]
        ]

        lessons.append(
            {
                "id": f"LIS_{level_key}_{lesson_number:03d}",
                "level": level,
                "label": _label_for_level(level),
                "lesson_number": lesson_number,
                "title": f"Listening {lesson_number}",
                "range": f"{start_idx + 1}-{end_idx_exclusive}",
                "word_start": start_idx + 1,
                "word_end": end_idx_exclusive,
                "word_count": len(word_ids),
                "question_count": question_count,
                "duration_sec": duration_sec,
                "persona_id": persona_id,
                "focus_dimension": "listening",
                "intent": "drill",
                "forced_ids": word_ids,
                "preview_terms": preview_terms,
                "launch": {
                    "intent": "drill",
                    "focus_dimension": "listening",
                    "exercise_count": question_count,
                    "forced_ids": word_ids,
                    # Allows 2-3 minute micro lessons.
                    "target_min_seconds": max(120, duration_sec - 30),
                    "target_max_seconds": duration_sec + 30,
                },
            }
        )

    return lessons


def _get_levels_summary(
    *,
    target_lang: str,
    source_lang: str,
    chunk_size: int,
) -> List[Dict[str, Any]]:
    groups: List[Dict[str, Any]] = []
    if target_lang == "zh":
        conn = _get_lp_conn()
        try:
            rows = conn.execute(
                """
                SELECT level, COUNT(DISTINCT concept_id) AS cnt
                FROM concept_curriculum_map
                WHERE standard='HSK3.0' AND band='core'
                GROUP BY level
                ORDER BY level
                """
            ).fetchall()
            for row in rows:
                level_key = str(row["level"] or "").strip().upper()
                if not level_key.startswith("HSK"):
                    continue
                try:
                    level = int(level_key.replace("HSK", ""))
                except ValueError:
                    continue
                total_words = int(row["cnt"] or 0)
                lesson_count = int(math.ceil(total_words / chunk_size))
                groups.append(
                    {
                        "level": level,
                        "label": _label_for_level(level),
                        "total_words": total_words,
                        "lesson_count": lesson_count,
                        "description": f"{lesson_count} listening lessons",
                    }
                )
        finally:
            conn.close()
    else:
        conn = _get_v2_conn()
        try:
            rows = conn.execute(
                """
                SELECT level, COUNT(*) AS cnt
                FROM concepts
                WHERE target_lang = ?
                GROUP BY level
                ORDER BY level
                """,
                (target_lang,),
            ).fetchall()
            for row in rows:
                level = int(row["level"] or 0)
                if level <= 0:
                    continue
                total_words = int(row["cnt"] or 0)
                lesson_count = int(math.ceil(total_words / chunk_size))
                groups.append(
                    {
                        "level": level,
                        "label": f"L{level}",
                        "total_words": total_words,
                        "lesson_count": lesson_count,
                        "description": f"{lesson_count} listening lessons",
                    }
                )
        finally:
            conn.close()

    return groups


@router.get("/levels", response_model=ListeningLevelsResponse)
async def get_listening_levels(
    target_lang: str = Query("zh", description="Target language code"),
    source_lang: str = Query("en", description="Source/native language code"),
    chunk_size: int = Query(12, ge=8, le=20),
    client_id: str = Depends(verify_api_key),
    user_id: str = Depends(check_user_rate_limit),
):
    _ = client_id, user_id
    cache_key = f"listen:levels:{target_lang}:{source_lang}:{chunk_size}"
    cached = CACHE.get(cache_key)
    if cached is not None:
        return cached
    groups = _get_levels_summary(
        target_lang=target_lang,
        source_lang=source_lang,
        chunk_size=chunk_size,
    )
    response = {
        "schema_version": LISTENING_SCHEMA_VERSION,
        "target_lang": target_lang,
        "source_lang": source_lang,
        "chunk_size": chunk_size,
        "groups": groups,
    }
    CACHE.set(cache_key, response)
    return response


@router.get("/lessons", response_model=ListeningLessonsResponse)
async def get_listening_lessons(
    target_lang: str = Query("zh", description="Target language code"),
    source_lang: str = Query("en", description="Source/native language code"),
    level: int = Query(..., ge=1, le=9),
    chunk_size: int = Query(12, ge=8, le=20),
    client_id: str = Depends(verify_api_key),
    user_id: str = Depends(check_user_rate_limit),
):
    _ = client_id, user_id
    level = _normalize_hsk_level(level)
    cache_key = (
        f"listen:lessons:{target_lang}:{source_lang}:{level}:{chunk_size}"
    )
    cached = CACHE.get(cache_key)
    if cached is not None:
        return cached

    if target_lang == "zh":
        words = _fetch_zh_level_words(level=level, source_lang=source_lang)
    else:
        words = _fetch_non_zh_level_words(
            target_lang=target_lang,
            level=level,
            source_lang=source_lang,
        )
    lessons = _build_lessons_from_words(
        words,
        level=level,
        chunk_size=chunk_size,
    )
    response = {
        "schema_version": LISTENING_SCHEMA_VERSION,
        "target_lang": target_lang,
        "source_lang": source_lang,
        "level": level,
        "label": _label_for_level(level),
        "chunk_size": chunk_size,
        "total_words": len(words),
        "lessons": lessons,
    }
    CACHE.set(cache_key, response)
    return response


@router.get(
    "/lessons/{lesson_id}",
    response_model=ListeningLessonDetailResponse,
)
async def get_listening_lesson_detail(
    lesson_id: str = ApiPath(..., description="Listening lesson ID"),
    target_lang: str = Query("zh", description="Target language code"),
    source_lang: str = Query("en", description="Source/native language code"),
    chunk_size: int = Query(12, ge=8, le=20),
    client_id: str = Depends(verify_api_key),
    user_id: str = Depends(check_user_rate_limit),
):
    _ = client_id, user_id
    match = _LESSON_ID_RE.match(str(lesson_id).strip().upper())
    if not match:
        raise HTTPException(status_code=404, detail="Listening lesson not found")

    level = _normalize_hsk_level(int(match.group("level")))
    lesson_index = int(match.group("index"))
    if lesson_index <= 0:
        raise HTTPException(status_code=404, detail="Listening lesson not found")

    if target_lang == "zh":
        words = _fetch_zh_level_words(level=level, source_lang=source_lang)
    else:
        words = _fetch_non_zh_level_words(
            target_lang=target_lang,
            level=level,
            source_lang=source_lang,
        )

    lessons = _build_lessons_from_words(
        words,
        level=level,
        chunk_size=chunk_size,
    )
    idx = lesson_index - 1
    if idx >= len(lessons):
        raise HTTPException(status_code=404, detail="Listening lesson not found")

    lesson = lessons[idx]
    return {
        "schema_version": LISTENING_SCHEMA_VERSION,
        "lesson": lesson,
        "mission": lesson["launch"],
    }
