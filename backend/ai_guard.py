import json
import math
import os
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Optional

from fastapi import HTTPException, Request, Response
from redis.asyncio import Redis
from redis.exceptions import NoScriptError
from sqlalchemy import BigInteger, Column, DateTime, Integer, MetaData, String, Table, create_engine
from sqlalchemy.sql import func
from starlette.concurrency import run_in_threadpool


AI_GUARD_ENABLED = os.getenv("AI_GUARD_ENABLED", "true").lower() == "true"
REDIS_URL = os.getenv("REDIS_URL")

PLAN_DAILY_LIMITS = {
    "free": int(os.getenv("AI_GUARD_FREE_DAILY", "15")),
    "plus": int(os.getenv("AI_GUARD_PLUS_DAILY", "10000")),
    "creator": int(os.getenv("AI_GUARD_CREATOR_DAILY", "30000")),
    "silver": int(os.getenv("AI_GUARD_SILVER_DAILY", "10000")),
    "gold": int(os.getenv("AI_GUARD_GOLD_DAILY", "30000")),
    "classroom": int(os.getenv("AI_GUARD_CLASSROOM_DAILY", "50000")),
}

PLAN_ALIASES = {
    "smart": "plus",
    "pro": "creator",
}

OPENAI_ALLOWED_PLANS = {"creator"}

BONUS_SCREEN_TIME = int(os.getenv("AI_GUARD_BONUS_SCREEN_TIME", "10"))
BONUS_NOTIFICATIONS = int(os.getenv("AI_GUARD_BONUS_NOTIFICATIONS", "10"))
FREE_DAILY_MAX = int(os.getenv("AI_GUARD_FREE_DAILY_MAX", "50"))

IP_RPM_LIMIT = int(os.getenv("AI_GUARD_IP_RPM", "60"))
DEVICE_RPM_LIMIT = int(os.getenv("AI_GUARD_DEVICE_RPM", "60"))
BURST_CAP = int(os.getenv("AI_GUARD_BURST_CAP", "10"))
BURST_REFILL_PER_SEC = float(os.getenv("AI_GUARD_BURST_REFILL", "0.5"))

DEFAULT_OUT_TOKENS = {
    "chat": int(os.getenv("AI_GUARD_OUT_CHAT", "600")),
    "quiz": int(os.getenv("AI_GUARD_OUT_QUIZ", "500")),
    "flashcards": int(os.getenv("AI_GUARD_OUT_FLASHCARDS", "300")),
    "ingest": int(os.getenv("AI_GUARD_OUT_INGEST", "400")),
    "consciousness": int(os.getenv("AI_GUARD_OUT_CONSCIOUSNESS", "300")),
}

PROVIDER_MULTIPLIERS = {
    "openai": 1.0,
    "deepseek": 0.35,
}

FEATURE_MULTIPLIERS = {
    "chat": 1.0,
    "quiz": 0.6,
    "flashcards": 0.4,
    "podcast": 3.0,
    "ingest": 0.8,
    "consciousness": 0.6,
}

AI_GUARD_PATH_FEATURES = {
    "/api/chat": "chat",
    "/api/generate/quiz": "quiz",
    "/api/generate/flashcards": "flashcards",
    "/api/ingest": "ingest",
    "/api/ingest_file": "ingest",
    "/api/consciousness": "consciousness",
}

LEDGER_ENABLED = os.getenv("AI_LEDGER_ENABLED", "true").lower() == "true"
LEDGER_DB_URL = os.getenv("AI_LEDGER_DB_URL", "sqlite:///./ai_usage_ledger.db")
LEDGER_METADATA = MetaData()
LEDGER_TABLE = Table(
    "ai_usage_ledger",
    LEDGER_METADATA,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column("ts", DateTime(timezone=True), server_default=func.now(), nullable=False),
    Column("user_id", String, nullable=False),
    Column("device_id", String, nullable=True),
    Column("org_id", String, nullable=True),
    Column("provider", String, nullable=False),
    Column("feature", String, nullable=False),
    Column("tokens_in", Integer, nullable=False),
    Column("tokens_out", Integer, nullable=False),
    Column("credits", Integer, nullable=False),
    Column("path", String, nullable=False),
    Column("status", Integer, nullable=False),
)


def yyyymmdd_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d")


def minute_bucket_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d%H%M")


def seconds_until_utc_midnight() -> int:
    now = datetime.now(timezone.utc)
    tomorrow = now.date().toordinal() + 1
    next_midnight = datetime.fromordinal(tomorrow).replace(tzinfo=timezone.utc)
    return max(1, int((next_midnight - now).total_seconds()))


def estimate_tokens(text: str) -> int:
    if not text:
        return 0
    return max(1, math.ceil(len(text) / 4))


def credits_cost(tokens_in: int, tokens_out: int, provider: str, feature: str) -> int:
    base = math.ceil((tokens_in + tokens_out) / 100)
    provider_mul = PROVIDER_MULTIPLIERS.get(provider, 1.0)
    feature_mul = FEATURE_MULTIPLIERS.get(feature, 1.0)
    return max(1, math.ceil(base * provider_mul * feature_mul))


def normalize_plan_tier(plan_tier: str) -> str:
    tier = (plan_tier or "free").lower()
    return PLAN_ALIASES.get(tier, tier)


def resolve_plan_limit(plan_tier: str) -> int:
    tier = normalize_plan_tier(plan_tier)
    return PLAN_DAILY_LIMITS.get(tier, PLAN_DAILY_LIMITS["free"])


def parse_bool(value: Optional[str]) -> bool:
    if value is None:
        return False
    return value.strip().lower() in {"1", "true", "yes", "y", "on"}


def calculate_free_bonus(screen_time_opt_in: bool, notifications_opt_in: bool) -> Dict[str, int]:
    screen_time = BONUS_SCREEN_TIME if screen_time_opt_in else 0
    notifications = BONUS_NOTIFICATIONS if notifications_opt_in else 0
    total = screen_time + notifications
    return {
        "screen_time": screen_time,
        "notifications": notifications,
        "total": total,
        "max_daily": FREE_DAILY_MAX,
    }


def apply_free_plan_bonuses(base_limit: int, bonus_total: int) -> int:
    return min(base_limit + bonus_total, FREE_DAILY_MAX)


def resolve_provider(requested_provider: Optional[str], plan_tier: str) -> str:
    provider = (requested_provider or "deepseek").lower()
    if provider not in {"deepseek", "openai"}:
        provider = "deepseek"
    tier = normalize_plan_tier(plan_tier)
    if provider == "openai" and tier not in OPENAI_ALLOWED_PLANS:
        return "deepseek"
    return provider


def extract_text_for_feature(feature: str, payload: Dict[str, Any]) -> str:
    parts: list[str] = []
    if feature == "chat":
        parts.append(payload.get("user_message") or "")
        parts.append(payload.get("condensed_notes") or "")
        parts.append(payload.get("system_instruction") or "")
        for msg in payload.get("chat_history", []) or []:
            if isinstance(msg, dict):
                parts.append(msg.get("message") or "")
    elif feature in {"quiz", "flashcards"}:
        parts.append(payload.get("context") or "")
        for msg in payload.get("chat_history", []) or []:
            if isinstance(msg, dict):
                parts.append(msg.get("message") or "")
    elif feature == "ingest":
        parts.append(payload.get("content") or "")
    else:
        parts.append(json.dumps(payload))
    return " ".join([p for p in parts if p])


def resolve_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    if request.client:
        return request.client.host
    return "0.0.0.0"


class AIGuard:
    def __init__(self, redis: Redis, lua_sha: str):
        self.redis = redis
        self.lua_sha = lua_sha

    async def check_and_consume(
        self,
        user_id: str,
        org_id: Optional[str],
        ip: str,
        device_id: Optional[str],
        provider: str,
        feature: str,
        tokens_in: int,
        tokens_out: int,
        user_daily_limit: int,
        org_daily_limit: int,
        ip_rpm_limit: int = IP_RPM_LIMIT,
        device_rpm_limit: int = DEVICE_RPM_LIMIT,
        burst_cap: int = BURST_CAP,
        burst_refill_per_sec: float = BURST_REFILL_PER_SEC,
    ) -> Dict[str, Any]:
        credits = credits_cost(tokens_in, tokens_out, provider, feature)

        today = yyyymmdd_utc()
        minute = minute_bucket_utc()
        day_ttl = seconds_until_utc_midnight()

        ip_key = f"rate:ip:{ip}:{minute}"
        device_key = f"rate:device:{device_id}:{minute}" if device_id else ""
        user_quota_key = f"quota:user:{user_id}:{today}"
        org_quota_key = f"quota:org:{org_id}:{today}" if org_id else ""
        burst_key = f"burst:user:{user_id}"

        now_epoch = int(time.time())
        minute_ttl = 70

        try:
            res = await self.redis.evalsha(
                self.lua_sha,
                5,
                ip_key,
                device_key,
                user_quota_key,
                org_quota_key,
                burst_key,
                str(ip_rpm_limit),
                str(device_rpm_limit),
                str(user_daily_limit),
                str(org_daily_limit if org_id else 0),
                str(credits),
                str(minute_ttl),
                str(day_ttl),
                str(burst_cap),
                str(burst_refill_per_sec),
                str(now_epoch),
            )
        except NoScriptError:
            self.lua_sha = await load_ai_guard_lua(self.redis)
            res = await self.redis.evalsha(
                self.lua_sha,
                5,
                ip_key,
                device_key,
                user_quota_key,
                org_quota_key,
                burst_key,
                str(ip_rpm_limit),
                str(device_rpm_limit),
                str(user_daily_limit),
                str(org_daily_limit if org_id else 0),
                str(credits),
                str(minute_ttl),
                str(day_ttl),
                str(burst_cap),
                str(burst_refill_per_sec),
                str(now_epoch),
            )

        result = [item.decode() if isinstance(item, (bytes, bytearray)) else item for item in res]
        allowed = int(result[0]) == 1
        reason = result[1]
        used = int(result[2]) if len(result) > 2 and result[2] is not None else None

        if not allowed:
            retry_after = day_ttl if reason in ("user_quota", "org_quota") else 30
            headers = {
                "Retry-After": str(retry_after),
                "X-Quota-Resets-In": str(day_ttl),
                "X-Quota-Credits-Limit": str(user_daily_limit),
            }
            if used is not None:
                headers["X-Quota-Credits-Used"] = str(used)
            raise HTTPException(
                status_code=429,
                detail={"reason": reason, "retry_after": retry_after},
                headers=headers,
            )

        return {
            "credits": credits,
            "used": used,
            "limit": user_daily_limit,
            "resets_in": day_ttl,
            "reason": "ok",
        }


async def load_ai_guard_lua(redis: Redis) -> str:
    lua_path = Path(__file__).with_name("ai_guard.lua")
    script = lua_path.read_text(encoding="utf-8")
    return await redis.script_load(script)


async def init_ai_guard(app) -> None:
    if not AI_GUARD_ENABLED:
        app.state.ai_guard = None
        return
    if not REDIS_URL:
        raise RuntimeError("AI_GUARD_ENABLED is true but REDIS_URL is not set.")
    redis = Redis.from_url(REDIS_URL, encoding="utf-8", decode_responses=False)
    lua_sha = await load_ai_guard_lua(redis)
    app.state.ai_guard = AIGuard(redis, lua_sha)


async def ai_guard_dependency(request: Request, response: Response) -> None:
    guard: Optional[AIGuard] = getattr(request.app.state, "ai_guard", None)
    if guard is None:
        return

    feature = AI_GUARD_PATH_FEATURES.get(request.url.path)
    if not feature:
        return

    content_type = request.headers.get("content-type", "")
    payload: Dict[str, Any] = {}
    if "application/json" in content_type:
        try:
            body_bytes = await request.body()
            if body_bytes:
                payload = json.loads(body_bytes.decode("utf-8"))
        except Exception:
            payload = {}

    requested_provider = (
        (payload.get("ai_provider") if isinstance(payload, dict) else None)
        or request.headers.get("x-ai-provider")
        or "deepseek"
    )

    text = ""
    tokens_in = 0
    if payload:
        text = extract_text_for_feature(feature, payload)
        tokens_in = estimate_tokens(text)
    else:
        length = int(request.headers.get("content-length", "0") or 0)
        if length:
            tokens_in = estimate_tokens("x" * min(length, 4000))

    tokens_out = DEFAULT_OUT_TOKENS.get(feature, 400)

    ip = resolve_ip(request)
    device_id = request.headers.get("x-device-id")
    user_id = request.headers.get("x-user-id") or f"anon:{ip}"
    org_id = request.headers.get("x-org-id") or request.headers.get("x-classroom-id")
    plan_tier = (request.headers.get("x-plan-tier") or "free").lower()
    screen_time_opt_in = parse_bool(request.headers.get("x-screen-time-opt-in"))
    notifications_opt_in = parse_bool(request.headers.get("x-notifications-opt-in"))
    provider = resolve_provider(requested_provider, plan_tier)

    user_daily_limit = resolve_plan_limit(plan_tier)
    free_bonus = None
    if normalize_plan_tier(plan_tier) == "free":
        free_bonus = calculate_free_bonus(screen_time_opt_in, notifications_opt_in)
        user_daily_limit = apply_free_plan_bonuses(user_daily_limit, free_bonus["total"])
    org_daily_limit = PLAN_DAILY_LIMITS["classroom"] if org_id else 0

    guard_result = await guard.check_and_consume(
        user_id=user_id,
        org_id=org_id,
        ip=ip,
        device_id=device_id,
        provider=provider,
        feature=feature,
        tokens_in=tokens_in,
        tokens_out=tokens_out,
        user_daily_limit=user_daily_limit,
        org_daily_limit=org_daily_limit,
    )

    response.headers["X-Quota-Credits-Used"] = str(guard_result.get("used") or 0)
    response.headers["X-Quota-Credits-Limit"] = str(guard_result["limit"])
    response.headers["X-Quota-Resets-In"] = str(guard_result["resets_in"])

    request.state.ai_guard_meta = {
        "user_id": user_id,
        "device_id": device_id,
        "org_id": org_id,
        "provider": provider,
        "plan_tier": normalize_plan_tier(plan_tier),
        "screen_time_opt_in": screen_time_opt_in,
        "notifications_opt_in": notifications_opt_in,
        "bonus_credits": free_bonus,
        "feature": feature,
        "tokens_in": tokens_in,
        "tokens_out": tokens_out,
        "credits": guard_result["credits"],
        "path": request.url.path,
    }


async def read_quota(
    redis: Redis,
    user_id: str,
    org_id: Optional[str],
    plan_tier: str,
    screen_time_opt_in: bool = False,
    notifications_opt_in: bool = False,
) -> Dict[str, Any]:
    today = yyyymmdd_utc()
    user_key = f"quota:user:{user_id}:{today}"
    used = int(await redis.get(user_key) or 0)
    limit = resolve_plan_limit(plan_tier)
    bonus_credits = None
    if normalize_plan_tier(plan_tier) == "free":
        bonus_credits = calculate_free_bonus(screen_time_opt_in, notifications_opt_in)
        limit = apply_free_plan_bonuses(limit, bonus_credits["total"])
    resets_in = seconds_until_utc_midnight()

    org_obj = None
    if org_id:
        org_key = f"quota:org:{org_id}:{today}"
        org_used = int(await redis.get(org_key) or 0)
        org_limit = PLAN_DAILY_LIMITS["classroom"]
        org_obj = {"credits_used": org_used, "credits_limit": org_limit}

    return {
        "credits_used": used,
        "credits_limit": limit,
        "resets_in_sec": resets_in,
        "plan_tier": plan_tier,
        "bonus_credits": bonus_credits,
        "org": org_obj,
    }


def init_ai_guard_ledger(app) -> None:
    if not LEDGER_ENABLED:
        app.state.ledger_engine = None
        app.state.ledger_table = None
        return
    engine = create_engine(LEDGER_DB_URL, future=True)
    LEDGER_METADATA.create_all(engine)
    app.state.ledger_engine = engine
    app.state.ledger_table = LEDGER_TABLE


async def record_ai_usage(app, meta: Dict[str, Any], status: int) -> None:
    engine = getattr(app.state, "ledger_engine", None)
    table = getattr(app.state, "ledger_table", None)
    if engine is None or table is None:
        return
    payload = {
        "user_id": meta.get("user_id"),
        "device_id": meta.get("device_id"),
        "org_id": meta.get("org_id"),
        "provider": meta.get("provider"),
        "feature": meta.get("feature"),
        "tokens_in": int(meta.get("tokens_in") or 0),
        "tokens_out": int(meta.get("tokens_out") or 0),
        "credits": int(meta.get("credits") or 0),
        "path": meta.get("path"),
        "status": int(status),
    }

    def _insert() -> None:
        with engine.begin() as conn:
            conn.execute(table.insert().values(**payload))

    await run_in_threadpool(_insert)
