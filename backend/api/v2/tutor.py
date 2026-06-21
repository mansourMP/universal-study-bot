import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from auth import get_user_id, verify_api_key
from services.model_router import run_chat_completion_with_metadata

router = APIRouter(prefix="/api/v2/tutor", tags=["Tutor"])
DB_PATH = Path(__file__).parent.parent / "learning_path.db"


class TutorHistoryMessage(BaseModel):
    role: str
    content: str


class TutorChatRequest(BaseModel):
    message: str
    history: List[TutorHistoryMessage] = Field(default_factory=list)
    context_words: List[str] = Field(default_factory=list)
    language_code: str = "zh"
    ai_provider: Optional[str] = None
    allow_fallback: bool = True


class TutorChatResponse(BaseModel):
    reply: str
    provider: str
    model: str
    requested_provider: str
    fallback_used: bool = False
    provider_attempts: List[Dict[str, Any]] = Field(default_factory=list)
    trace_id: str


class TutorConversationUpdateRequest(BaseModel):
    messages: List[TutorHistoryMessage] = Field(default_factory=list)
    context_words: List[str] = Field(default_factory=list)
    preferred_provider: Optional[str] = None
    language_code: str = "zh"


def _ensure_tables(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS tutor_conversations (
            user_id TEXT NOT NULL,
            language_code TEXT NOT NULL DEFAULT 'zh',
            messages_json TEXT NOT NULL DEFAULT '[]',
            context_words_json TEXT NOT NULL DEFAULT '[]',
            preferred_provider TEXT,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (user_id, language_code)
        )
        """
    )
    conn.commit()


def _db() -> sqlite3.Connection:
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    _ensure_tables(conn)
    return conn


def _safe_json_load(value: str) -> Dict[str, Any]:
    try:
        parsed = json.loads(value)
        return parsed if isinstance(parsed, dict) else {}
    except Exception:
        return {}


def _fetch_recent_words(user_id: str, language_code: str, max_words: int = 5) -> List[str]:
    try:
        conn = _db()
    except Exception:
        return []

    try:
        row = conn.execute(
            """
            SELECT word_ids
            FROM study_sessions
            WHERE user_id = ?
              AND language_code = ?
            ORDER BY COALESCE(completed_at, started_at) DESC
            LIMIT 1
            """,
            (user_id, language_code),
        ).fetchone()
        if row is None:
            row = conn.execute(
                """
                SELECT word_ids
                FROM study_sessions
                WHERE user_id = ?
                ORDER BY COALESCE(completed_at, started_at) DESC
                LIMIT 1
                """,
                (user_id,),
            ).fetchone()
        if row is None:
            return []

        raw_ids = [item.strip() for item in (row["word_ids"] or "").split(",") if item.strip()]
        if not raw_ids:
            return []

        unique_ids: List[str] = []
        for word_id in raw_ids:
            if word_id in unique_ids:
                continue
            unique_ids.append(word_id)
            if len(unique_ids) >= max_words:
                break

        placeholders = ",".join("?" * len(unique_ids))
        rows = conn.execute(
            f"""
            SELECT word_id, payload
            FROM word_exercises
            WHERE exercise_type = 'flashcard'
              AND word_id IN ({placeholders})
            """,
            tuple(unique_ids),
        ).fetchall()
        payload_by_id = {r["word_id"]: _safe_json_load(r["payload"]) for r in rows}
        words = [
            payload_by_id.get(word_id, {}).get("front", word_id)
            for word_id in unique_ids
        ]
        return [w for w in words if w][:max_words]
    except Exception:
        return []
    finally:
        conn.close()


def _default_suggestions() -> List[str]:
    return [
        "解释一下四个声调并给我一个小练习。",
        "给我 5 道 HSK1 词汇小测验。",
        "用中文和我进行 3 分钟日常对话。",
    ]


def _contextual_suggestions(words: List[str]) -> List[str]:
    preview = "、".join(words[:3])
    if not preview:
        return _default_suggestions()
    return [
        f"用这些词造句并解释：{preview}",
        f"用 {preview} 出 5 道选择题考我。",
        f"帮我练习发音：{preview}",
    ]


def _build_system_prompt(language_code: str, context_words: List[str]) -> str:
    word_hint = "、".join(context_words[:8])
    context_line = (
        f"Recent learner words to prioritize: {word_hint}."
        if word_hint
        else "No recent words provided. Start from practical beginner usage."
    )
    return (
        "You are Dragon Chinese Tutor, a high-quality Chinese learning coach. "
        "Respond with short, clear, actionable explanations. "
        "Always include pinyin when introducing Chinese words, and use encouraging but concise tone. "
        f"Primary learner target language code is '{language_code}'. "
        f"{context_line} "
        "When user asks for practice, provide a compact exercise and then wait for user answer."
    )


@router.get("/suggestions")
async def get_tutor_suggestions(
    language_code: str = Query("zh"),
    user_id: str = Depends(get_user_id),
    _: str = Depends(verify_api_key),
):
    words = _fetch_recent_words(user_id=user_id, language_code=language_code)
    suggestions = _contextual_suggestions(words)
    if words:
        subtitle = f"你刚学了 {len(words)} 个词，先用它们做练习。"
    else:
        subtitle = "从这里开始，先热身一下。"
    return {
        "headline": "准备开始练习了吗？",
        "subtitle": subtitle,
        "context_words": words,
        "suggestions": suggestions,
    }


@router.get("/history")
async def get_tutor_history(
    language_code: str = Query("zh"),
    user_id: str = Depends(get_user_id),
    _: str = Depends(verify_api_key),
):
    conn = _db()
    try:
        row = conn.execute(
            """
            SELECT messages_json, context_words_json, preferred_provider, updated_at
            FROM tutor_conversations
            WHERE user_id = ? AND language_code = ?
            """,
            (user_id, language_code),
        ).fetchone()
        if row is None:
            return {
                "messages": [],
                "context_words": [],
                "preferred_provider": None,
                "updated_at": None,
            }
        messages = json.loads(row["messages_json"] or "[]")
        context_words = json.loads(row["context_words_json"] or "[]")
        return {
            "messages": messages if isinstance(messages, list) else [],
            "context_words": context_words if isinstance(context_words, list) else [],
            "preferred_provider": row["preferred_provider"],
            "updated_at": row["updated_at"],
        }
    finally:
        conn.close()


@router.put("/history")
async def update_tutor_history(
    request: TutorConversationUpdateRequest,
    user_id: str = Depends(get_user_id),
    _: str = Depends(verify_api_key),
):
    trimmed_messages = request.messages[-100:]
    payload_messages = [
        {"role": msg.role, "content": msg.content} for msg in trimmed_messages
    ]
    payload_context = request.context_words[:20]
    now = datetime.now(timezone.utc).isoformat()

    conn = _db()
    try:
        conn.execute(
            """
            INSERT INTO tutor_conversations (
                user_id, language_code, messages_json, context_words_json, preferred_provider, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(user_id, language_code) DO UPDATE SET
                messages_json = excluded.messages_json,
                context_words_json = excluded.context_words_json,
                preferred_provider = excluded.preferred_provider,
                updated_at = excluded.updated_at
            """,
            (
                user_id,
                request.language_code,
                json.dumps(payload_messages, ensure_ascii=False),
                json.dumps(payload_context, ensure_ascii=False),
                request.preferred_provider,
                now,
            ),
        )
        conn.commit()
        return {"ok": True, "updated_at": now}
    finally:
        conn.close()


@router.delete("/history")
async def clear_tutor_history(
    language_code: str = Query("zh"),
    user_id: str = Depends(get_user_id),
    _: str = Depends(verify_api_key),
):
    conn = _db()
    try:
        conn.execute(
            "DELETE FROM tutor_conversations WHERE user_id = ? AND language_code = ?",
            (user_id, language_code),
        )
        conn.commit()
        return {"ok": True}
    finally:
        conn.close()


@router.post("/chat", response_model=TutorChatResponse)
async def tutor_chat(
    request: TutorChatRequest,
    user_id: str = Depends(get_user_id),
    _: str = Depends(verify_api_key),
):
    trace_id = uuid4().hex
    if not request.message.strip():
        raise HTTPException(status_code=400, detail="message is required")

    # Prefer explicit context from client; fallback to latest Quick Study words.
    context_words = request.context_words or _fetch_recent_words(
        user_id=user_id,
        language_code=request.language_code,
    )
    system_prompt = _build_system_prompt(request.language_code, context_words)

    messages: List[Dict[str, str]] = [{"role": "system", "content": system_prompt}]
    for history_item in request.history[-8:]:
        role = history_item.role.lower().strip()
        if role not in {"user", "assistant"}:
            role = "user"
        content = history_item.content.strip()
        if content:
            messages.append({"role": role, "content": content})
    messages.append({"role": "user", "content": request.message.strip()})

    try:
        reply, provider_used, model_used, routing_meta = await run_chat_completion_with_metadata(
            messages=messages,
            ai_provider=request.ai_provider,
            temperature=0.35,
            max_tokens=500,
            allow_fallback=request.allow_fallback,
        )
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Tutor model error [{trace_id}]: {exc}",
        )

    requested_provider = (
        str(routing_meta.get("requested_provider") or "").strip().lower()
        or (request.ai_provider or "").strip().lower()
        or provider_used
    )
    fallback_used = bool(routing_meta.get("fallback_used", False))
    raw_attempts = routing_meta.get("provider_attempts")
    provider_attempts: List[Dict[str, Any]] = []
    if isinstance(raw_attempts, list):
        for attempt in raw_attempts:
            if not isinstance(attempt, dict):
                continue
            provider_attempts.append(
                {
                    "provider": str(attempt.get("provider") or "").strip().lower(),
                    "model": str(attempt.get("model") or "").strip(),
                    "success": bool(attempt.get("success", False)),
                    "error": str(attempt.get("error") or "").strip() or None,
                }
            )

    return TutorChatResponse(
        reply=reply,
        provider=provider_used,
        model=model_used,
        requested_provider=requested_provider,
        fallback_used=fallback_used,
        provider_attempts=provider_attempts,
        trace_id=trace_id,
    )


@router.get("/health")
async def tutor_health():
    return {"status": "ok", "timestamp": datetime.now(timezone.utc).isoformat()}
