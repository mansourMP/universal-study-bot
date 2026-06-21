"""
Learning Path 2.0 - Brain API Router
Technical Memo v1.1 - Phase 5 (Unified)

FastAPI router for /api/v2/brain/* endpoints with:
- Intent-based Mission Generation (Hard Contract enforced)
- Idempotent submit
- Slot validation
- Stage completion tracking
- Delayed recall enforcement
"""

from fastapi import APIRouter, HTTPException, Depends
from auth import get_user_id
from pydantic import BaseModel, Field, field_validator
from typing import List, Optional, Dict, Any, Literal, Set, Tuple
import sqlite3
import json
import uuid
import hashlib
import math
import re
from collections import Counter
from datetime import datetime, timedelta
from pathlib import Path

from .schema import (
    init_database,
    STATE_PRACTICING, STATE_MASTERED_PENDING, STATE_MASTERED,
    STATE_LEARNING
)
from .srs_plan import (
    MasteryVector, get_srs_plan, SKILL_TO_TYPES, FOCUS_TO_SKILL,
    make_slot_key, make_plan_slot_id, parse_plan_slot_id, get_interval_hours
)
from .skill_updates import (
    compute_skill_delta, update_skill_score, is_mastery_criteria_met,
    can_transition_to_mastered
)
from .stage_completion import (
    create_review_instance, get_active_review_instance
)
from .brain_selector import create_selector, BrainSelector
from .sense_store import get_primary_gloss, get_sense_payload, get_senses
from .knowledge_policy import (
    recent_knowledge_signal as _recent_knowledge_signal,
    prioritize_candidates_by_knowledge as _prioritize_candidates_by_knowledge,
)


router = APIRouter(prefix="/api/v2/brain", tags=["brain"])


# ============================================================
# DAILY ADAPTIVE LOAD POLICY (Backlog Guardrail)
# ============================================================

# If due backlog is this high, block new words and run review-only.
DAILY_DUE_REVIEW_ONLY_THRESHOLD = 50
# If due backlog is moderately high, sharply reduce new words.
DAILY_DUE_REDUCED_NEW_THRESHOLD = 20
# In normal mode, daily missions should still cap "new" to stay sustainable.
DAILY_NEW_CAP_NORMAL = 5
# In reduced mode, keep minimal new exposure while paying down backlog.
DAILY_NEW_CAP_REDUCED = 2
# Daily hard-due capacity target used for backlog ratio.
DAILY_REVIEW_CAP_WORDS = 60
# Hard-due / capacity >= 1.0 -> review only.
DAILY_BACKLOG_REVIEW_ONLY_RATIO = 1.0
# Hard-due / capacity >= 0.6 -> reduced new words.
DAILY_BACKLOG_REDUCED_RATIO = 0.6
TOO_FAST_BASE_MS = 900
TOO_FAST_STREAK_MIN = 4


# ============================================================
# REQUEST/RESPONSE MODELS
# ============================================================

class MissionRequest(BaseModel):
    language_code: str = "zh"
    intent: Literal["daily", "review", "learn", "drill"] = "daily"
    limit: int = 8
    forced_ids: Optional[List[str]] = Field(None, max_length=64)  # Abuse guard: cap at 64
    allowed_word_ids: Optional[List[str]] = Field(None, max_length=64)  # Optional hard scope whitelist
    node_id: Optional[str] = None           # Path node ID context
    unit_id: Optional[str] = None           # Contextual unit ID
    focus_dimension: Optional[Literal["recognition", "listening", "production", "usage"]] = None
    daily_new_target: Optional[int] = Field(default=None, ge=0, le=20)
    target_min_seconds: Optional[int] = Field(default=None, ge=120, le=1800)
    target_max_seconds: Optional[int] = Field(default=None, ge=240, le=2400)


class ExerciseItem(BaseModel):
    exercise_id: str
    word_id: str
    sense_id: Optional[str] = None
    type: str
    difficulty: int
    skill_focus: str
    stage: int
    review_instance_id: str
    slot_key: str
    plan_slot_id: str
    payload: Dict[str, Any] = Field(default_factory=dict)
    
    # Debug/Analytics
    selected_by: Optional[str] = None 


class ExercisesResponse(BaseModel):
    mission_id: str
    exercises: List[ExerciseItem]
    policy_version: str = "v2.0"
    metadata: Dict[str, Any] = Field(default_factory=dict)


class SubmitRequest(BaseModel):
    user_id: str
    language_code: str
    mission_id: str
    exercise_id: str
    word_id: str
    sense_id: Optional[str] = None
    plan_slot_id: str
    is_correct: bool
    latency_ms: Optional[int] = None
    idempotency_key: Optional[str] = None
    attempt_meta: Optional[Dict[str, Any]] = None


class SubmitResponse(BaseModel):
    accepted: bool
    idempotent_hit: bool = False
    skill_updated: Optional[str] = None
    skill_score: Optional[int] = None
    skill_display: Optional[int] = None
    mastery_state: Optional[str] = None
    stage_complete: bool = False
    new_stage: Optional[int] = None
    slots_remaining: List[str] = Field(default_factory=list)
    next_review_at: Optional[str] = None
    next_action: str = "continue"
    mastery_gate_passed: Optional[bool] = None
    mastery_gate_reasons: Optional[List[str]] = None
    feedback_flags: Dict[str, Any] = Field(default_factory=dict)

    @field_validator("mastery_state", mode="before")
    @classmethod
    def _coerce_mastery_state(cls, value: Any) -> Optional[str]:
        if value is None:
            return None
        if isinstance(value, str):
            return value
        return str(value)


class BrainSummary(BaseModel):
    due_count: int
    review_due_count: int
    hard_due_count: int = 0
    soft_due_count: int = 0
    learn_available_count: int
    next_review_at: Optional[str]
    has_active_mission: bool
    server_time: str


class UnitIntroResponse(BaseModel):
    unit_id: str
    audio_url: str
    script_hanzi: str
    script_pinyin: str
    translation: str
    target_words: List[str]


# ============================================================
# DATABASE CONNECTION
# ============================================================

_db_conn: Optional[sqlite3.Connection] = None
_hsk1_unit_circle_pack_cache: Optional[Dict[str, Any]] = None
_hsk1_unit_001_gold_cache: Optional[Dict[str, Any]] = None
_hsk1_unit_001_dynamic_pool_cache: Optional[Dict[str, Any]] = None
_HSK1_NODE_ID_RE = re.compile(r"^(UNIT_HSK1_\d{3})_L(\d{1,2})$")
_HSK1_UNIT_ID_RE = re.compile(r"^UNIT_HSK1_(\d{3})$")
_HSK1_CIRCLE_IDS = ("C1", "C2", "C3", "C4", "C5", "C6", "C7")
_HSK1_INTRO_CIRCLE_IDS = {"C1", "C2", "C3", "C4", "C5"}
_HSK1_REVIEW_CIRCLE_IDS = {"C6", "C7"}
_SCOPE_VERSION_HSK1_LEARN_V1 = "hsk1_learn_scope_v1"

def get_db() -> sqlite3.Connection:
    global _db_conn
    if _db_conn is None:
        from pathlib import Path
        db_path = Path(__file__).parent.parent / "learning_path.db"
        _db_conn = init_database(db_path)
    return _db_conn


def _load_hsk1_unit_circle_pack() -> Optional[Dict[str, Any]]:
    global _hsk1_unit_circle_pack_cache
    if _hsk1_unit_circle_pack_cache is not None:
        return _hsk1_unit_circle_pack_cache
    pack_path = Path(__file__).resolve().parents[2] / "docs" / "specs" / "hsk1_unit_circle_pack_v1.json"
    if not pack_path.exists():
        return None
    try:
        _hsk1_unit_circle_pack_cache = json.loads(pack_path.read_text(encoding="utf-8"))
    except Exception:
        _hsk1_unit_circle_pack_cache = None
    return _hsk1_unit_circle_pack_cache


def _load_hsk1_unit_001_gold() -> Optional[Dict[str, Any]]:
    global _hsk1_unit_001_gold_cache
    if _hsk1_unit_001_gold_cache is not None:
        return _hsk1_unit_001_gold_cache
    gold_path = Path(__file__).resolve().parents[2] / "docs" / "specs" / "hsk1_unit_001_gold_v1.json"
    if not gold_path.exists():
        return None
    try:
        _hsk1_unit_001_gold_cache = json.loads(gold_path.read_text(encoding="utf-8"))
    except Exception:
        _hsk1_unit_001_gold_cache = None
    return _hsk1_unit_001_gold_cache


def _load_hsk1_unit_001_dynamic_pool() -> Optional[Dict[str, Any]]:
    global _hsk1_unit_001_dynamic_pool_cache
    if _hsk1_unit_001_dynamic_pool_cache is not None:
        return _hsk1_unit_001_dynamic_pool_cache
    pool_path = Path(__file__).resolve().parents[2] / "docs" / "specs" / "hsk1_unit_001_dynamic_pool_v1.json"
    if not pool_path.exists():
        return None
    try:
        _hsk1_unit_001_dynamic_pool_cache = json.loads(pool_path.read_text(encoding="utf-8"))
    except Exception:
        _hsk1_unit_001_dynamic_pool_cache = None
    return _hsk1_unit_001_dynamic_pool_cache


def _resolve_hsk1_node_circle(
    node_id: Optional[str],
    unit_id: Optional[str],
) -> tuple[Optional[str], Optional[str]]:
    if node_id:
        raw = str(node_id).strip()
        match = _HSK1_NODE_ID_RE.match(raw)
        if match:
            parsed_unit = match.group(1)
            lesson_idx = int(match.group(2))
            if 1 <= lesson_idx <= len(_HSK1_CIRCLE_IDS):
                return parsed_unit, _HSK1_CIRCLE_IDS[lesson_idx - 1]
            return parsed_unit, None
    if unit_id and str(unit_id).startswith("UNIT_HSK1_"):
        return str(unit_id), _HSK1_CIRCLE_IDS[0]
    return None, None


def _rotating_subset(items: List[str], count: int, seed_key: str) -> List[str]:
    if count <= 0 or not items:
        return []
    if count >= len(items):
        return list(items)
    offset = _stable_hash(seed_key, len(items)) % len(items)
    out: List[str] = []
    for i in range(count):
        out.append(items[(offset + i) % len(items)])
    return out


def _normalize_word_id_list(raw_values: Optional[List[Any]], max_items: int = 64) -> List[str]:
    if not raw_values:
        return []
    out: List[str] = []
    seen: Set[str] = set()
    for value in raw_values:
        text = str(value).strip()
        if not text or text in seen:
            continue
        out.append(text)
        seen.add(text)
        if len(out) >= max_items:
            break
    return out


def _hsk1_previous_unit_id(unit_id: Optional[str]) -> Optional[str]:
    if not unit_id:
        return None
    match = _HSK1_UNIT_ID_RE.match(str(unit_id).strip())
    if not match:
        return None
    current = int(match.group(1))
    if current <= 1:
        return None
    return f"UNIT_HSK1_{current - 1:03d}"


def _hsk1_introduced_words_for_unit(unit_id: Optional[str]) -> List[str]:
    if not unit_id:
        return []
    circle = _resolve_hsk1_pack_circle(
        node_id=f"{unit_id}_L01",
        unit_id=unit_id,
    )
    if not circle:
        return []
    return _normalize_word_id_list(circle.get("introduced_word_ids"))


def _resolve_hsk1_pack_circle(
    node_id: Optional[str],
    unit_id: Optional[str],
) -> Optional[Dict[str, Any]]:
    parsed_unit_id, circle_id = _resolve_hsk1_node_circle(node_id, unit_id)
    if not parsed_unit_id or not circle_id:
        return None

    unit_payload: Optional[Dict[str, Any]] = None
    if parsed_unit_id == "UNIT_HSK1_001":
        # Keep mission resolver aligned with journey resolver for Unit 1 pilot.
        gold = _load_hsk1_unit_001_gold()
        if isinstance(gold, dict):
            maybe_unit = gold.get("unit")
            if isinstance(maybe_unit, dict):
                unit_payload = maybe_unit
    if unit_payload is None:
        pack = _load_hsk1_unit_circle_pack()
        if not pack:
            return None
        units = pack.get("units", [])
        if not isinstance(units, list):
            return None
        for unit in units:
            if not isinstance(unit, dict):
                continue
            if str(unit.get("unit_id") or "") == parsed_unit_id:
                unit_payload = unit
                break
    if not unit_payload:
        return None

    circles = unit_payload.get("circles", [])
    if not isinstance(circles, list):
        return None
    introduced_word_ids: Set[str] = set()
    introduced_until_circle_word_ids: List[str] = []
    progressive_seen: Set[str] = set()
    progressive_open = True
    for c in circles:
        if not isinstance(c, dict):
            continue
        cid = str(c.get("circle_id") or "")
        if cid in _HSK1_INTRO_CIRCLE_IDS:
            focus_words = [str(w).strip() for w in (c.get("focus_word_ids") or [])]
            for swid in focus_words:
                if swid:
                    introduced_word_ids.add(swid)
            if progressive_open:
                for swid in focus_words:
                    if swid and swid not in progressive_seen:
                        introduced_until_circle_word_ids.append(swid)
                        progressive_seen.add(swid)
        if cid == circle_id:
            progressive_open = False

    for circle in circles:
        if not isinstance(circle, dict):
            continue
        if str(circle.get("circle_id") or "") != circle_id:
            continue
        raw_focus_word_ids = [
            str(w) for w in (circle.get("focus_word_ids") or []) if str(w).strip()
        ]
        # Hard guard: C6/C7 are review/checkpoint circles; keep them within taught unit scope.
        if circle_id in _HSK1_REVIEW_CIRCLE_IDS and introduced_word_ids:
            focus_word_ids = [w for w in raw_focus_word_ids if w in introduced_word_ids]
            if not focus_word_ids:
                # Safe fallback to introduced words if source data is malformed.
                focus_word_ids = sorted(introduced_word_ids)
        else:
            focus_word_ids = raw_focus_word_ids

        target_exercise_count = int(circle.get("target_exercise_count") or 5)
        # Keep intended circle runtime length (e.g., 10-12 items), even if focus words are fewer.
        target_exercise_count = max(1, target_exercise_count)
        candidate_pool_size = int(circle.get("candidate_pool_size") or len(focus_word_ids))
        target_word_count = int(circle.get("target_word_count") or 0)
        if target_word_count <= 0:
            target_word_count = (
                min(len(focus_word_ids), max(4, int(round(len(focus_word_ids) * 0.6))))
                if focus_word_ids
                else 1
            )
        target_word_count = max(1, min(target_word_count, len(focus_word_ids) or 1))

        exercise_mix = dict(circle.get("exercise_mix") or {})
        if parsed_unit_id == "UNIT_HSK1_001":
            # Unit-1 pilot rich mix (closer to intended C1-C7 pedagogy).
            override_mix: Dict[str, Dict[str, int]] = {
                "C1": {"meaning_select": 3, "audio_select": 2, "character_select": 2, "order_sentence": 3},
                "C2": {"audio_select": 3, "character_select": 2, "order_sentence": 3, "reading_micro": 2},
                "C3": {"speak_read_aloud": 4, "speak_prompted_reply": 3, "audio_select": 1, "character_select": 1, "order_sentence": 1},
                "C4": {"meaning_select": 3, "audio_select": 2, "character_select": 2, "order_sentence": 3},
                "C5": {"audio_select": 2, "character_select": 2, "order_sentence": 3, "reading_micro": 2, "meaning_select": 1},
                "C6": {"reading_micro": 3, "audio_select": 3, "order_sentence": 3, "character_select": 1, "meaning_select": 2},
                "C7": {"audio_select": 3, "reading_micro": 3, "order_sentence": 3, "speak_prompted_reply": 2, "character_select": 1},
            }
        if circle_id in override_mix:
            exercise_mix = override_mix[circle_id]
            target_exercise_count = max(target_exercise_count, sum(exercise_mix.values()))

        serve_min: Optional[int] = None
        serve_target: Optional[int] = None
        serve_cap: Optional[int] = None
        serve_cap_normal: Optional[int] = None
        serve_cap_struggle: Optional[int] = None
        if parsed_unit_id == "UNIT_HSK1_001":
            dynamic_pool = _load_hsk1_unit_001_dynamic_pool()
            if isinstance(dynamic_pool, dict):
                defaults = dynamic_pool.get("run_defaults", {}) or {}
                circles_cfg = dynamic_pool.get("circles", []) or []
                dyn_circle = None
                for c in circles_cfg:
                    if isinstance(c, dict) and str(c.get("circle_id") or "") == circle_id:
                        dyn_circle = c
                        break
                runtime = (dyn_circle or {}).get("runtime_serving", {}) or {}
                pool_cfg = (dyn_circle or {}).get("pool", {}) or {}
                serve_min = int(runtime.get("serve_min") or defaults.get("serve_min") or 10)
                serve_target = int(runtime.get("serve_target") or defaults.get("serve_target") or target_exercise_count)
                serve_cap = int(runtime.get("serve_cap") or defaults.get("serve_cap_normal") or serve_target)
                serve_cap_normal = int(defaults.get("serve_cap_normal") or serve_cap)
                serve_cap_struggle = int(defaults.get("serve_cap_struggle") or serve_cap)
                target_exercise_count = max(target_exercise_count, serve_target)
                candidate_pool_size = int(
                    pool_cfg.get("candidate_pool_size")
                    or candidate_pool_size
                    or len(focus_word_ids)
                    or target_exercise_count
                )

        return {
            "unit_id": parsed_unit_id,
            "unit_title": str(unit_payload.get("title") or ""),
            "circle_id": circle_id,
            "circle_title": str(circle.get("title") or ""),
            "duration_target_sec": int(circle.get("duration_target_sec") or 240),
            "target_exercise_count": target_exercise_count,
            "candidate_pool_size": candidate_pool_size,
            "target_word_count": target_word_count,
            "exercise_mix": exercise_mix,
            "on_fail": dict(circle.get("on_fail") or {}),
            "focus_word_ids": focus_word_ids,
            "focus_sense_ids": [str(s) for s in (circle.get("focus_sense_ids") or []) if str(s).strip()],
            "filtered_for_review_only": circle_id in _HSK1_REVIEW_CIRCLE_IDS,
            "introduced_scope_size": len(introduced_word_ids),
            "introduced_word_ids": sorted(introduced_word_ids),
            "introduced_until_circle_word_ids": introduced_until_circle_word_ids,
            "serve_min": serve_min,
            "serve_target": serve_target,
            "serve_cap": serve_cap,
            "serve_cap_normal": serve_cap_normal,
            "serve_cap_struggle": serve_cap_struggle,
        }
    return None


def _selected_by_value(value: Any) -> Optional[str]:
    if value is None:
        return None
    if hasattr(value, "value"):
        return str(value.value)
    return str(value)


def _stable_hash(*parts: Any) -> int:
    raw = "::".join(str(p) for p in parts)
    return int(hashlib.md5(raw.encode("utf-8")).hexdigest()[:8], 16)


def _parse_sqlite_datetime(value: Any) -> Optional[datetime]:
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    try:
        return datetime.fromisoformat(text.replace(" ", "T"))
    except ValueError:
        return None


def _normalize_mastery_state_value(value: Any) -> str:
    """Normalize legacy/mastery-state variants to canonical enum strings."""
    raw = str(value if value is not None else "").strip()
    if raw == "" or raw.upper() == "UNKNOWN":
        return STATE_LEARNING
    normalized = raw.upper()
    if normalized in {STATE_LEARNING, STATE_PRACTICING, STATE_MASTERED_PENDING, STATE_MASTERED}:
        return normalized
    if normalized in {"0", "1"}:
        return STATE_LEARNING
    if normalized == "2":
        return STATE_PRACTICING
    if normalized == "3":
        return STATE_MASTERED_PENDING
    if normalized == "4":
        return STATE_MASTERED
    return STATE_LEARNING


def _hard_due_grace_hours(stage: int) -> int:
    """
    Grace window after ideal_due (next_review_at).
    clamp(1 day, 4 days, round(interval * 0.35))
    """
    interval_hours = get_interval_hours(stage, is_correct=True)
    return max(24, min(96, int(round(interval_hours * 0.35))))


def _count_due_reviews(
    conn: sqlite3.Connection,
    user_id: str,
    language_code: str,
    unit_id: Optional[str] = None,
) -> Dict[str, int]:
    unit_clause = ""
    params: list[Any] = [user_id, language_code]
    if unit_id:
        unit_clause = "AND uwm.word_id IN (SELECT concept_id FROM unit_concepts WHERE unit_id = ?)"
        params.append(unit_id)
    rows = conn.execute(
        f"""
        SELECT uwm.srs_stage, uwm.next_review_at
        FROM user_word_mastery uwm
        WHERE uwm.user_id = ?
          AND uwm.language_code = ?
          AND EXISTS (SELECT 1 FROM concepts c WHERE c.id = uwm.word_id)
          AND uwm.next_review_at <= datetime('now')
          {unit_clause}
        """,
        params,
    ).fetchall()
    now_utc = datetime.utcnow()
    hard_due_count = 0
    soft_due_count = 0
    due_count = 0

    for row in rows:
        due_count += 1
        stage = int(row[0] or 0)
        next_review_at = _parse_sqlite_datetime(row[1])
        if next_review_at is None:
            # Corrupt/empty timestamp: treat as urgent hard due.
            hard_due_count += 1
            continue
        grace_hours = _hard_due_grace_hours(stage)
        hard_cutoff = next_review_at + timedelta(hours=grace_hours)
        if now_utc >= hard_cutoff:
            hard_due_count += 1
        else:
            soft_due_count += 1

    return {
        "due_count": due_count,
        "hard_due_count": hard_due_count,
        "soft_due_count": soft_due_count,
    }


def _recent_seen_words_for_scope(
    conn: sqlite3.Connection,
    user_id: str,
    language_code: str,
    scope_word_ids: List[str],
    lookback_hours: int = 24,
) -> Set[str]:
    """
    Return scope words that user has attempted recently.
    Used to keep C6/C7 review circles constrained to actually-seen words.
    """
    normalized = [str(w).strip() for w in scope_word_ids if str(w).strip()]
    if not normalized:
        return set()
    placeholders = ",".join("?" for _ in normalized)
    rows = conn.execute(
        f"""
        SELECT DISTINCT ua.word_id
        FROM user_attempts ua
        WHERE ua.user_id = ?
          AND ua.language_code = ?
          AND ua.word_id IN ({placeholders})
          AND ua.created_at >= datetime('now', '-' || ? || ' hours')
        """,
        [user_id, language_code, *normalized, lookback_hours],
    ).fetchall()
    return {str(r[0]) for r in rows if r and r[0]}


def _daily_budget_policy(
    mission_limit: int,
    due_status: Dict[str, int],
    requested_new_target: Optional[int] = None,
) -> Dict[str, Any]:
    due_count = int(due_status.get("due_count", 0))
    hard_due_count = int(due_status.get("hard_due_count", 0))
    soft_due_count = int(due_status.get("soft_due_count", 0))
    review_capacity_words = DAILY_REVIEW_CAP_WORDS
    backlog_ratio = hard_due_count / max(1, review_capacity_words)

    # Default target by mission size, then apply hard caps.
    base_target = max(1, min(10, int(math.ceil(mission_limit * 0.35))))
    if requested_new_target is not None:
        base_target = max(0, min(20, int(requested_new_target)))

    mode_reason = "balanced_daily_mix"
    if (
        backlog_ratio >= DAILY_BACKLOG_REVIEW_ONLY_RATIO
        or hard_due_count >= DAILY_DUE_REVIEW_ONLY_THRESHOLD
    ):
        mode_reason = "hard_due_backlog_over_capacity"
        return {
            "mode": "review_only",
            "max_new": 0,
            "max_review": mission_limit,
            "due_count": due_count,
            "hard_due_count": hard_due_count,
            "soft_due_count": soft_due_count,
            "backlog_ratio": round(backlog_ratio, 4),
            "review_capacity_words": review_capacity_words,
            "mode_reason": mode_reason,
        }

    if (
        backlog_ratio >= DAILY_BACKLOG_REDUCED_RATIO
        or hard_due_count >= DAILY_DUE_REDUCED_NEW_THRESHOLD
    ):
        reduced_new = min(DAILY_NEW_CAP_REDUCED, base_target)
        mode_reason = "hard_due_backlog_rising"
        return {
            "mode": "reduced_new",
            "max_new": reduced_new,
            "max_review": mission_limit,
            "due_count": due_count,
            "hard_due_count": hard_due_count,
            "soft_due_count": soft_due_count,
            "backlog_ratio": round(backlog_ratio, 4),
            "review_capacity_words": review_capacity_words,
            "mode_reason": mode_reason,
        }

    normal_new = min(DAILY_NEW_CAP_NORMAL, base_target)
    if soft_due_count > review_capacity_words * 2:
        # Keep growth, but lightly dampen when soft-due debt is large.
        normal_new = max(0, normal_new - 1)
        mode_reason = "soft_due_backlog_dampening"

    return {
        "mode": "normal",
        "max_new": normal_new,
        "max_review": mission_limit,
        "due_count": due_count,
        "hard_due_count": hard_due_count,
        "soft_due_count": soft_due_count,
        "backlog_ratio": round(backlog_ratio, 4),
        "review_capacity_words": review_capacity_words,
        "mode_reason": mode_reason,
    }


def _modality_for_type(ex_type: str) -> str:
    ex_type = (ex_type or "").lower()
    if ex_type in {"audio_select", "audio_match", "dictation_select", "tone_select"}:
        return "listening"
    if ex_type in {
        "order_sentence",
        "character_select",
        "pinyin_type",
        "speaking",
        "speak_read_aloud",
        "speak_prompted_reply",
        "sentence_fill",
        "collocation_pick",
    }:
        return "production"
    if ex_type in {"reading_micro"}:
        return "usage"
    if ex_type in {"flashcard", "meaning_select"}:
        return "recognition"
    return "other"


def _recent_retry_profile(
    conn: sqlite3.Connection,
    user_id: str,
    language_code: str,
    lookback_hours: int = 72,
    limit_words: int = 600,
) -> Dict[str, Dict[str, Any]]:
    """
    Build retry profile from recent failed attempts.
    Used to avoid repeating the same exercise type on retries.
    """
    rows = conn.execute(
        """
        SELECT
            ua.word_id,
            COUNT(*) AS fail_count,
            MAX(ua.created_at) AS last_failed_at,
            GROUP_CONCAT(
                DISTINCT COALESCE(
                    we.exercise_type,
                    CASE
                        WHEN ua.exercise_id LIKE 'auto_usage_%' THEN 'order_sentence'
                        WHEN ua.exercise_id LIKE 'auto_recog_%' THEN 'meaning_select'
                        WHEN ua.exercise_id LIKE 'auto_listen_%' THEN 'audio_select'
                        WHEN ua.exercise_id LIKE 'auto_prod_%' THEN 'character_select'
                        WHEN ua.exercise_id LIKE 'fallback_%' THEN 'flashcard'
                        ELSE ''
                    END
                )
            ) AS failed_types_csv
        FROM user_attempts ua
        LEFT JOIN word_exercises we ON we.id = ua.exercise_id
        WHERE ua.user_id = ?
          AND ua.language_code = ?
          AND ua.is_correct = 0
          AND ua.created_at >= datetime('now', '-' || ? || ' hours')
        GROUP BY ua.word_id
        ORDER BY fail_count DESC, last_failed_at DESC
        LIMIT ?
        """,
        [user_id, language_code, lookback_hours, limit_words],
    ).fetchall()

    profile: Dict[str, Dict[str, Any]] = {}
    for row in rows:
        failed_types: Set[str] = set()
        csv_value = row[3] if len(row) > 3 else None
        if csv_value:
            for raw in str(csv_value).split(","):
                token = raw.strip()
                if token:
                    failed_types.add(token)
        profile[str(row[0])] = {
            "fail_count": int(row[1] or 0),
            "last_failed_at": row[2],
            "failed_types": failed_types,
        }
    return profile


def _recent_learning_signal(
    conn: sqlite3.Connection,
    user_id: str,
    language_code: str,
    lookback_minutes: int = 30,
) -> Dict[str, Any]:
    row = conn.execute(
        """
        SELECT
            COUNT(*) AS attempts,
            SUM(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END) AS correct,
            AVG(COALESCE(latency_ms, 0)) AS avg_latency_ms,
            SUM(CASE WHEN is_correct = 0 THEN 1 ELSE 0 END) AS failures,
            SUM(CASE WHEN COALESCE(latency_ms, 0) > 0 AND COALESCE(latency_ms, 0) < ? THEN 1 ELSE 0 END) AS too_fast
        FROM user_attempts
        WHERE user_id = ?
          AND language_code = ?
          AND created_at >= datetime('now', '-' || ? || ' minutes')
        """,
        [TOO_FAST_BASE_MS, user_id, language_code, lookback_minutes],
    ).fetchone()
    attempts = int(row[0] or 0) if row else 0
    correct = int(row[1] or 0) if row else 0
    failures = int(row[3] or 0) if row else 0
    too_fast = int(row[4] or 0) if row else 0
    avg_latency = float(row[2] or 0.0) if row else 0.0
    accuracy = (correct / attempts) if attempts > 0 else 0.0
    mode = "normal"
    reason = "insufficient_history"
    if attempts >= 6:
        if failures >= 4 or accuracy < 0.55 or avg_latency >= 9000:
            mode = "assist"
            reason = "high_difficulty_detected"
        elif accuracy >= 0.9 and 0 < avg_latency <= 2200 and too_fast <= 1:
            mode = "challenge"
            reason = "high_confidence_detected"
        else:
            mode = "normal"
            reason = "stable_progress"
    return {
        "attempts": attempts,
        "correct": correct,
        "failures": failures,
        "accuracy": round(accuracy, 4),
        "avg_latency_ms": int(round(avg_latency)) if avg_latency > 0 else 0,
        "too_fast_attempts": too_fast,
        "mode": mode,
        "mode_reason": reason,
    }


def _adapt_hsk1_target_words(
    base_target: int,
    pool_size: int,
    signal: Dict[str, Any],
    knowledge_signal: Optional[Dict[str, Any]] = None,
) -> int:
    mode = str(signal.get("mode") or "normal")
    target = max(1, min(pool_size, base_target))
    if mode == "assist":
        target = max(3, target - 1)
    elif mode == "challenge":
        target = min(pool_size, target + 1)
    if knowledge_signal:
        k_mode = str(knowledge_signal.get("mode") or "normal")
        if k_mode == "assist":
            target = max(3, target - 1)
        elif k_mode == "challenge":
            target = min(pool_size, target + 1)
    return max(1, min(pool_size, target))


def _compute_ring_slots(
    *,
    learning_signal: Dict[str, Any],
    adaptive_policy: Dict[str, Any],
    circle_id: Optional[str],
    has_review_pressure: bool,
) -> int:
    """
    Decide visible ring chunk count for a circle.
    Range: 3..8
    """
    mode = str(learning_signal.get("mode") or "normal")
    base = 6
    if mode == "assist":
        base = 4
    elif mode == "challenge":
        base = 7

    # Review/checkpoint circles can be heavier if user is stable.
    if circle_id in {"C6", "C7"}:
        base += 1

    # If backlog/review pressure is high, simplify visual load.
    backlog_ratio = float(adaptive_policy.get("backlog_ratio") or 0.0)
    hard_due = int(adaptive_policy.get("hard_due_count") or 0)
    if backlog_ratio >= 1.0 or hard_due >= DAILY_REVIEW_CAP_WORDS:
        base -= 2
    elif has_review_pressure:
        base -= 1

    return max(3, min(8, base))


def _infer_exercise_type(exercise_id: str) -> str:
    eid = str(exercise_id or "")
    if eid.startswith("auto_usage_"):
        return "order_sentence"
    if eid.startswith("auto_recog_"):
        return "meaning_select"
    if eid.startswith("auto_listen_"):
        return "audio_select"
    if eid.startswith("auto_speak_read_"):
        return "speak_read_aloud"
    if eid.startswith("auto_speak_reply_"):
        return "speak_prompted_reply"
    if eid.startswith("auto_prod_"):
        return "character_select"
    if eid.startswith("fallback_"):
        return "flashcard"
    return ""


def _too_fast_guard(
    conn: sqlite3.Connection,
    user_id: str,
    language_code: str,
    exercise_id: str,
    latency_ms: Optional[int],
) -> Dict[str, Any]:
    ex_type = conn.execute(
        "SELECT exercise_type FROM word_exercises WHERE id = ? LIMIT 1",
        [exercise_id],
    ).fetchone()
    resolved_type = str(ex_type[0]) if ex_type else _infer_exercise_type(exercise_id)
    floor_by_type = {
        "meaning_select": 900,
        "character_select": 900,
        "pinyin_select": 1100,
        "audio_select": 1000,
        "dictation_select": 1400,
        "cloze_select": 1200,
        "order_sentence": 1800,
        "reading_micro": 2200,
        "speak_read_aloud": 1400,
        "speak_prompted_reply": 1600,
        "flashcard": 600,
    }
    threshold = int(floor_by_type.get(resolved_type, TOO_FAST_BASE_MS))
    current_latency = int(latency_ms or 0)
    current_too_fast = current_latency > 0 and current_latency < threshold
    if not current_too_fast:
        return {
            "triggered": False,
            "threshold_ms": threshold,
            "streak": 0,
            "exercise_type": resolved_type,
        }
    row = conn.execute(
        """
        SELECT
            SUM(CASE WHEN COALESCE(latency_ms, 0) > 0 AND COALESCE(latency_ms, 0) < ? THEN 1 ELSE 0 END) AS too_fast
        FROM (
            SELECT latency_ms
            FROM user_attempts
            WHERE user_id = ? AND language_code = ?
            ORDER BY created_at DESC
            LIMIT 5
        )
        """,
        [threshold, user_id, language_code],
    ).fetchone()
    previous_fast = int(row[0] or 0) if row else 0
    streak = previous_fast + 1
    triggered = streak >= TOO_FAST_STREAK_MIN
    return {
        "triggered": triggered,
        "threshold_ms": threshold,
        "streak": streak,
        "exercise_type": resolved_type,
    }


def _pick_primary_with_retry_variation(
    selected_items: List["ExerciseItem"],
    failed_types: Set[str],
) -> "ExerciseItem":
    """
    Pick a primary exercise for a word with retry-aware variation:
    1) different type + listening/production
    2) different type
    3) listening/production
    4) original first
    """
    if not selected_items:
        raise ValueError("selected_items must not be empty")
    if not failed_types:
        return selected_items[0]

    for item in selected_items:
        if item.type in failed_types:
            continue
        if _modality_for_type(item.type) in {"listening", "production"}:
            return item

    for item in selected_items:
        if item.type not in failed_types:
            return item

    for item in selected_items:
        if _modality_for_type(item.type) in {"listening", "production"}:
            return item

    return selected_items[0]


def _prioritize_retry_sequence(
    selected_items: List["ExerciseItem"],
    failed_types: Set[str],
) -> List["ExerciseItem"]:
    """
    Reorder per-word sequence so retries start with variation and
    speaking-friendly modalities.
    """
    if len(selected_items) <= 1 or not failed_types:
        return selected_items

    def rank(item: "ExerciseItem") -> int:
        modality = _modality_for_type(item.type)
        if item.type not in failed_types and modality in {"listening", "production"}:
            return 0
        if item.type not in failed_types:
            return 1
        if modality in {"listening", "production"}:
            return 2
        return 3

    indexed = list(enumerate(selected_items))
    indexed.sort(key=lambda pair: (rank(pair[1]), pair[0]))
    return [item for _, item in indexed]


def _knowledge_state_for_word(word_id: str, knowledge_signal: Dict[str, Any]) -> str:
    struggling_words = set(str(w) for w in (knowledge_signal.get("top_struggling_words") or []))
    knows_words = set(str(w) for w in (knowledge_signal.get("top_knows_words") or []))
    if word_id in struggling_words:
        return "struggling"
    if word_id in knows_words:
        return "knows"
    return "neutral"


def _knowledge_type_profile(state: str) -> Tuple[List[str], Set[str]]:
    if state == "struggling":
        return (
            ["meaning_select", "audio_select", "character_select", "flashcard"],
            {
                "speak_prompted_reply",
                "speak_read_aloud",
                "order_sentence",
                "reading_micro",
                "conversation_simulation",
                "reply_select",
            },
        )
    if state == "knows":
        return (
            [
                "order_sentence",
                "reply_select",
                "conversation_simulation",
                "speak_prompted_reply",
                "speak_read_aloud",
                "reading_micro",
                "character_select",
            ],
            {"flashcard", "meaning_select", "audio_select"},
        )
    return ([], set())


def _apply_knowledge_type_bias_for_word(
    conn: sqlite3.Connection,
    items: List["ExerciseItem"],
    word_id: str,
    knowledge_signal: Dict[str, Any],
    *,
    allow_convert: bool,
) -> Tuple[List["ExerciseItem"], Dict[str, Any]]:
    if not items:
        return items, {"state": "neutral", "reordered": False, "converted": False}

    state = _knowledge_state_for_word(word_id, knowledge_signal)
    preferred, depri = _knowledge_type_profile(state)
    if state == "neutral" or not preferred:
        return items, {"state": state, "reordered": False, "converted": False}

    converted = False
    converted_to: Optional[str] = None
    if allow_convert:
        has_preferred = any(item.type in set(preferred) for item in items)
        if not has_preferred and state == "struggling":
            for target in ("meaning_select", "audio_select", "character_select"):
                for item in items:
                    if _convert_exercise_to_type(conn, item, target):
                        converted = True
                        converted_to = target
                        has_preferred = True
                        break
                if has_preferred:
                    break
        elif not has_preferred and state == "knows":
            for target in (
                "order_sentence",
                "speak_read_aloud",
                "reply_select",
                "character_select",
                "reading_micro",
            ):
                for item in items:
                    if _convert_exercise_to_type(conn, item, target):
                        converted = True
                        converted_to = target
                        has_preferred = True
                        break
                if has_preferred:
                    break

    preferred_rank = {t: i for i, t in enumerate(preferred)}
    indexed = list(enumerate(items))

    def _rank(pair: Tuple[int, "ExerciseItem"]) -> Tuple[int, int]:
        idx, item = pair
        t = item.type
        if t in preferred_rank:
            return (preferred_rank[t], idx)
        if t in depri:
            return (100 + idx, idx)
        return (50 + idx, idx)

    ranked = sorted(indexed, key=_rank)
    reordered_items = [item for _, item in ranked]
    reordered = any(a.exercise_id != b.exercise_id for a, b in zip(items, reordered_items))
    return reordered_items, {
        "state": state,
        "reordered": reordered,
        "converted": converted,
        "converted_to": converted_to,
    }


def _is_image_exercise(item: ExerciseItem) -> bool:
    image_url = item.payload.get("image_url")
    return isinstance(image_url, str) and bool(image_url.strip())


def _exercise_mix_stats(exercises: List[ExerciseItem]) -> Dict[str, Any]:
    total = len(exercises)
    if total == 0:
        return {
            "total": 0,
            "image_ratio": 0.0,
            "listening_ratio": 0.0,
            "production_ratio": 0.0,
        }

    image_count = 0
    listening_count = 0
    production_count = 0
    for item in exercises:
        modality = _modality_for_type(item.type)
        if _is_image_exercise(item):
            image_count += 1
        if modality == "listening":
            listening_count += 1
        if modality == "production":
            production_count += 1

    return {
        "total": total,
        "image_count": image_count,
        "listening_count": listening_count,
        "production_count": production_count,
        "image_ratio": round(image_count / total, 4),
        "listening_ratio": round(listening_count / total, 4),
        "production_ratio": round(production_count / total, 4),
    }


def _reorder_no_triplets(exercises: List[ExerciseItem]) -> List[ExerciseItem]:
    """Avoid more than 2 identical types in a row."""
    remaining = list(exercises)
    ordered: List[ExerciseItem] = []
    while remaining:
        pick_index = None
        for i, candidate in enumerate(remaining):
            if len(ordered) >= 2:
                if ordered[-1].type == ordered[-2].type == candidate.type:
                    continue
            pick_index = i
            break
        if pick_index is None:
            pick_index = 0
        ordered.append(remaining.pop(pick_index))
    return ordered


def _enforce_image_budget(exercises: List[ExerciseItem], max_ratio: float = 0.25) -> int:
    """
    Strip excess image_url payloads to keep image-heavy lessons in check.
    Returns number of payloads modified.
    """
    total = len(exercises)
    if total == 0:
        return 0
    max_images = int(total * max_ratio)
    image_indexes = [i for i, item in enumerate(exercises) if _is_image_exercise(item)]
    if len(image_indexes) <= max_images:
        return 0
    changed = 0
    for idx in image_indexes[max_images:]:
        if "image_url" in exercises[idx].payload:
            exercises[idx].payload.pop("image_url", None)
            changed += 1
    return changed


def _build_hanzi_choices(conn: sqlite3.Connection, word_id: str, target_hanzi: str, count: int = 4) -> List[str]:
    rows = conn.execute(
        """
        SELECT text
        FROM concepts
        WHERE id != ?
        ORDER BY id ASC
        LIMIT 24
        """,
        (word_id,),
    ).fetchall()
    choices: List[str] = [target_hanzi]
    for row in rows:
        text = row[0]
        if not text or text in choices:
            continue
        choices.append(text)
        if len(choices) >= count:
            break
    seed = _stable_hash(word_id, "choices")
    choices.sort(key=lambda x: _stable_hash(seed, x))
    return choices


def _build_meaning_choices(conn: sqlite3.Connection, word_id: str, target_meaning: str, count: int = 4) -> List[str]:
    rows = conn.execute(
        """
        SELECT meaning
        FROM concepts
        WHERE id != ?
        ORDER BY id ASC
        LIMIT 64
        """,
        (word_id,),
    ).fetchall()
    choices: List[str] = [target_meaning]
    for row in rows:
        meaning = str(row[0] or "").strip()
        if not meaning or meaning in choices:
            continue
        choices.append(meaning)
        if len(choices) >= count:
            break
    seed = _stable_hash(word_id, "meaning_choices")
    choices.sort(key=lambda x: _stable_hash(seed, x))
    return choices


def _sentence_chunks(hanzi: str, segmentation: Optional[str]) -> List[str]:
    seg = str(segmentation or "").strip()
    if seg:
        # Prefer JSON array segmentation (e.g. ["我","喜欢","你"]).
        try:
            parsed = json.loads(seg)
            if isinstance(parsed, list):
                tokens = [str(t).strip() for t in parsed if str(t).strip()]
                if len(tokens) >= 2:
                    return tokens
        except Exception:
            pass

        # Fallback for plain-delimited segmentation text.
        tokens = []
        for t in re.split(r"[\s|/]+", seg):
            tok = t.strip().strip("[]\"',")
            if tok:
                tokens.append(tok)
        if len(tokens) >= 2:
            return tokens
    chars = [ch for ch in str(hanzi or "").strip() if ch.strip()]
    if len(chars) >= 2:
        return chars
    return [str(hanzi or "").strip()] if str(hanzi or "").strip() else []


def _pick_sentence_for_word(conn: sqlite3.Connection, word_id: str) -> Optional[Dict[str, str]]:
    row = conn.execute(
        """
        SELECT s.id, s.text, s.pinyin, s.translation, s.segmentation
        FROM word_sentences ws
        JOIN sentences s ON s.id = ws.sentence_id
        WHERE ws.word_id = ?
        ORDER BY ws.is_primary DESC, s.id ASC
        LIMIT 1
        """,
        (word_id,),
    ).fetchone()
    if not row:
        return None
    return {
        "sentence_id": str(row[0]),
        "hanzi": str(row[1] or ""),
        "pinyin": str(row[2] or ""),
        "translation": str(row[3] or ""),
        "segmentation": str(row[4] or ""),
    }


def _convert_to_meaning_select(conn: sqlite3.Connection, item: ExerciseItem) -> bool:
    row = conn.execute(
        "SELECT text, pinyin, meaning FROM concepts WHERE id = ?",
        (item.word_id,),
    ).fetchone()
    if not row:
        return False
    hanzi, pinyin, meaning = row[0], row[1], row[2]
    primary_gloss = get_primary_gloss(conn, item.word_id, fallback=meaning)
    sense_payload = get_sense_payload(conn, item.word_id, fallback=meaning)
    choices = _build_meaning_choices(conn, item.word_id, primary_gloss)
    if primary_gloss not in choices:
        return False
    item.type = "meaning_select"
    item.payload = {
        "prompt": {"hanzi": hanzi, "pinyin": pinyin},
        "choices": choices,
        "answer": primary_gloss,
        "answer_index": choices.index(primary_gloss),
        "instruction_en": "Choose the meaning",
        "sense": sense_payload,
    }
    return True


def _convert_to_order_sentence(conn: sqlite3.Connection, item: ExerciseItem) -> bool:
    sentence = _pick_sentence_for_word(conn, item.word_id)
    if not sentence:
        return False
    chunks = _sentence_chunks(sentence["hanzi"], sentence["segmentation"])
    if len(chunks) < 2:
        return False
    meaning_row = conn.execute(
        "SELECT meaning FROM concepts WHERE id = ?",
        (item.word_id,),
    ).fetchone()
    fallback = meaning_row[0] if meaning_row else None
    sense_payload = get_sense_payload(conn, item.word_id, fallback=fallback)
    item.type = "order_sentence"
    item.payload = {
        "segments": chunks,
        "answer": chunks,
        "sentence": sentence["hanzi"],
        "instruction_en": "Build the sentence in correct order",
        "prompt": {
            "pinyin": sentence["pinyin"],
            "translation": sentence["translation"],
        },
        "sense": sense_payload,
    }
    return True


def _convert_to_reading_micro(conn: sqlite3.Connection, item: ExerciseItem) -> bool:
    sentence = _pick_sentence_for_word(conn, item.word_id)
    if not sentence:
        return False
    meaning_row = conn.execute(
        "SELECT text, meaning FROM concepts WHERE id = ?",
        (item.word_id,),
    ).fetchone()
    if not meaning_row:
        return False
    hanzi = str(meaning_row[0] or "")
    meaning = str(meaning_row[1] or "")
    choices = _build_meaning_choices(conn, item.word_id, meaning)
    if meaning not in choices:
        return False
    answer_index = choices.index(meaning)
    sense_payload = get_sense_payload(conn, item.word_id, fallback=meaning)
    item.type = "reading_micro"
    item.payload = {
        "reading": {
            "title_zh": f"阅读：{hanzi}",
            "title_en": "Micro Reading",
            "story_zh": sentence["hanzi"],
            "story_en": sentence["translation"],
        },
        "questions": [
            {
                "type": "meaning_select",
                "prompt": {"question": "What is the highlighted word meaning?", "hanzi": hanzi},
                "choices": choices,
                "answer_index": answer_index,
            }
        ],
        "instruction_en": "Read and answer",
        "sense": sense_payload,
    }
    return True


def _convert_to_audio_select(conn: sqlite3.Connection, item: ExerciseItem) -> bool:
    row = conn.execute(
        "SELECT text, pinyin, meaning FROM concepts WHERE id = ?",
        (item.word_id,),
    ).fetchone()
    if not row:
        return False
    hanzi, pinyin, meaning = row[0], row[1], row[2]
    primary_gloss = get_primary_gloss(conn, item.word_id, fallback=meaning)
    sense_payload = get_sense_payload(conn, item.word_id, fallback=meaning)
    choices = _build_hanzi_choices(conn, item.word_id, hanzi)
    if hanzi not in choices:
        return False
    item.type = "audio_select"
    item.payload = {
        "choices": choices,
        "answer": hanzi,
        "answer_index": choices.index(hanzi),
        "instruction_en": "Listen and choose the characters",
        "prompt": {"meaning": primary_gloss, "pinyin": pinyin},
        "sense": sense_payload,
    }
    return True


def _convert_to_character_select(conn: sqlite3.Connection, item: ExerciseItem) -> bool:
    row = conn.execute(
        "SELECT text, pinyin, meaning FROM concepts WHERE id = ?",
        (item.word_id,),
    ).fetchone()
    if not row:
        return False
    hanzi, pinyin, meaning = row[0], row[1], row[2]
    primary_gloss = get_primary_gloss(conn, item.word_id, fallback=meaning)
    sense_payload = get_sense_payload(conn, item.word_id, fallback=meaning)
    choices = _build_hanzi_choices(conn, item.word_id, hanzi)
    if hanzi not in choices:
        return False
    item.type = "character_select"
    item.payload = {
        "prompt": {"meaning": primary_gloss, "pinyin": pinyin},
        "choices": choices,
        "answer": hanzi,
        "answer_index": choices.index(hanzi),
        "instruction_en": "Choose the correct characters",
        "sense": sense_payload,
    }
    return True


def _convert_to_speak_read_aloud(conn: sqlite3.Connection, item: ExerciseItem) -> bool:
    row = conn.execute(
        "SELECT text, pinyin, meaning FROM concepts WHERE id = ?",
        (item.word_id,),
    ).fetchone()
    if not row:
        return False
    hanzi, pinyin, meaning = row[0], row[1], row[2]
    primary_gloss = get_primary_gloss(conn, item.word_id, fallback=meaning)
    sense_payload = get_sense_payload(conn, item.word_id, fallback=meaning)
    item.type = "speak_read_aloud"
    item.payload = {
        "prompt": {
            "hanzi": hanzi,
            "pinyin": pinyin,
            "meaning": primary_gloss,
        },
        "sample_answers": [str(hanzi or "")],
        "instruction_en": "Read aloud and self-rate",
        "sense": sense_payload,
    }
    return True


def _convert_to_speak_prompted_reply(conn: sqlite3.Connection, item: ExerciseItem) -> bool:
    row = conn.execute(
        "SELECT text, pinyin, meaning FROM concepts WHERE id = ?",
        (item.word_id,),
    ).fetchone()
    if not row:
        return False
    hanzi, pinyin, meaning = row[0], row[1], row[2]
    primary_gloss = get_primary_gloss(conn, item.word_id, fallback=meaning)
    sense_payload = get_sense_payload(conn, item.word_id, fallback=meaning)
    item.type = "speak_prompted_reply"
    item.payload = {
        "prompt_text": f"Respond using '{hanzi}'",
        "prompt": {
            "hanzi": hanzi,
            "pinyin": pinyin,
            "meaning": primary_gloss,
        },
        "sample_answers": [str(hanzi or ""), f"{str(hanzi or '')}。"],
        "instruction_en": "Respond aloud and self-rate",
        "sense": sense_payload,
    }
    return True


def _convert_exercise_to_type(conn: sqlite3.Connection, item: ExerciseItem, target_type: str) -> bool:
    normalized = (target_type or "").strip().lower()
    if not normalized:
        return False
    if item.type == normalized:
        return True
    if normalized == "audio_select":
        return _convert_to_audio_select(conn, item)
    if normalized == "character_select":
        return _convert_to_character_select(conn, item)
    if normalized == "meaning_select":
        return _convert_to_meaning_select(conn, item)
    if normalized == "order_sentence":
        return _convert_to_order_sentence(conn, item)
    if normalized == "reading_micro":
        return _convert_to_reading_micro(conn, item)
    if normalized == "speak_read_aloud":
        return _convert_to_speak_read_aloud(conn, item)
    if normalized == "speak_prompted_reply":
        return _convert_to_speak_prompted_reply(conn, item)
    return False


def _enforce_hsk1_circle_mix(
    conn: sqlite3.Connection,
    exercises: List[ExerciseItem],
    mix: Dict[str, int],
    max_total: int,
    focus_word_ids: List[str],
) -> Dict[str, Any]:
    target: Dict[str, int] = {}
    for ex_type, count in (mix or {}).items():
        c = int(count or 0)
        if c > 0:
            target[str(ex_type)] = c
    if not target or not exercises:
        return {"applied": False, "requested": target, "actual": {}, "converted": 0}

    focus_set = set(str(w) for w in focus_word_ids)
    indexed = list(enumerate(exercises))

    def _priority(pair: tuple[int, ExerciseItem]) -> tuple[int, int]:
        idx, item = pair
        return (0 if item.word_id in focus_set else 1, idx)

    available = sorted(indexed, key=_priority)
    used_indices: Set[int] = set()
    selected: List[ExerciseItem] = []
    converted = 0
    selected_counts: Dict[str, int] = {}
    selected_word_counts: Dict[str, int] = {}

    def _score_candidate(idx: int, item: ExerciseItem) -> tuple[int, int, int]:
        in_focus = item.word_id in focus_set
        word_seen = selected_word_counts.get(item.word_id, 0) > 0
        if in_focus and not word_seen:
            word_bucket = 0
        elif in_focus and word_seen:
            word_bucket = 1
        else:
            word_bucket = 2
        type_seen = selected_counts.get(item.type, 0)
        return (word_bucket, type_seen, idx)

    for ex_type, needed in target.items():
        if needed <= 0:
            continue
        while selected_counts.get(ex_type, 0) < needed:
            direct_candidates: List[tuple[int, ExerciseItem]] = []
            for idx, item in available:
                if idx in used_indices:
                    continue
                if item.type == ex_type:
                    direct_candidates.append((idx, item))

            pick: Optional[tuple[int, ExerciseItem]] = None
            if direct_candidates:
                pick = min(direct_candidates, key=lambda p: _score_candidate(p[0], p[1]))
            else:
                convert_candidates: List[tuple[int, ExerciseItem]] = []
                for idx, item in available:
                    if idx in used_indices:
                        continue
                    convert_candidates.append((idx, item))
                if convert_candidates:
                    convert_candidates.sort(key=lambda p: _score_candidate(p[0], p[1]))
                    for idx, item in convert_candidates:
                        if _convert_exercise_to_type(conn, item, ex_type):
                            converted += 1
                            pick = (idx, item)
                            break

            if not pick:
                break

            idx, item = pick
            used_indices.add(idx)
            selected.append(item)
            selected_counts[item.type] = selected_counts.get(item.type, 0) + 1
            selected_word_counts[item.word_id] = selected_word_counts.get(item.word_id, 0) + 1

    # Fill leftover up to max_total with remaining unused, preferring focus words.
    for idx, item in available:
        if len(selected) >= max_total:
            break
        if idx in used_indices:
            continue
        selected.append(item)
        used_indices.add(idx)
        selected_counts[item.type] = selected_counts.get(item.type, 0) + 1
        selected_word_counts[item.word_id] = selected_word_counts.get(item.word_id, 0) + 1

    # Hard cap
    if len(selected) > max_total:
        selected = selected[:max_total]

    # Mutate original list in-place for downstream logic.
    exercises[:] = selected

    actual: Dict[str, int] = {}
    for item in exercises:
        actual[item.type] = actual.get(item.type, 0) + 1
    return {
        "applied": True,
        "requested": target,
        "actual": actual,
        "converted": converted,
    }


def _enforce_modality_minimums(
    conn: sqlite3.Connection,
    exercises: List[ExerciseItem],
    min_listening_ratio: float = 0.25,
    min_production_ratio: float = 0.20,
) -> Dict[str, int]:
    conversions = {"to_listening": 0, "to_production": 0}
    total = len(exercises)
    if total == 0:
        return conversions

    required_listening = math.ceil(total * min_listening_ratio)
    required_production = math.ceil(total * min_production_ratio)

    def current_counts() -> Dict[str, int]:
        counts = {"listening": 0, "production": 0}
        for item in exercises:
            modality = _modality_for_type(item.type)
            if modality == "listening":
                counts["listening"] += 1
            if modality == "production":
                counts["production"] += 1
        return counts

    counts = current_counts()

    # Prioritize production fill first.
    if counts["production"] < required_production:
        need = required_production - counts["production"]
        for item in exercises:
            if need <= 0:
                break
            if _modality_for_type(item.type) in {"production", "listening"}:
                continue
            if _convert_to_character_select(conn, item):
                conversions["to_production"] += 1
                need -= 1

        # If still short, convert some listening items while preserving listening minimum.
        if need > 0:
            for item in exercises:
                if need <= 0:
                    break
                if _modality_for_type(item.type) != "listening":
                    continue
                # Keep enough listening items after conversion.
                projected_listening = current_counts()["listening"] - 1
                if projected_listening < required_listening:
                    continue
                if _convert_to_character_select(conn, item):
                    conversions["to_production"] += 1
                    need -= 1

    counts = current_counts()
    if counts["listening"] < required_listening:
        need = required_listening - counts["listening"]
        for item in exercises:
            if need <= 0:
                break
            if _modality_for_type(item.type) in {"listening", "production"}:
                continue
            if _convert_to_audio_select(conn, item):
                conversions["to_listening"] += 1
                need -= 1

    return conversions


def _estimate_exercise_seconds(ex_type: str) -> int:
    ex_type = (ex_type or "").lower()
    table = {
        "flashcard": 25,
        "meaning_select": 35,
        "character_select": 35,
        "audio_select": 40,
        "audio_match": 40,
        "tone_select": 40,
        "order_sentence": 55,
        "sentence_fill": 55,
        "collocation_pick": 45,
        "reading_micro": 75,
        "speaking": 60,
        "speak_read_aloud": 60,
        "speak_prompted_reply": 65,
    }
    return table.get(ex_type, 40)


def _estimate_total_seconds(exercises: List[ExerciseItem]) -> int:
    return sum(_estimate_exercise_seconds(ex.type) for ex in exercises)


def _to_exercise_item(selected_item: Any) -> ExerciseItem:
    payload = selected_item.payload or {}
    sense_id: Optional[str] = None
    if isinstance(payload, dict):
        sense_obj = payload.get("sense")
        if isinstance(sense_obj, dict) and isinstance(sense_obj.get("sense_id"), str):
            sense_id = str(sense_obj["sense_id"])
    return ExerciseItem(
        exercise_id=selected_item.exercise_id,
        word_id=selected_item.word_id,
        sense_id=sense_id,
        type=selected_item.exercise_type,
        difficulty=selected_item.difficulty,
        skill_focus=selected_item.skill_focus,
        stage=selected_item.stage,
        review_instance_id=selected_item.review_instance_id,
        slot_key=selected_item.slot_key,
        plan_slot_id=selected_item.plan_slot_id,
        payload=payload,
        selected_by=_selected_by_value(selected_item.selected_by),
    )


def _resolve_submit_sense_id(conn: sqlite3.Connection, request: SubmitRequest) -> Optional[str]:
    """Resolve sense_id for analytics/mastery migration without breaking old clients."""
    if request.sense_id and request.sense_id.startswith(f"{request.word_id}::"):
        return request.sense_id

    # Prefer sense bound to the concrete exercise payload when present.
    ex_row = conn.execute(
        """
        SELECT payload
        FROM word_exercises
        WHERE id = ? AND word_id = ?
        LIMIT 1
        """,
        (request.exercise_id, request.word_id),
    ).fetchone()
    if ex_row and ex_row[0]:
        try:
            payload = json.loads(ex_row[0])
        except Exception:
            payload = None
        if isinstance(payload, dict):
            sense_obj = payload.get("sense")
            if isinstance(sense_obj, dict):
                sid = sense_obj.get("sense_id")
                if isinstance(sid, str) and sid.startswith(f"{request.word_id}::"):
                    return sid

    row = conn.execute(
        "SELECT meaning FROM concepts WHERE id = ?",
        (request.word_id,),
    ).fetchone()
    fallback = row[0] if row else None
    payload = get_sense_payload(conn, request.word_id, fallback=fallback)
    sid = payload.get("sense_id") if isinstance(payload, dict) else None
    if isinstance(sid, str) and sid.startswith(f"{request.word_id}::"):
        return sid
    return None


def _ensure_sense_mastery_row(
    conn: sqlite3.Connection,
    user_id: str,
    language_code: str,
    word_id: str,
    sense_id: str,
) -> sqlite3.Row:
    row = conn.execute(
        """
        SELECT recognition, listening, production, usage, writing,
               mastery_state, pending_since, srs_stage, next_review_at
        FROM user_sense_mastery
        WHERE user_id = ? AND language_code = ? AND sense_id = ?
        """,
        (user_id, language_code, sense_id),
    ).fetchone()
    if row is not None:
        return row

    seed = conn.execute(
        """
        SELECT recognition, listening, production, usage, writing,
               mastery_state, srs_stage, next_review_at, pending_since
        FROM user_word_mastery
        WHERE user_id = ? AND language_code = ? AND word_id = ?
        """,
        (user_id, language_code, word_id),
    ).fetchone()
    if seed is None:
        conn.execute(
            """
            INSERT INTO user_sense_mastery
                (user_id, language_code, sense_id, word_id, mastery_state, srs_stage, next_review_at)
            VALUES (?, ?, ?, ?, ?, 0, datetime('now'))
            """,
            (user_id, language_code, sense_id, word_id, STATE_LEARNING),
        )
    else:
        conn.execute(
            """
            INSERT INTO user_sense_mastery
                (user_id, language_code, sense_id, word_id,
                 recognition, listening, production, usage, writing,
                 mastery_state, srs_stage, next_review_at, pending_since, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
            ON CONFLICT(user_id, language_code, sense_id) DO NOTHING
            """,
            (
                user_id,
                language_code,
                sense_id,
                word_id,
                int(seed["recognition"] or 0),
                int(seed["listening"] or 0),
                int(seed["production"] or 0),
                int(seed["usage"] or 0),
                int(seed["writing"] or 0),
                str(seed["mastery_state"] or STATE_LEARNING),
                int(seed["srs_stage"] or 0),
                seed["next_review_at"],
                seed["pending_since"],
            ),
        )

    return conn.execute(
        """
        SELECT recognition, listening, production, usage, writing,
               mastery_state, pending_since, srs_stage, next_review_at
        FROM user_sense_mastery
        WHERE user_id = ? AND language_code = ? AND sense_id = ?
        """,
        (user_id, language_code, sense_id),
    ).fetchone()


def _ensure_sense_stage_progress_row(
    conn: sqlite3.Connection,
    user_id: str,
    language_code: str,
    word_id: str,
    sense_id: str,
    review_instance_id: str,
    stage: int,
    required_slots_json: str,
    passed_slots_json: str,
    failed_attempts: int,
) -> sqlite3.Row:
    conn.execute(
        """
        INSERT INTO user_sense_stage_progress
            (user_id, language_code, sense_id, word_id, stage, review_instance_id,
             required_slots, passed_slots, failed_attempts, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))
        ON CONFLICT(user_id, language_code, sense_id, review_instance_id) DO NOTHING
        """,
        (
            user_id,
            language_code,
            sense_id,
            word_id,
            int(stage),
            review_instance_id,
            required_slots_json,
            passed_slots_json,
            int(failed_attempts),
        ),
    )
    return conn.execute(
        """
        SELECT required_slots, passed_slots, stage
        FROM user_sense_stage_progress
        WHERE user_id = ? AND language_code = ? AND sense_id = ?
          AND review_instance_id = ?
        """,
        (user_id, language_code, sense_id, review_instance_id),
    ).fetchone()


def _mastery_gate_snapshot(
    conn: sqlite3.Connection,
    user_id: str,
    language_code: str,
    word_id: str,
    plan_slot_id: str,
    sense_id: Optional[str],
    is_correct: bool,
) -> Dict[str, Any]:
    """
    Anti-inflation promotion gate for MASTERED_PENDING transition.
    Uses existing attempts + current in-flight submission (provisional).
    """
    row = conn.execute(
        """
        SELECT
            COUNT(*) AS total_attempts,
            SUM(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END) AS correct_attempts,
            COUNT(DISTINCT plan_slot_id) AS distinct_slots,
            COUNT(DISTINCT date(created_at)) AS active_days,
            COUNT(DISTINCT CASE WHEN sense_id IS NOT NULL AND TRIM(sense_id) != '' THEN sense_id END) AS distinct_senses,
            SUM(CASE WHEN sense_id = ? THEN 1 ELSE 0 END) AS target_sense_attempts,
            MAX(CASE WHEN plan_slot_id = ? THEN 1 ELSE 0 END) AS slot_seen,
            MAX(CASE WHEN date(created_at) = date('now') THEN 1 ELSE 0 END) AS seen_today
        FROM user_attempts
        WHERE user_id = ? AND language_code = ? AND word_id = ?
          AND created_at >= datetime('now', '-45 days')
        """,
        [sense_id, plan_slot_id, user_id, language_code, word_id],
    ).fetchone()

    total_attempts = int(row[0] or 0)
    correct_attempts = int(row[1] or 0)
    distinct_slots = int(row[2] or 0)
    active_days = int(row[3] or 0)
    distinct_senses = int(row[4] or 0)
    target_sense_attempts = int(row[5] or 0)
    slot_seen = int(row[6] or 0)
    seen_today = int(row[7] or 0)

    # Provisional update with current submit before insert.
    total_attempts += 1
    if is_correct:
        correct_attempts += 1
    if slot_seen == 0:
        distinct_slots += 1
    if seen_today == 0:
        active_days += 1
    if sense_id:
        target_sense_attempts += 1
        # Distinct senses can only increase by 1 for this in-flight submit.
        # We conservatively assume it is new only if no previous attempts on this sense.
        if target_sense_attempts == 1:
            distinct_senses += 1

    sense_variants = 1
    try:
        row_sense = conn.execute(
            "SELECT meaning FROM concepts WHERE id = ? LIMIT 1",
            (word_id,),
        ).fetchone()
        fallback_meaning = row_sense[0] if row_sense else None
        sense_variants = max(1, len(get_senses(conn, word_id, fallback=fallback_meaning)))
    except Exception:
        sense_variants = 1

    reasons: List[str] = []
    if correct_attempts < 6:
        reasons.append("need_more_correct_attempts")
    if distinct_slots < 3:
        reasons.append("need_more_slot_variety")
    if active_days < 2:
        reasons.append("need_spaced_success_across_days")
    if sense_id and target_sense_attempts < 1:
        reasons.append("need_current_sense_attempt")
    if (
        sense_variants > 1
        and distinct_senses < min(2, sense_variants)
        and correct_attempts < 10
    ):
        reasons.append("need_sense_coverage")

    return {
        "passed": len(reasons) == 0,
        "reasons": reasons,
        "snapshot": {
            "total_attempts": total_attempts,
            "correct_attempts": correct_attempts,
            "distinct_slots": distinct_slots,
            "active_days": active_days,
            "distinct_senses": distinct_senses,
            "target_sense_attempts": target_sense_attempts,
            "sense_variants": sense_variants,
        },
    }


def _build_word_exercises(
    conn: sqlite3.Connection,
    selector: BrainSelector,
    user_id: str,
    language_code: str,
    word_id: str,
    mission_id: str,
    preferred_sense_id: Optional[str] = None,
) -> List[ExerciseItem]:
    if preferred_sense_id:
        sense_row = _ensure_sense_mastery_row(
            conn=conn,
            user_id=user_id,
            language_code=language_code,
            word_id=word_id,
            sense_id=preferred_sense_id,
        )
        vector = MasteryVector(
            recognition=int(sense_row[0] or 0),
            listening=int(sense_row[1] or 0),
            production=int(sense_row[2] or 0),
            usage=int(sense_row[3] or 0),
        )
        stage = int(sense_row[7] or 0)
    else:
        mastery_row = conn.execute("""
            SELECT recognition, listening, production, usage, srs_stage, mastery_state
            FROM user_word_mastery
            WHERE user_id = ? AND language_code = ? AND word_id = ?
        """, [user_id, language_code, word_id]).fetchone()

        if not mastery_row:
            conn.execute("""
                INSERT INTO user_word_mastery
                    (user_id, language_code, word_id, mastery_state, srs_stage, next_review_at)
                VALUES (?, ?, ?, ?, 0, datetime('now'))
            """, [user_id, language_code, word_id, STATE_LEARNING])
            conn.commit()
            vector = MasteryVector()
            stage = 0
        else:
            vector = MasteryVector(
                recognition=mastery_row[0],
                listening=mastery_row[1],
                production=mastery_row[2],
                usage=mastery_row[3],
            )
            stage = mastery_row[4]

    active = get_active_review_instance(conn, user_id, language_code, word_id)
    if not active:
        instance = create_review_instance(
            conn, user_id, language_code, word_id, stage, vector
        )
        review_instance_id = instance["review_instance_id"]
        remaining = instance["required_slots"]
    else:
        review_instance_id = active["review_instance_id"]
        remaining = active["slots_remaining"]

    selected_items = selector.select_exercises_for_word(
        user_id=user_id,
        language_code=language_code,
        word_id=word_id,
        stage=stage,
        vector=vector,
        review_instance_id=review_instance_id,
        mission_id=mission_id,
        remaining_slots=remaining,
        preferred_sense_id=preferred_sense_id,
    )

    return [_to_exercise_item(item) for item in selected_items]


# ============================================================
# POST /api/v2/brain/mission
# ============================================================

@router.post("/mission", response_model=ExercisesResponse)
async def create_mission(
    request: MissionRequest,
    token_user_id: str = Depends(get_user_id)
):
    """
    Generate exercises for a mission using BrainSelector.
    Enforces the LEARN mission Hard Contract: Every forced word gets at least one exercise.
    """
    conn = get_db()
    mission_id = f"m_{uuid.uuid4().hex[:12]}"
    
    selector = create_selector(conn, mission_seed=mission_id)
    retry_profile = _recent_retry_profile(
        conn=conn,
        user_id=token_user_id,
        language_code=request.language_code,
    )
    learning_signal = _recent_learning_signal(
        conn=conn,
        user_id=token_user_id,
        language_code=request.language_code,
        lookback_minutes=30,
    )
    knowledge_signal = _recent_knowledge_signal(
        conn=conn,
        user_id=token_user_id,
        language_code=request.language_code,
        lookback_minutes=45,
        per_word_lookback_hours=72,
    )

    # Personas Disabled: Use Standard HSK Profile
    goal_profile = None

    # 1. Get Candidates (Smart Selection or Forced)
    forced_strs = _normalize_word_id_list(request.forced_ids)
    allowed_strs = _normalize_word_id_list(request.allowed_word_ids)
    requested_allowed_strs = list(allowed_strs)
    effective_unit_id = request.unit_id
    hsk1_pack_circle: Optional[Dict[str, Any]] = None
    hsk1_pack_sense_by_word: Dict[str, str] = {}
    remediation_mode = False
    remediation_reason: Optional[str] = None
    scope_violation_count = 0
    scope_regen_attempts = 0
    scope_fallback_count = 0
    scope_source = "request" if allowed_strs else "none"

    if request.intent.lower() == "learn" and request.language_code == "zh":
        circle = _resolve_hsk1_pack_circle(request.node_id, request.unit_id)
        if circle:
            focus_word_ids = [str(w) for w in circle.get("focus_word_ids", []) if str(w).strip()]
            if focus_word_ids:
                base_target_words = int(
                    circle.get("target_word_count")
                    or circle.get("target_exercise_count")
                    or len(focus_word_ids)
                )
                target_words = _adapt_hsk1_target_words(
                    base_target=base_target_words,
                    pool_size=len(focus_word_ids),
                    signal=learning_signal,
                    knowledge_signal=knowledge_signal,
                )
                day_bucket = datetime.utcnow().strftime("%Y-%m-%d")
                forced_strs = _rotating_subset(
                    focus_word_ids,
                    target_words,
                    seed_key=f"{token_user_id}:{circle['unit_id']}:{circle['circle_id']}:{day_bucket}",
                )
                effective_unit_id = str(circle["unit_id"])
                hsk1_pack_circle = circle
                focus_set = set(forced_strs)
                for sid in circle.get("focus_sense_ids", []):
                    sid_str = str(sid or "")
                    if "::" not in sid_str:
                        continue
                    wid = sid_str.split("::", 1)[0]
                    if wid in focus_set:
                        hsk1_pack_sense_by_word[wid] = sid_str
                if not allowed_strs:
                    # HSK1 LEARN rollout scope:
                    # allow words introduced up to this circle + previous-unit introduced words.
                    current_introduced = _normalize_word_id_list(
                        circle.get("introduced_until_circle_word_ids")
                    )
                    if not current_introduced:
                        current_introduced = _normalize_word_id_list(
                            circle.get("focus_word_ids")
                        )
                    previous_introduced = _hsk1_introduced_words_for_unit(
                        _hsk1_previous_unit_id(circle.get("unit_id"))
                    )
                    merged_scope = _normalize_word_id_list(
                        [*current_introduced, *previous_introduced]
                    )
                    if merged_scope:
                        allowed_strs = merged_scope
                        scope_source = "hsk1_unit_plus_previous"
                    elif forced_strs:
                        allowed_strs = list(forced_strs)
                        scope_source = "focus_fallback"
                        scope_fallback_count += 1
    
    # [FIX] Budgeting: limit must be at least the size of forced_ids to satisfy the contract
    effective_limit = max(request.limit, len(forced_strs))
    if hsk1_pack_circle:
        base_target = int(hsk1_pack_circle.get("serve_target") or hsk1_pack_circle.get("target_exercise_count") or effective_limit)
        effective_limit = base_target
        effective_limit = max(1, effective_limit)
        mode = str(learning_signal.get("mode") or "normal")
        cap_normal = int(hsk1_pack_circle.get("serve_cap_normal") or hsk1_pack_circle.get("serve_cap") or effective_limit)
        cap_struggle = int(hsk1_pack_circle.get("serve_cap_struggle") or hsk1_pack_circle.get("serve_cap") or effective_limit)
        if mode == "assist":
            # Struggling users get a longer guided run (more remediation opportunities).
            effective_limit = max(effective_limit, cap_struggle)
        elif mode == "challenge":
            # Strong users keep compact runs; avoid overlong sessions.
            effective_limit = min(cap_normal, effective_limit)
        else:
            effective_limit = min(cap_normal, effective_limit)
        hsk1_pack_circle["target_exercise_count"] = int(max(1, effective_limit))

    # Adaptive daily policy: controls how many NEW words can appear when backlog is high.
    # This keeps SRS debt from exploding when users move too fast.
    adaptive_policy: Dict[str, Any] = {
        "mode": "static",
        "due_count": 0,
        "hard_due_count": 0,
        "soft_due_count": 0,
        "backlog_ratio": 0.0,
        "review_capacity_words": DAILY_REVIEW_CAP_WORDS,
        "mode_reason": "static",
    }
    if request.intent.lower() == "learn":
        if hsk1_pack_circle:
            # Pack circles are strict: only circle-focus words for this mission.
            actual_max_new = len(forced_strs) if forced_strs else 3
            actual_max_review = 0
            adaptive_policy["mode"] = "learn_hsk1_pack"
            adaptive_policy["mode_reason"] = "hsk1_circle_pack_forced_focus"
            adaptive_policy["pack_unit_id"] = hsk1_pack_circle["unit_id"]
            adaptive_policy["pack_circle_id"] = hsk1_pack_circle["circle_id"]
            adaptive_policy["pack_candidate_pool_size"] = hsk1_pack_circle.get("candidate_pool_size")
            adaptive_policy["pack_target_word_count"] = hsk1_pack_circle.get("target_word_count")
            adaptive_policy["learning_mode"] = learning_signal.get("mode")
            adaptive_policy["learning_mode_reason"] = learning_signal.get("mode_reason")
        else:
            # LEARN circles intentionally prioritize forced words.
            actual_max_new = len(forced_strs) if forced_strs else 3
            actual_max_review = effective_limit
            adaptive_policy["mode"] = "learn_forced"
    elif request.intent.lower() == "daily":
        due_status = _count_due_reviews(
            conn,
            token_user_id,
            request.language_code,
            unit_id=effective_unit_id,
        )
        adaptive_policy = _daily_budget_policy(
            mission_limit=effective_limit,
            due_status=due_status,
            requested_new_target=request.daily_new_target,
        )
        actual_max_new = int(adaptive_policy["max_new"])
        actual_max_review = int(adaptive_policy["max_review"])
    elif request.intent.lower() in {"review", "drill"}:
        actual_max_new = 0
        actual_max_review = effective_limit
        adaptive_policy["mode"] = request.intent.lower()
    else:
        actual_max_new = 3
        actual_max_review = effective_limit

    if request.intent.lower() == "learn" and hsk1_pack_circle:
        on_fail = hsk1_pack_circle.get("on_fail", {}) or {}
        retry_mode = str(on_fail.get("retry_mode") or "")
        max_retry_rings = int(on_fail.get("max_retry_rings") or 0)
        focus_failing_words = [
            wid for wid in forced_strs if int((retry_profile.get(wid) or {}).get("fail_count") or 0) > 0
        ]
        if focus_failing_words:
            if retry_mode == "auto_insert_remedial_c6" and hsk1_pack_circle.get("circle_id") == "C7":
                remedial = _resolve_hsk1_pack_circle(
                    node_id=f"{hsk1_pack_circle['unit_id']}_L06",
                    unit_id=hsk1_pack_circle["unit_id"],
                )
                if remedial:
                    hsk1_pack_circle = remedial
                    focus_word_ids = [str(w) for w in (remedial.get("focus_word_ids") or [])]
                    base_target_words = int(
                        remedial.get("target_word_count")
                        or remedial.get("target_exercise_count")
                        or len(focus_word_ids)
                    )
                    target_words = _adapt_hsk1_target_words(
                        base_target=base_target_words,
                        pool_size=len(focus_word_ids),
                        signal=learning_signal,
                        knowledge_signal=knowledge_signal,
                    )
                    target_words = max(1, min(len(focus_word_ids), target_words))
                    day_bucket = datetime.utcnow().strftime("%Y-%m-%d")
                    forced_strs = _rotating_subset(
                        focus_word_ids,
                        target_words,
                        seed_key=f"{token_user_id}:{remedial['unit_id']}:{remedial['circle_id']}:{day_bucket}",
                    )
                    hsk1_pack_sense_by_word = {}
                    focus_set = set(forced_strs)
                    for sid in remedial.get("focus_sense_ids", []):
                        sid_str = str(sid or "")
                        if "::" not in sid_str:
                            continue
                        wid = sid_str.split("::", 1)[0]
                        if wid in focus_set:
                            hsk1_pack_sense_by_word[wid] = sid_str
                    effective_limit = max(1, int(remedial.get("target_exercise_count") or effective_limit))
                    remediation_mode = True
                    remediation_reason = "checkpoint_failed_auto_c6"
            elif retry_mode in {
                "immediate_remediate",
                "speaking_or_audio_first",
                "force_type_variation",
                "review_only_until_stable",
            }:
                # Keep mission size fixed, but force retry words to the front.
                reordered = focus_failing_words + [w for w in forced_strs if w not in set(focus_failing_words)]
                forced_strs = reordered[: max(1, effective_limit)]
                remediation_mode = True
                remediation_reason = f"retry_mode:{retry_mode}"
        adaptive_policy["retry_mode"] = retry_mode
        adaptive_policy["max_retry_rings"] = max_retry_rings
        # Ensure candidate caps reflect latest forced_ids after remediation.
        actual_max_new = len(forced_strs) if forced_strs else actual_max_new

    if request.intent.lower() == "learn" and forced_strs:
        struggling_front = [
            wid
            for wid in (knowledge_signal.get("top_struggling_words") or [])
            if wid in set(forced_strs)
        ]
        if struggling_front:
            seen = set(struggling_front)
            forced_strs = struggling_front + [w for w in forced_strs if w not in seen]
            if not remediation_mode:
                remediation_mode = True
                remediation_reason = "knowledge_struggling_frontload"

    if request.intent.lower() == "learn" and hsk1_pack_circle:
        circle_id = str(hsk1_pack_circle.get("circle_id") or "")
        if circle_id in _HSK1_REVIEW_CIRCLE_IDS:
            introduced_scope = [
                str(w)
                for w in (hsk1_pack_circle.get("introduced_word_ids") or [])
                if str(w).strip()
            ]
            scope = introduced_scope or list(forced_strs)
            seen_words = _recent_seen_words_for_scope(
                conn=conn,
                user_id=token_user_id,
                language_code=request.language_code,
                scope_word_ids=scope,
                lookback_hours=24,
            )
            if seen_words:
                filtered = [w for w in forced_strs if w in seen_words]
                if filtered:
                    forced_strs = filtered
                    if hsk1_pack_sense_by_word:
                        hsk1_pack_sense_by_word = {
                            wid: sid
                            for wid, sid in hsk1_pack_sense_by_word.items()
                            if wid in set(filtered)
                        }

    if allowed_strs:
        allowed_set_for_validation = set(allowed_strs)
        missing_forced = [wid for wid in forced_strs if wid not in allowed_set_for_validation]
        if missing_forced:
            raise HTTPException(
                status_code=400,
                detail=(
                    "forced_ids must be a subset of allowed_word_ids when whitelist is provided. "
                    f"missing={missing_forced[:8]}"
                ),
            )

    scope_enabled = bool(allowed_strs) and request.intent.lower() == "learn"
    allowed_scope_set = set(allowed_strs) if scope_enabled else set()
    scope_version = _SCOPE_VERSION_HSK1_LEARN_V1 if scope_enabled else "off"

    def _filter_candidates_by_scope(items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        nonlocal scope_violation_count
        if not scope_enabled:
            return items
        filtered_items: List[Dict[str, Any]] = []
        for item in items:
            wid = str(item.get("word_id") or "").strip()
            if not wid:
                continue
            if wid in allowed_scope_set:
                filtered_items.append(item)
            else:
                scope_violation_count += 1
        return filtered_items

    candidates = selector.get_candidates_for_intent(
        user_id=token_user_id,
        language_code=request.language_code,
        intent=request.intent.upper(),
        forced_ids=forced_strs,
        unit_id=effective_unit_id,
        focus_dimension=request.focus_dimension,
        max_new=actual_max_new,
        max_review=actual_max_review
    )
    candidates = _filter_candidates_by_scope(candidates)
    candidates = _prioritize_candidates_by_knowledge(
        candidates=candidates,
        retry_profile=retry_profile,
        knowledge_signal=knowledge_signal,
    )
    
    final_exercises = []
    overflow_pool = [] # For secondary exercises for same words
    retry_words_in_mission = 0
    retry_primary_swaps = 0
    knowledge_type_adaptation: Dict[str, Any] = {
        "enabled": True,
        "signal_mode": str(knowledge_signal.get("mode") or "normal"),
        "conversion_allowed": not bool(hsk1_pack_circle),
        "state_counts": {"struggling": 0, "knows": 0, "neutral": 0},
        "reordered_words": 0,
        "converted_items": 0,
        "converted_to_counts": {},
    }
    review_word_ids = {
        str(c.get("word_id"))
        for c in candidates
        if str(c.get("reason", "")).startswith("srs_due")
    }
    
    # 2. Process Candidates
    for cand in candidates:
        word_id = str(cand["word_id"])
        retry_entry = retry_profile.get(word_id, {})
        failed_types = set(retry_entry.get("failed_types") or [])
        if failed_types:
            retry_words_in_mission += 1
        preferred_sense_id = str(cand["sense_id"]) if cand.get("sense_id") else None
        if not preferred_sense_id and hsk1_pack_sense_by_word:
            preferred_sense_id = hsk1_pack_sense_by_word.get(word_id)
        selected_items = _build_word_exercises(
            conn=conn,
            selector=selector,
            user_id=token_user_id,
            language_code=request.language_code,
            word_id=word_id,
            mission_id=mission_id,
            preferred_sense_id=preferred_sense_id,
        )
        if not selected_items:
            continue

        biased_items, bias_meta = _apply_knowledge_type_bias_for_word(
            conn=conn,
            items=selected_items,
            word_id=word_id,
            knowledge_signal=knowledge_signal,
            allow_convert=not bool(hsk1_pack_circle),
        )
        state_key = str(bias_meta.get("state") or "neutral")
        if state_key not in {"struggling", "knows", "neutral"}:
            state_key = "neutral"
        knowledge_type_adaptation["state_counts"][state_key] = (
            int(knowledge_type_adaptation["state_counts"].get(state_key) or 0) + 1
        )
        if bool(bias_meta.get("reordered")):
            knowledge_type_adaptation["reordered_words"] = (
                int(knowledge_type_adaptation.get("reordered_words") or 0) + 1
            )
        if bool(bias_meta.get("converted")):
            knowledge_type_adaptation["converted_items"] = (
                int(knowledge_type_adaptation.get("converted_items") or 0) + 1
            )
            target_type = str(bias_meta.get("converted_to") or "")
            if target_type:
                c_counts = knowledge_type_adaptation["converted_to_counts"]
                c_counts[target_type] = int(c_counts.get(target_type) or 0) + 1

        # Deep Learning Strategy: For forced words (Lessons), we want the WHOLE sequence
        # (Exposure -> Quiz -> Sentence).
        if request.intent.lower() == "learn":
            ordered_items = _prioritize_retry_sequence(biased_items, failed_types)
            if ordered_items and ordered_items[0].exercise_id != biased_items[0].exercise_id:
                retry_primary_swaps += 1
            for item in ordered_items:
                final_exercises.append(item)
        else:
            # Standard Strategy (Daily/Review): 1 exercise per word, others to overflow
            primary_item = _pick_primary_with_retry_variation(biased_items, failed_types)
            if primary_item.exercise_id != biased_items[0].exercise_id:
                retry_primary_swaps += 1
            final_exercises.append(primary_item)

            # Add remaining to overflow for budget filling
            for item in biased_items:
                if item.exercise_id == primary_item.exercise_id:
                    continue
                overflow_pool.append(item)

    # 3. Fill remaining budget from overflow pool up to effective_limit
    while len(final_exercises) < effective_limit and overflow_pool:
        final_exercises.append(overflow_pool.pop(0))

    support_inserts: List[Dict[str, Any]] = []
    if request.intent.lower() == "learn" and len(final_exercises) < effective_limit:
        used_word_ids = {item.word_id for item in final_exercises}
        fill_needed = effective_limit - len(final_exercises)
        support_candidates = selector.get_candidates_for_intent(
            user_id=token_user_id,
            language_code=request.language_code,
            intent="REVIEW",
            max_new=0,
            max_review=max(6, fill_needed * 2),
            unit_id=effective_unit_id,
        )
        support_candidates = _filter_candidates_by_scope(support_candidates)
        for cand in support_candidates:
            if len(final_exercises) >= effective_limit:
                break
            wid = str(cand.get("word_id") or "")
            if not wid:
                continue
            if scope_enabled and wid not in allowed_scope_set:
                scope_violation_count += 1
                continue
            if (
                hsk1_pack_circle
                and forced_strs
                and not scope_enabled
                and wid not in set(forced_strs)
            ):
                # Keep strict circle scope in pack mode.
                continue
            if wid in used_word_ids:
                continue
            preferred_sense_id = str(cand["sense_id"]) if cand.get("sense_id") else None
            items = _build_word_exercises(
                conn=conn,
                selector=selector,
                user_id=token_user_id,
                language_code=request.language_code,
                word_id=wid,
                mission_id=mission_id,
                preferred_sense_id=preferred_sense_id,
            )
            if not items:
                continue
            final_exercises.append(items[0])
            used_word_ids.add(wid)
            support_inserts.append(
                {
                    "kind": "srs_topup",
                    "word_id": wid,
                    "exercise_id": items[0].exercise_id,
                    "exercise_type": items[0].type,
                }
            )

    # 3.5 Duration targeting for LEARN missions (default 8-10 min).
    target_min_seconds: Optional[int] = None
    target_max_seconds: Optional[int] = None
    duration_topup_added = 0
    duration_trimmed = 0
    duration_topup_words: List[str] = []
    if request.intent.lower() == "learn":
        if request.target_min_seconds is not None:
            target_min_seconds = request.target_min_seconds
        elif hsk1_pack_circle:
            circle_target = int(hsk1_pack_circle.get("duration_target_sec") or 240)
            target_min_seconds = max(180, circle_target - 60)
        else:
            target_min_seconds = 480

        if request.target_max_seconds is not None:
            target_max_seconds = request.target_max_seconds
        elif hsk1_pack_circle:
            circle_target = int(hsk1_pack_circle.get("duration_target_sec") or 240)
            target_max_seconds = max(target_min_seconds, circle_target + 60)
        else:
            target_max_seconds = 600

        if target_max_seconds < target_min_seconds:
            target_max_seconds = target_min_seconds

        used_exercise_ids = {item.exercise_id for item in final_exercises}
        used_word_ids = {item.word_id for item in final_exercises}
        estimated_duration = _estimate_total_seconds(final_exercises)

        def append_if_new(item: ExerciseItem) -> bool:
            nonlocal estimated_duration, duration_topup_added
            if item.exercise_id in used_exercise_ids:
                return False
            final_exercises.append(item)
            used_exercise_ids.add(item.exercise_id)
            used_word_ids.add(item.word_id)
            estimated_duration += _estimate_exercise_seconds(item.type)
            duration_topup_added += 1
            return True

        while overflow_pool and estimated_duration < target_min_seconds:
            append_if_new(overflow_pool.pop(0))

        if estimated_duration < target_min_seconds:
            topup_candidates = selector.get_candidates_for_intent(
                user_id=token_user_id,
                language_code=request.language_code,
                intent="REVIEW",
                max_new=0,
                max_review=24,
            )
            topup_candidates = _filter_candidates_by_scope(topup_candidates)
            for candidate in topup_candidates:
                if estimated_duration >= target_min_seconds:
                    break
                word_id = str(candidate.get("word_id"))
                preferred_sense_id = str(candidate["sense_id"]) if candidate.get("sense_id") else None
                if not word_id or word_id in used_word_ids:
                    continue
                if scope_enabled and word_id not in allowed_scope_set:
                    scope_violation_count += 1
                    continue
                word_exercises = _build_word_exercises(
                    conn=conn,
                    selector=selector,
                    user_id=token_user_id,
                    language_code=request.language_code,
                    word_id=word_id,
                    mission_id=mission_id,
                    preferred_sense_id=preferred_sense_id,
                )
                if not word_exercises:
                    continue
                if append_if_new(word_exercises[0]):
                    duration_topup_words.append(word_id)
                for extra in word_exercises[1:]:
                    overflow_pool.append(extra)

            while overflow_pool and estimated_duration < target_min_seconds:
                append_if_new(overflow_pool.pop(0))

        if estimated_duration > target_max_seconds and final_exercises:
            protected_word_ids = set(forced_strs)
            word_counts = Counter(item.word_id for item in final_exercises)
            idx = len(final_exercises) - 1
            while idx >= 0 and estimated_duration > target_max_seconds:
                item = final_exercises[idx]
                is_protected = item.word_id in protected_word_ids and word_counts[item.word_id] <= 1
                if is_protected:
                    idx -= 1
                    continue
                removed = final_exercises.pop(idx)
                word_counts[removed.word_id] -= 1
                used_exercise_ids.discard(removed.exercise_id)
                estimated_duration -= _estimate_exercise_seconds(removed.type)
                duration_trimmed += 1
                idx -= 1

    if scope_enabled:
        before_count = len(final_exercises)
        final_exercises = [
            item for item in final_exercises if item.word_id in allowed_scope_set
        ]
        removed_out_of_scope = before_count - len(final_exercises)
        if removed_out_of_scope > 0:
            scope_violation_count += removed_out_of_scope
            scope_regen_attempts += 1

    # 4. Pack mix enforcement (HSK1 strict circles) + composition telemetry.
    circle_mix_result: Dict[str, Any] = {"applied": False, "requested": {}, "actual": {}, "converted": 0}
    if request.intent.lower() == "learn" and hsk1_pack_circle:
        circle_mix_result = _enforce_hsk1_circle_mix(
            conn=conn,
            exercises=final_exercises,
            mix=dict(hsk1_pack_circle.get("exercise_mix") or {}),
            max_total=max(1, int(hsk1_pack_circle.get("target_exercise_count") or len(final_exercises) or 1)),
            focus_word_ids=[str(w) for w in (forced_strs or [])],
        )

    # 5. Composition enforcement and telemetry (especially for LEARN missions).
    modality_conversions = {"to_listening": 0, "to_production": 0}
    if request.intent.lower() == "learn" and not hsk1_pack_circle:
        modality_conversions = _enforce_modality_minimums(
            conn,
            final_exercises,
            min_listening_ratio=0.25,
            min_production_ratio=0.20,
        )
    final_exercises = _reorder_no_triplets(final_exercises)
    images_stripped = _enforce_image_budget(final_exercises, max_ratio=0.25)
    mix = _exercise_mix_stats(final_exercises)
    estimated_duration_seconds = _estimate_total_seconds(final_exercises)
    has_review_item = any(ex.word_id in review_word_ids for ex in final_exercises)

    violations: List[str] = []
    if mix["image_ratio"] > 0.25:
        violations.append("image_ratio_exceeded")
    if request.intent.lower() == "learn" and not hsk1_pack_circle and mix["listening_ratio"] < 0.25:
        violations.append("listening_ratio_below_min")
    if request.intent.lower() == "learn" and not hsk1_pack_circle and mix["production_ratio"] < 0.20:
        violations.append("production_ratio_below_min")
    if request.intent.lower() == "learn" and review_word_ids and not has_review_item:
        violations.append("no_review_item_available")
    if request.intent.lower() == "learn" and target_min_seconds is not None:
        if estimated_duration_seconds < target_min_seconds:
            violations.append("duration_below_target")
    if request.intent.lower() == "learn" and target_max_seconds is not None:
        if estimated_duration_seconds > target_max_seconds:
            violations.append("duration_above_target")

    circle_id_for_slots = (
        str(hsk1_pack_circle.get("circle_id"))
        if hsk1_pack_circle and hsk1_pack_circle.get("circle_id") is not None
        else None
    )
    ring_slots = _compute_ring_slots(
        learning_signal=learning_signal,
        adaptive_policy=adaptive_policy,
        circle_id=circle_id_for_slots,
        has_review_pressure=bool(review_word_ids),
    )

    suggested_media_slot: Optional[Dict[str, Any]] = None
    if hsk1_pack_circle and request.intent.lower() == "learn":
        cid = str(hsk1_pack_circle.get("circle_id") or "")
        if cid in {"C6", "C7"}:
            suggested_media_slot = {
                "type": "radio_story",
                "duration_sec": 45,
                "mode": "listen_only",
                "note": "Short story/listen insert for recovery and engagement",
            }
        elif cid in {"C2", "C5"}:
            suggested_media_slot = {
                "type": "sticker_scene",
                "duration_sec": 25,
                "mode": "tap_to_reveal",
                "note": "Light visual context insert",
            }

    scope_focus_word_ids = _normalize_word_id_list(forced_strs)
    scope_introduced_word_ids = _normalize_word_id_list(
        hsk1_pack_circle.get("introduced_word_ids") if hsk1_pack_circle else None
    )
    scope_allowed_word_ids = _normalize_word_id_list(allowed_strs)
    if not scope_allowed_word_ids and scope_focus_word_ids:
        scope_allowed_word_ids = list(scope_focus_word_ids)
        scope_source = "focus_fallback"
        scope_fallback_count += 1
    scope_new_word_ids = list(scope_focus_word_ids)
    scope_new_set = set(scope_new_word_ids)
    scope_known_word_ids = [wid for wid in scope_allowed_word_ids if wid not in scope_new_set]

    return ExercisesResponse(
        mission_id=mission_id,
        exercises=final_exercises,
        policy_version="v2.1-mixed-learn" if request.intent.lower() == "learn" else "v2.1",
        metadata={
            "intent": request.intent,
            "adaptive_policy": adaptive_policy,
            "explainability": {
                "policy_mode": adaptive_policy.get("mode"),
                "mode_reason": adaptive_policy.get("mode_reason"),
                "due_hard_count": adaptive_policy.get("hard_due_count", 0),
                "due_soft_count": adaptive_policy.get("soft_due_count", 0),
                "due_total_count": adaptive_policy.get("due_count", 0),
                "backlog_ratio": adaptive_policy.get("backlog_ratio", 0.0),
                "review_capacity_words": adaptive_policy.get("review_capacity_words", DAILY_REVIEW_CAP_WORDS),
                "new_word_cap": actual_max_new,
            },
            "requested_daily_new_target": request.daily_new_target,
            "applied_max_new": actual_max_new,
            "applied_max_review": actual_max_review,
            "ring_slots": ring_slots,
            "mix": mix,
            "images_stripped": images_stripped,
            "modality_conversions": modality_conversions,
            "has_review_item": has_review_item,
            "retry_policy": {
                "lookback_hours": 72,
                "retry_profile_words": len(retry_profile),
                "retry_words_in_mission": retry_words_in_mission,
                "retry_primary_swaps": retry_primary_swaps,
            },
            "learning_signal": learning_signal,
            "knowledge_signal": knowledge_signal,
            "knowledge_type_adaptation": knowledge_type_adaptation,
            "estimated_duration_seconds": estimated_duration_seconds,
            "target_min_seconds": target_min_seconds,
            "target_max_seconds": target_max_seconds,
            "duration_topup_added": duration_topup_added,
            "duration_topup_words": duration_topup_words,
            "duration_trimmed": duration_trimmed,
            "support_inserts": support_inserts,
            "scope_version": scope_version,
            "focus_word_ids": scope_focus_word_ids,
            "allowed_word_ids": scope_allowed_word_ids,
            "introduced_word_ids": scope_introduced_word_ids,
            "new_word_ids": scope_new_word_ids,
            "known_word_ids": scope_known_word_ids,
            "scope_violation_count": scope_violation_count,
            "regen_attempts": scope_regen_attempts,
            "fallback_count": scope_fallback_count,
            "scope": {
                "version": scope_version,
                "enabled": scope_enabled,
                "source": scope_source,
                "requested_allowed_word_ids": requested_allowed_strs,
                "focus_word_ids": scope_focus_word_ids,
                "allowed_word_ids": scope_allowed_word_ids,
                "introduced_word_ids": scope_introduced_word_ids,
                "new_word_ids": scope_new_word_ids,
                "known_word_ids": scope_known_word_ids,
            },
            "generation": {
                "scope_violation_count": scope_violation_count,
                "regen_attempts": scope_regen_attempts,
                "fallback_count": scope_fallback_count,
            },
            "hsk1_pack": {
                "applied": hsk1_pack_circle is not None,
                "unit_id": hsk1_pack_circle.get("unit_id") if hsk1_pack_circle else None,
                "circle_id": hsk1_pack_circle.get("circle_id") if hsk1_pack_circle else None,
                "circle_title": hsk1_pack_circle.get("circle_title") if hsk1_pack_circle else None,
                "candidate_pool_size": (
                    hsk1_pack_circle.get("candidate_pool_size") if hsk1_pack_circle else None
                ),
                "target_word_count": (
                    hsk1_pack_circle.get("target_word_count") if hsk1_pack_circle else None
                ),
                "target_exercise_count": (
                    hsk1_pack_circle.get("target_exercise_count") if hsk1_pack_circle else None
                ),
                "ring_slots": ring_slots,
                "forced_word_ids": forced_strs if hsk1_pack_circle else [],
                "sense_locked_words": sorted(hsk1_pack_sense_by_word.keys()),
                "mix_enforcement": circle_mix_result,
                "remediation_mode": remediation_mode,
                "remediation_reason": remediation_reason,
                "suggested_media_slot": suggested_media_slot,
            },
            "violations": violations,
        }
    )


# ============================================================
# GET /api/v2/brain/summary
# ============================================================

@router.get("/summary", response_model=BrainSummary)
async def get_summary(
    token_user_id: str = Depends(get_user_id)
):
    """Get high-level stats for Dashboard."""
    user_id = token_user_id
    conn = get_db()
    
    # 1. Due Count
    now = datetime.utcnow().isoformat()
    due_status = _count_due_reviews(conn, user_id, "zh")
    due_count = int(due_status.get("due_count", 0))
    hard_due_count = int(due_status.get("hard_due_count", 0))
    soft_due_count = int(due_status.get("soft_due_count", 0))
    
    # 2. Next Review
    row_next = conn.execute("""
        SELECT MIN(next_review_at) FROM user_word_mastery 
        WHERE user_id = ? AND next_review_at > datetime('now')
    """, [user_id]).fetchone()
    next_at = row_next[0] if row_next and row_next[0] else None
    
    # 3. Learn Available (real count of non-mastered words in mastery table)
    row_learn = conn.execute("""
        SELECT COUNT(*) FROM user_word_mastery
        WHERE user_id = ?
          AND COALESCE(mastery_state, 'UNKNOWN') NOT IN ('MASTERED', 'MASTERED_PENDING_REVIEW')
    """, [user_id]).fetchone()
    learn_count = row_learn[0] if row_learn else 0
    
    return BrainSummary(
        due_count=due_count,
        review_due_count=hard_due_count,
        hard_due_count=hard_due_count,
        soft_due_count=soft_due_count,
        learn_available_count=learn_count,
        next_review_at=next_at,
        has_active_mission=False,
        server_time=now
    )


# ============================================================
# GET /api/v2/brain/unit/{unit_id}/intro
# ============================================================

@router.get("/unit/{unit_id}/intro", response_model=UnitIntroResponse)
async def get_unit_intro_endpoint(
    unit_id: str,
    token_user_id: str = Depends(get_user_id)
):
    """Get the audio priming content for a unit."""
    conn = get_db()
    row = conn.execute("SELECT * FROM unit_intros WHERE unit_id = ?", [unit_id]).fetchone()
    
    if not row:
        raise HTTPException(status_code=404, detail="Unit intro not found")
        
    return UnitIntroResponse(
        unit_id=row['unit_id'],
        audio_url=row['audio_url'],
        script_hanzi=row['script_hanzi'],
        script_pinyin=row['script_pinyin'],
        translation=row['translation'],
        target_words=json.loads(row['target_words']) if row['target_words'] else []
    )


# ============================================================
# POST /api/v2/brain/submit
# ============================================================

@router.post("/submit", response_model=SubmitResponse)
async def submit_exercise(
    request: SubmitRequest,
    token_user_id: str = Depends(get_user_id)
):
    """Process exercise submission with atomic transaction and extended validation."""
    if request.user_id != token_user_id:
        raise HTTPException(status_code=403, detail="User ID mismatch")

    conn = get_db()
    
    # 1. Check idempotency BEFORE transaction (mission-scoped)
    if request.idempotency_key:
        existing = conn.execute("""
            SELECT id FROM user_attempts
            WHERE user_id = ? AND mission_id = ? AND idempotency_key = ?
        """, [request.user_id, request.mission_id, request.idempotency_key]).fetchone()
        
        if existing:
            return SubmitResponse(
                accepted=True,
                idempotent_hit=True,
                next_action="continue"
            )
    
    # 2. Parse plan_slot_id and extract review_instance_id
    try:
        review_instance_id, focus, difficulty = parse_plan_slot_id(request.plan_slot_id)
        slot_key = make_slot_key(focus, difficulty)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=f"Invalid plan_slot_id: {e}")
    
    skill = FOCUS_TO_SKILL.get(focus, focus)
    resolved_sense_id = _resolve_submit_sense_id(conn, request)
    
    # BEGIN ATOMIC TRANSACTION
    try:
        # 3. Extended slot validation
        progress_row = None
        if resolved_sense_id:
            progress_row = conn.execute(
                """
                SELECT required_slots, passed_slots, stage
                FROM user_sense_stage_progress
                WHERE user_id = ? AND language_code = ? AND sense_id = ?
                  AND review_instance_id = ?
                """,
                [
                    request.user_id,
                    request.language_code,
                    resolved_sense_id,
                    review_instance_id,
                ],
            ).fetchone()

        word_progress_row = conn.execute(
            """
            SELECT required_slots, passed_slots, stage
            FROM user_word_stage_progress
            WHERE user_id = ? AND language_code = ? AND word_id = ?
              AND review_instance_id = ?
            """,
            [
                request.user_id,
                request.language_code,
                request.word_id,
                review_instance_id,
            ],
        ).fetchone()

        if progress_row is None and word_progress_row is not None and resolved_sense_id:
            # Seed sense-stage row from the existing word-stage row for compatibility.
            _ensure_sense_stage_progress_row(
                conn=conn,
                user_id=request.user_id,
                language_code=request.language_code,
                word_id=request.word_id,
                sense_id=resolved_sense_id,
                review_instance_id=review_instance_id,
                stage=int(word_progress_row[2] or 0),
                required_slots_json=str(word_progress_row[0] or "[]"),
                passed_slots_json=str(word_progress_row[1] or "[]"),
                failed_attempts=0,
            )
            progress_row = conn.execute(
                """
                SELECT required_slots, passed_slots, stage
                FROM user_sense_stage_progress
                WHERE user_id = ? AND language_code = ? AND sense_id = ?
                  AND review_instance_id = ?
                """,
                [
                    request.user_id,
                    request.language_code,
                    resolved_sense_id,
                    review_instance_id,
                ],
            ).fetchone()

        if progress_row is None:
            progress_row = word_progress_row
        
        if not progress_row:
            raise HTTPException(status_code=404, detail=f"Review instance not found: {review_instance_id}")
        
        required = set(json.loads(progress_row[0]))
        passed = set(json.loads(progress_row[1]))
        stored_stage = progress_row[2]
        
        # Validation: slot_key must be in required_slots
        if slot_key not in required:
            raise HTTPException(status_code=400, detail=f"Slot key not in required_slots: {slot_key}")
        
        # Validation: slot already passed? (no-op, return success)
        if slot_key in passed:
            return SubmitResponse(
                accepted=True,
                idempotent_hit=True,  # Treat as idempotent hit
                skill_updated=skill,
                slots_remaining=list(required - passed),
                next_action="continue"
            )
        
        # Validation: verify stage matches current mastery stage
        if resolved_sense_id:
            mastery_row = _ensure_sense_mastery_row(
                conn=conn,
                user_id=request.user_id,
                language_code=request.language_code,
                word_id=request.word_id,
                sense_id=resolved_sense_id,
            )
        else:
            mastery_row = conn.execute(
                """
                SELECT recognition, listening, production, usage, mastery_state, pending_since, srs_stage
                FROM user_word_mastery
                WHERE user_id = ? AND language_code = ? AND word_id = ?
                """,
                [request.user_id, request.language_code, request.word_id],
            ).fetchone()
        
        if not mastery_row:
            raise HTTPException(status_code=404, detail="Mastery record not found")
        
        # Read by column names (sense rows include `writing`, word rows do not).
        current_stage = int(mastery_row["srs_stage"] or 0)

        # NOTE: We allow stored_stage != current_stage for race conditions
        # (submission came after stage update), but we base updates on CURRENT state.
        current_score = int(mastery_row[skill] or 0)
        current_state = _normalize_mastery_state_value(mastery_row["mastery_state"])
        pending_since = mastery_row["pending_since"]
        guard = _too_fast_guard(
            conn=conn,
            user_id=request.user_id,
            language_code=request.language_code,
            exercise_id=request.exercise_id,
            latency_ms=request.latency_ms,
        )
        feedback_flags: Dict[str, Any] = {}
        scored_correct = bool(request.is_correct)
        if scored_correct and bool(guard.get("triggered")):
            scored_correct = False
            feedback_flags["too_fast_guard"] = {
                "triggered": True,
                "streak": int(guard.get("streak") or 0),
                "threshold_ms": int(guard.get("threshold_ms") or TOO_FAST_BASE_MS),
                "exercise_type": str(guard.get("exercise_type") or ""),
                "message": "Slow down for mastery credit",
            }
        # 4. Compute skill update
        session_failures = conn.execute("""
            SELECT COUNT(*) FROM user_attempts
            WHERE user_id = ? AND word_id = ? AND is_correct = 0
              AND created_at > datetime('now', '-30 minutes')
        """, [request.user_id, request.word_id]).fetchone()[0]
        
        delta = compute_skill_delta(difficulty, scored_correct, request.latency_ms, session_failures)
        new_score = update_skill_score(current_score, delta)
        
        # 6. Build updated vector
        vector = MasteryVector(
            recognition=int(mastery_row["recognition"] or 0),
            listening=int(mastery_row["listening"] or 0),
            production=int(mastery_row["production"] or 0),
            usage=int(mastery_row["usage"] or 0),
        )
        setattr(vector, skill, new_score)
        
        # 7. Compute state transition
        new_state = current_state
        new_pending_since = pending_since
        mastery_gate_passed: Optional[bool] = None
        mastery_gate_reasons: List[str] = []
        
        if current_state == STATE_PRACTICING or current_state == STATE_LEARNING:
            if scored_correct and is_mastery_criteria_met(vector):
                gate = _mastery_gate_snapshot(
                    conn=conn,
                    user_id=request.user_id,
                    language_code=request.language_code,
                    word_id=request.word_id,
                    plan_slot_id=request.plan_slot_id,
                    sense_id=resolved_sense_id,
                    is_correct=scored_correct,
                )
                mastery_gate_passed = bool(gate.get("passed"))
                mastery_gate_reasons = list(gate.get("reasons") or [])
                if mastery_gate_passed:
                    new_state = STATE_MASTERED_PENDING
                    new_pending_since = datetime.now().isoformat()
            elif scored_correct:
                mastery_gate_passed = False
                mastery_gate_reasons = ["mastery_threshold_not_met"]
        elif current_state == STATE_MASTERED_PENDING:
            if scored_correct:
                if can_transition_to_mastered(pending_since):
                    new_state = STATE_MASTERED
                    new_pending_since = None
            else:
                new_state = STATE_PRACTICING
                new_pending_since = None
        
        # 8. Update mastery table
        if resolved_sense_id:
            conn.execute(
                f"""
                UPDATE user_sense_mastery
                SET {skill} = ?, mastery_state = ?, pending_since = ?, updated_at = datetime('now')
                WHERE user_id = ? AND language_code = ? AND sense_id = ?
                """,
                [
                    new_score,
                    new_state,
                    new_pending_since,
                    request.user_id,
                    request.language_code,
                    resolved_sense_id,
                ],
            )

        # Compatibility mirror during migration: keep word-level state in sync.
        conn.execute(
            f"""
            UPDATE user_word_mastery
            SET {skill} = ?, mastery_state = ?, pending_since = ?, updated_at = datetime('now')
            WHERE user_id = ? AND language_code = ? AND word_id = ?
            """,
            [
                new_score,
                new_state,
                new_pending_since,
                request.user_id,
                request.language_code,
                request.word_id,
            ],
        )
        
        # 9. Update passed_slots with race-safe conditional update
        slots_remaining = []
        stage_complete = False
        new_stage = None
        next_review_at = None
        
        if scored_correct:
            passed.add(slot_key)
        
        passed_slots_json = json.dumps(list(passed))
        if resolved_sense_id:
            conn.execute(
                """
                UPDATE user_sense_stage_progress
                SET passed_slots = ?, updated_at = datetime('now')
                WHERE user_id = ? AND language_code = ? AND sense_id = ? AND review_instance_id = ?
                """,
                [
                    passed_slots_json,
                    request.user_id,
                    request.language_code,
                    resolved_sense_id,
                    review_instance_id,
                ],
            )

        conn.execute(
            """
            UPDATE user_word_stage_progress
            SET passed_slots = ?, updated_at = datetime('now')
            WHERE user_id = ? AND language_code = ? AND word_id = ? AND review_instance_id = ?
            """,
            [
                passed_slots_json,
                request.user_id,
                request.language_code,
                request.word_id,
                review_instance_id,
            ],
        )
        
        # 10. Check stage completion
        if required.issubset(passed):
            stage_complete = True
            new_stage = stored_stage + 1
            interval_hours = get_interval_hours(new_stage, is_correct=True)
            next_review_at = (datetime.now() + timedelta(hours=interval_hours)).isoformat()

            if resolved_sense_id:
                conn.execute(
                    """
                    UPDATE user_sense_mastery
                    SET srs_stage = ?, next_review_at = ?, updated_at = datetime('now')
                    WHERE user_id = ? AND language_code = ? AND sense_id = ?
                    """,
                    [
                        new_stage,
                        next_review_at,
                        request.user_id,
                        request.language_code,
                        resolved_sense_id,
                    ],
                )

            conn.execute(
                """
                UPDATE user_word_mastery
                SET srs_stage = ?, next_review_at = ?
                WHERE user_id = ? AND language_code = ? AND word_id = ?
                """,
                [new_stage, next_review_at, request.user_id, request.language_code, request.word_id],
            )
        else:
            slots_remaining = list(required - passed)

        attempt_meta_json: Optional[str] = None
        knowledge_state: Optional[str] = None
        knowledge_confidence: Optional[float] = None
        if request.attempt_meta:
            try:
                attempt_meta_json = json.dumps(
                    request.attempt_meta,
                    ensure_ascii=False,
                    separators=(",", ":"),
                )
                signal = request.attempt_meta.get("knowledge_signal")
                if isinstance(signal, dict):
                    raw_state = signal.get("knowledge_state")
                    if isinstance(raw_state, str):
                        state = raw_state.strip().lower()
                        if state in {"knows", "learning", "struggling"}:
                            knowledge_state = state
                    raw_confidence = signal.get("confidence")
                    if isinstance(raw_confidence, (int, float)):
                        knowledge_confidence = float(raw_confidence)
            except Exception:
                # Keep submit resilient even if client metadata is malformed.
                attempt_meta_json = None
                knowledge_state = None
                knowledge_confidence = None

        # 11. Record attempt with idempotency_key
        conn.execute("""
            INSERT INTO user_attempts
                (user_id, language_code, word_id, exercise_id, mission_id,
                 plan_slot_id, skill, is_correct, latency_ms, idempotency_key, sense_id,
                 attempt_meta_json, knowledge_state, knowledge_confidence)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, [
            request.user_id, request.language_code, request.word_id,
            request.exercise_id, request.mission_id, request.plan_slot_id,
            skill, 1 if scored_correct else 0, request.latency_ms,
            request.idempotency_key, resolved_sense_id, attempt_meta_json,
            knowledge_state, knowledge_confidence
        ])
        
        # 12. Update exercise history
        conn.execute("""
            INSERT INTO user_exercise_history
                (user_id, language_code, exercise_id, mission_id, last_seen_at, times_seen, last_correct)
            VALUES (?, ?, ?, ?, datetime('now'), 1, ?)
            ON CONFLICT(user_id, language_code, exercise_id) DO UPDATE SET
                mission_id = excluded.mission_id,
                last_seen_at = excluded.last_seen_at,
                times_seen = times_seen + 1,
                last_correct = excluded.last_correct
        """, [request.user_id, request.language_code, request.exercise_id, 
              request.mission_id, 1 if scored_correct else 0])
        
        # COMMIT TRANSACTION
        conn.commit()
        
        return SubmitResponse(
            accepted=True,
            skill_updated=skill,
            skill_score=new_score,
            skill_display=new_score // 20,
            mastery_state=str(new_state),
            stage_complete=stage_complete,
            new_stage=new_stage,
            slots_remaining=slots_remaining,
            next_review_at=next_review_at,
            next_action="complete" if stage_complete else "continue",
            mastery_gate_passed=mastery_gate_passed,
            mastery_gate_reasons=mastery_gate_reasons,
            feedback_flags=feedback_flags,
        )
    
    except HTTPException:
        conn.rollback()
        raise
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=f"Transaction failed: {str(e)}")


# ============================================================
# TEST ENDPOINT
# ============================================================

@router.get("/health")
async def health():
    return {"status": "ok", "version": "v1.1-unified"}
