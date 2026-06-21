import os
import json
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Body
from typing import List, Optional, Dict, Any
from auth import get_user_id


# ----------------------------------------------------------------------
# BRAIN INTEGRATION (The Engine)
# ----------------------------------------------------------------------
import sqlite3
from pathlib import Path
from learning_path.brain_selector import BrainSelector
from learning_path.schema import init_database

router = APIRouter(prefix="/api/v2/path", tags=["Learning Path"])

# Constants
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
_hsk1_circle_pack_cache: Optional[Dict[str, Any]] = None
_hsk1_unit_001_gold_cache: Optional[Dict[str, Any]] = None
_db_runtime_verified = False

def _get_brain_selector():
    """Helper to get Brain instance."""
    global _db_runtime_verified
    db_path = Path(__file__).parent.parent.parent / "learning_path.db"
    if not _db_runtime_verified:
        # Ensure additive migrations (e.g., sentences.hanzi + mastery normalization)
        # are applied at least once for this process.
        bootstrap_conn = init_database(db_path)
        bootstrap_conn.close()
        _db_runtime_verified = True
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    return BrainSelector(conn), conn

def _format_word_id(raw_id):
    """Ensure word ID is in W00001 format."""
    s_id = str(raw_id)
    if s_id.startswith('W'):
        return s_id
    if s_id.isdigit():
        return f"W{int(s_id):05d}"
    return s_id


def _load_hsk1_circle_pack() -> Optional[Dict[str, Any]]:
    global _hsk1_circle_pack_cache
    if _hsk1_circle_pack_cache is not None:
        return _hsk1_circle_pack_cache
    try:
        pack_path = os.path.join(CURRENT_DIR, "..", "..", "..", "docs", "specs", "hsk1_unit_circle_pack_v1.json")
        if not os.path.exists(pack_path):
            return None
        with open(pack_path, "r", encoding="utf-8") as f:
            _hsk1_circle_pack_cache = json.load(f)
        return _hsk1_circle_pack_cache
    except Exception:
        _hsk1_circle_pack_cache = None
        return None


def _load_hsk1_unit_001_gold() -> Optional[Dict[str, Any]]:
    global _hsk1_unit_001_gold_cache
    if _hsk1_unit_001_gold_cache is not None:
        return _hsk1_unit_001_gold_cache
    try:
        gold_path = os.path.join(
            CURRENT_DIR, "..", "..", "..", "docs", "specs", "hsk1_unit_001_gold_v1.json"
        )
        if not os.path.exists(gold_path):
            return None
        with open(gold_path, "r", encoding="utf-8") as f:
            _hsk1_unit_001_gold_cache = json.load(f)
        return _hsk1_unit_001_gold_cache
    except Exception:
        _hsk1_unit_001_gold_cache = None
        return None


def _normalize_level_key(raw_level: str) -> str:
    value = str(raw_level or "").strip().upper()
    if not value:
        return "HSK1"
    if value.startswith("HSK"):
        digits = "".join(ch for ch in value if ch.isdigit())
        if not digits:
            return "HSK1"
        n = max(1, min(7, int(digits)))
        return f"HSK{n}"
    if value.isdigit():
        n = max(1, min(7, int(value)))
        return f"HSK{n}"
    return "HSK1"


def _level_number(level_key: str) -> int:
    try:
        return int("".join(ch for ch in level_key if ch.isdigit()) or "1")
    except ValueError:
        return 1


def _realm_for_level(level_key: str) -> str:
    mapping = {
        "HSK1": "Stage 1 • Foundations",
        "HSK2": "Stage 2 • Everyday Communication",
        "HSK3": "Stage 3 • Social Navigation",
        "HSK4": "Stage 4 • Complex Contexts",
        "HSK5": "Stage 5 • Professional Fluency",
        "HSK6": "Stage 6 • Advanced Expression",
        "HSK7": "Stage 7-9 • Expert Band",
    }
    return mapping.get(level_key, f"{level_key} Path")


def _guide_for_level(level_key: str) -> str:
    if level_key in ("HSK1", "HSK2"):
        return "CHAR_HUAHUA"
    if level_key in ("HSK3", "HSK4"):
        return "CHAR_SHIFU"
    return "CHAR_LONGLONG"


def _lesson_templates() -> List[dict]:
    return [
        {
            "title": "Discover",
            "type": "intro",
            "mode": "learn",
            "skills": ["Reading", "Listening"],
            "minutes": 8,
            "objective": "Understand new words in clear context",
        },
        {
            "title": "Drill",
            "type": "practice",
            "mode": "learn",
            "skills": ["Reading", "Listening"],
            "minutes": 8,
            "objective": "Strengthen recognition and pronunciation",
        },
        {
            "title": "Use",
            "type": "practice",
            "mode": "practice",
            "skills": ["Speaking", "Reading"],
            "minutes": 8,
            "objective": "Start active recall and response building",
        },
        {
            "title": "Listen + Speak",
            "type": "listening",
            "mode": "practice",
            "skills": ["Listening", "Speaking"],
            "minutes": 8,
            "objective": "Train listening comprehension under variation",
        },
        {
            "title": "Apply",
            "type": "story",
            "mode": "apply",
            "skills": ["Reading", "Speaking"],
            "minutes": 8,
            "objective": "Apply vocabulary inside micro-dialogue or story",
        },
        {
            "title": "Review Mix",
            "type": "review",
            "mode": "review",
            "skills": ["Reading", "Listening", "Speaking"],
            "minutes": 8,
            "objective": "Reinforce weak words with adaptive review",
        },
        {
            "title": "Checkpoint",
            "type": "checkpoint",
            "mode": "checkpoint",
            "skills": ["Reading", "Listening", "Speaking", "Writing"],
            "minutes": 10,
            "objective": "Verify durable mastery before next unit",
        },
    ]


def _lesson_word_ids(unit_words: List[str], lesson_index: int, total_lessons: int) -> List[str]:
    if not unit_words:
        return []
    if len(unit_words) <= 5:
        return unit_words

    n = len(unit_words)
    first = max(1, n // 3)
    second = max(first + 1, (2 * n) // 3)

    if lesson_index == 1:
        return unit_words[:first]
    if lesson_index == 2:
        return unit_words[first:second] or unit_words[:first]
    if lesson_index == 3:
        return unit_words[second:] or unit_words[first:second] or unit_words[:first]
    if lesson_index == total_lessons:
        return unit_words
    # Mid circles use full unit set for deliberate spaced retrieval.
    return unit_words


def _hsk1_pack_templates_for_unit(unit_id: str) -> Optional[List[dict]]:
    # Gold override for live pilot testing of first unit.
    if unit_id == "UNIT_HSK1_001":
        gold = _load_hsk1_unit_001_gold()
        if isinstance(gold, dict):
            unit_payload = gold.get("unit")
            if isinstance(unit_payload, dict):
                circles = unit_payload.get("circles")
                if isinstance(circles, list) and len(circles) == 7:
                    templates: List[dict] = []
                    for idx, circle in enumerate(circles, start=1):
                        cid = str(circle.get("circle_id") or f"C{idx}")
                        title = str(circle.get("title") or f"Circle {idx}")
                        duration_sec = int(circle.get("duration_target_sec") or 240)
                        minutes = max(3, int(round(duration_sec / 60)))
                        focus_words = [str(w) for w in (circle.get("focus_word_ids") or []) if str(w).strip()]
                        role = str(circle.get("role") or "")
                        if cid in {"C1", "C4"} or role == "new":
                            ltype, mode, skills = "intro", "learn", ["Reading", "Listening"]
                        elif cid in {"C2", "C5"}:
                            ltype, mode, skills = "practice", "practice", ["Reading", "Listening", "Speaking"]
                        elif cid == "C3" or role == "speaking":
                            ltype, mode, skills = "speaking", "practice", ["Listening", "Speaking"]
                        elif cid == "C6" or role == "story_radio":
                            ltype, mode, skills = "story", "apply", ["Reading", "Listening", "Speaking"]
                        else:
                            ltype, mode, skills = "checkpoint", "checkpoint", ["Reading", "Listening", "Speaking", "Writing"]

                        templates.append(
                            {
                                "title": title,
                                "type": ltype,
                                "mode": mode,
                                "skills": skills,
                                "minutes": minutes,
                                "objective": str(circle.get("hook_start") or f"{title} ({cid})"),
                                "circle_id": cid,
                                "word_ids": focus_words,
                                "exercise_mix": {},
                                "target_exercise_count": int(
                                    circle.get("target_exercise_count") or 10
                                ),
                            }
                        )
                    return templates

    pack = _load_hsk1_circle_pack()
    if not pack:
        return None
    units = pack.get("units")
    if not isinstance(units, list):
        return None

    unit_payload = None
    for unit in units:
        if not isinstance(unit, dict):
            continue
        if str(unit.get("unit_id") or "") == unit_id:
            unit_payload = unit
            break
    if not unit_payload:
        return None

    circles = unit_payload.get("circles")
    if not isinstance(circles, list) or len(circles) != 7:
        return None

    templates: List[dict] = []
    for idx, circle in enumerate(circles, start=1):
        cid = str(circle.get("circle_id") or f"C{idx}")
        title = str(circle.get("title") or f"Circle {idx}")
        duration_sec = int(circle.get("duration_target_sec") or 240)
        minutes = max(3, int(round(duration_sec / 60)))
        focus_words = [str(w) for w in (circle.get("focus_word_ids") or []) if str(w).strip()]
        mix = dict(circle.get("exercise_mix") or {})
        if cid in {"C1", "C4"}:
            ltype, mode, skills = "intro", "learn", ["Reading", "Listening"]
        elif cid in {"C2", "C5"}:
            ltype, mode, skills = "practice", "practice", ["Reading", "Listening", "Speaking"]
        elif cid == "C3":
            ltype, mode, skills = "speaking", "practice", ["Listening", "Speaking"]
        elif cid == "C6":
            ltype, mode, skills = "review", "review", ["Reading", "Listening", "Speaking"]
        else:
            ltype, mode, skills = "checkpoint", "checkpoint", ["Reading", "Listening", "Speaking", "Writing"]

        templates.append(
            {
                "title": title,
                "type": ltype,
                "mode": mode,
                "skills": skills,
                "minutes": minutes,
                "objective": f"{title} ({cid})",
                "circle_id": cid,
                "word_ids": focus_words,
                "exercise_mix": mix,
                "target_exercise_count": int(circle.get("target_exercise_count") or 10),
            }
        )
    return templates

# ----------------------------------------------------------------------
# PATH API (The Map)
# ----------------------------------------------------------------------

@router.get("/config/{subject_id}")
async def get_subject_config(subject_id: str):
    """Returns the configuration for a specific subject (skills, UI, etc)."""
    try:
        config_path = os.path.join(CURRENT_DIR, "..", "..", "subjects", f"{subject_id}.json")
        if not os.path.exists(config_path):
            # Fallback to zh if not found
            config_path = os.path.join(CURRENT_DIR, "..", "..", "subjects", "zh.json")
            
        if not os.path.exists(config_path):
            raise HTTPException(status_code=404, detail=f"Config not found for {subject_id}")
            
        with open(config_path, 'r') as f:
            return json.load(f)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/journey")
async def get_journey(
    user_id: str = Depends(get_user_id),
    target_lang: str = "zh",
    goal: str = "hsk",
    level: str = "1",
):
    """
    Returns DB-driven learning journey (HSK3.0 runtime only).
    Legacy realm manifests are intentionally ignored here.
    """
    try:
        # Keep journey scoped to Chinese for now.
        if target_lang != "zh":
            return {"nodes": []}

        level_key = _normalize_level_key(level)

        selector, conn = _get_brain_selector()
        try:
            units_rows = conn.execute(
                """
                SELECT id, unit_number, title, description
                FROM units
                WHERE level = ? AND id LIKE 'UNIT_HSK%_%'
                ORDER BY unit_number ASC, id ASC
                """,
                [level_key],
            ).fetchall()

            # Fallback: discover from unit_concepts if units table is incomplete.
            if not units_rows:
                prefix = f"UNIT_{level_key}_%"
                units_rows = conn.execute(
                    """
                    WITH discovered AS (
                        SELECT DISTINCT unit_id
                        FROM unit_concepts
                        WHERE unit_id LIKE ?
                    )
                    SELECT
                        unit_id AS id,
                        CAST(substr(unit_id, -3) AS INTEGER) AS unit_number,
                        unit_id AS title,
                        '' AS description
                    FROM discovered
                    ORDER BY unit_number ASC, id ASC
                    """,
                    [prefix],
                ).fetchall()

            if not units_rows:
                return {"nodes": []}

            unit_ids = [str(r["id"]) for r in units_rows]
            batch_status = selector.get_batch_unit_status(
                user_id,
                target_lang,
                unit_ids,
            )

            placeholders = ",".join("?" for _ in unit_ids)
            words_rows = conn.execute(
                f"""
                SELECT unit_id, concept_id
                FROM unit_concepts
                WHERE unit_id IN ({placeholders})
                ORDER BY unit_id ASC, sequence ASC
                """,
                unit_ids,
            ).fetchall()

            words_by_unit: dict[str, list[str]] = {uid: [] for uid in unit_ids}
            for row in words_rows:
                uid = str(row["unit_id"])
                wid = _format_word_id(row["concept_id"])
                if uid in words_by_unit and wid not in words_by_unit[uid]:
                    words_by_unit[uid].append(wid)
            attempts_rows = conn.execute(
                """
                SELECT word_id, COUNT(*) AS c
                FROM user_attempts
                WHERE user_id = ? AND language_code = ?
                GROUP BY word_id
                """,
                [user_id, target_lang],
            ).fetchall()
            attempts_by_word: dict[str, int] = {}
            for row in attempts_rows:
                wid = _format_word_id(row["word_id"])
                attempts_by_word[wid] = int(row["c"] or 0)
        finally:
            conn.close()

        journey_nodes = []

        previous_unit_passed = True
        locked_units_count = 0
        max_locked_units = 2
        guide_id = _guide_for_level(level_key)
        realm_title = _realm_for_level(level_key)
        default_lesson_templates = _lesson_templates()

        for idx, unit_row in enumerate(units_rows):
            unit_id = str(unit_row["id"])
            unit_number = int(unit_row["unit_number"] or (idx + 1))
            unit_title_from_db = str(unit_row["title"] or "").strip()
            unit_desc_from_db = str(unit_row["description"] or "").strip()
            unit_words = words_by_unit.get(unit_id, [])
            if not unit_words:
                continue

            unit_brain_state = batch_status.get(
                unit_id,
                {"unlocked": False, "failing_count": len(unit_words)},
            )
            is_this_unit_mastered = bool(unit_brain_state.get("unlocked"))
            failing_count = int(unit_brain_state.get("failing_count", len(unit_words)))

            if is_this_unit_mastered:
                unit_status = "completed"
                unlock_reason = "mastered"
            elif previous_unit_passed:
                unit_status = "available"
                unlock_reason = "previous_completed"
            else:
                unit_status = "locked"
                unlock_reason = "previous_incomplete"
                locked_units_count += 1

            if unit_status == "locked" and locked_units_count > max_locked_units:
                break

            previous_unit_passed = is_this_unit_mastered

            lesson_templates = default_lesson_templates
            if level_key == "HSK1":
                pack_templates = _hsk1_pack_templates_for_unit(unit_id)
                if pack_templates:
                    lesson_templates = pack_templates

            total_words = max(1, len(unit_words))
            mastered_words = max(0, total_words - max(0, failing_count))
            progress_ratio = mastered_words / total_words
            current_lesson_index = min(
                len(lesson_templates) - 1,
                int(progress_ratio * len(lesson_templates)),
            )
            if level_key == "HSK1" and lesson_templates:
                has_circles = any(bool(t.get("circle_id")) for t in lesson_templates)
                if has_circles:
                    completed_flags: List[bool] = []
                    for template in lesson_templates:
                        focus_words = [
                            _format_word_id(w)
                            for w in (template.get("word_ids") or [])
                            if str(w).strip()
                        ]
                        if not focus_words:
                            completed_flags.append(False)
                            continue
                        attempts_total = sum(
                            int(attempts_by_word.get(wid, 0)) for wid in focus_words
                        )
                        distinct_attempted = sum(
                            1
                            for wid in focus_words
                            if int(attempts_by_word.get(wid, 0)) > 0
                        )
                        target_items = int(template.get("target_exercise_count") or 10)
                        min_attempts = max(3, int(round(target_items * 0.6)))
                        min_distinct = max(2, int(round(len(focus_words) * 0.35)))
                        completed_flags.append(
                            attempts_total >= min_attempts and distinct_attempted >= min_distinct
                        )
                    first_incomplete = next(
                        (i for i, done in enumerate(completed_flags) if not done),
                        len(completed_flags),
                    )
                    current_lesson_index = min(
                        len(lesson_templates) - 1,
                        first_incomplete,
                    )

            unit_title = unit_title_from_db or f"Unit {unit_number:03d}"
            unit_story = unit_desc_from_db or f"{realm_title} • Core vocabulary training"

            progressive_allowed_words: List[str] = []
            progressive_seen_words = set()

            for lesson_index, template in enumerate(lesson_templates, start=1):
                if unit_status == "completed":
                    lesson_status = "completed"
                elif unit_status == "locked":
                    lesson_status = "locked"
                elif level_key == "HSK1":
                    # Pilot behavior: keep all circles in the active HSK1 unit open.
                    # This avoids deadlocks while we refine strict per-circle completion signals.
                    local_idx = lesson_index - 1
                    if local_idx < current_lesson_index:
                        lesson_status = "completed"
                    else:
                        lesson_status = "review_due"
                else:
                    local_idx = lesson_index - 1
                    if local_idx < current_lesson_index:
                        lesson_status = "completed"
                    elif local_idx == current_lesson_index:
                        lesson_status = "review_due"
                    elif level_key == "HSK1" and local_idx == current_lesson_index + 1:
                        # Keep HSK1 circle flow moving: open one step ahead (Duolingo-like pacing).
                        lesson_status = "review_due"
                    else:
                        lesson_status = "locked"

                lesson_words = template.get("word_ids") or _lesson_word_ids(
                    unit_words,
                    lesson_index,
                    len(lesson_templates),
                )
                if not lesson_words:
                    lesson_words = unit_words[: min(5, len(unit_words))]

                circle_id = str(template.get("circle_id") or "")
                if level_key == "HSK1" and circle_id in {"C1", "C2", "C3", "C4", "C5"}:
                    for wid in lesson_words:
                        swid = str(wid).strip()
                        if not swid or swid in progressive_seen_words:
                            continue
                        progressive_seen_words.add(swid)
                        progressive_allowed_words.append(swid)

                if level_key == "HSK1" and circle_id in {"C6", "C7"}:
                    allowed_words_for_lesson = list(progressive_allowed_words or lesson_words)
                elif level_key == "HSK1" and circle_id in {"C1", "C2", "C3", "C4", "C5"}:
                    allowed_words_for_lesson = list(progressive_allowed_words or lesson_words)
                else:
                    allowed_words_for_lesson = [str(w) for w in lesson_words]

                journey_nodes.append(
                    {
                        "id": f"{unit_id}_L{lesson_index:02d}",
                        "lesson_id": unit_id,
                        "title": f"{template['title']}",
                        "subtitle": f"{unit_title} • {template['type'].title()} • {len(lesson_words)} words",
                        "type": template["type"],
                        "mode": template["mode"],
                        "level": _level_number(level_key),
                        "estimated_minutes": template["minutes"],
                        "guide_id": guide_id,
                        "guest_id": None,
                        "cultural": {
                            "setting": unit_title,
                            "story_context": unit_story,
                            "language_objective": template["objective"],
                        },
                        "status": lesson_status,
                        "unlock_reason": unlock_reason,
                        "mastery_summary": {
                            "failing_words": failing_count,
                            "known": mastered_words,
                            "total": total_words,
                        },
                        "metadata": {
                            "realm_id": level_key,
                            "realm_title": realm_title,
                            "unit_id": unit_id,
                            "unit_number": unit_number,
                            "unit_title": unit_title,
                            "lesson_number": lesson_index,
                            "title": template["title"],
                            "type": template["type"],
                            "skills": template["skills"],
                            "word_ids": lesson_words,
                            "allowed_word_ids": allowed_words_for_lesson,
                            "circle_id": template.get("circle_id"),
                            "exercise_mix": template.get("exercise_mix", {}),
                        },
                    }
                )

        return {"nodes": journey_nodes}

    except Exception as e:
        print(f"Error serving journey: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# ----------------------------------------------------------------------
# HELPER ENDPOINTS
# ----------------------------------------------------------------------

@router.get("/unit/{unit_id}/passage")
async def get_unit_passage(unit_id: str):
    """Returns Golden Passage (unchanged)."""
    try:
        unit_num = unit_id.split("_")[-1]
        filename = f"unit_{unit_num}_passage.json"
        passage_path = os.path.join(CURRENT_DIR, "..", "..", "content", "passages", filename)
        
        if not os.path.exists(passage_path):
            raise HTTPException(status_code=404, detail=f"Passage not found")
            
        with open(passage_path, 'r') as f:
            return json.load(f)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/activities/{node_id}")
async def get_activities(node_id: str):
    """DEPRECATED: Redirect to Brain."""
    return {
        "deprecated": True,
        "message": "Use POST /api/v2/brain/mission with intent=LEARN",
        "mission_config": {
            "intent": "LEARN",
            "forced_ids": [], # Client should fetch from node metadata
            "node_id": node_id
        }
    }

@router.get("/gate/{unit_id}")
async def check_gate(
    unit_id: str,
    user_id: str = Depends(get_user_id),
    language_code: str = "zh"
):
    """Direct Brain Gate Check."""
    selector, conn = _get_brain_selector()
    try:
        return selector.check_unit_gate(user_id, language_code, unit_id)
    finally:
        conn.close()


@router.get("/units/list")
async def get_units_list(
    level: str = "HSK1",
    user_id: str = Depends(get_user_id),
    language_code: str = "zh"
):
    """
    Get list of units with lock status and progress.
    
    Returns:
    {
      "units": [
        {
          "id": "UNIT_HSK1_001",
          "title": "Unit 001",
          "unit_number": 1,
          "description": "HSK1 core training block",
          "unlocked": true,
          "progress": 0.45,  // 45% of words mastered
          "word_count": 10,
          "failing_count": 5
        },
        ...
      ]
    }
    """
    selector, conn = _get_brain_selector()
    try:
        level_key = _normalize_level_key(level)
        # Fetch all units for the level
        units_rows = conn.execute("""
            SELECT id, unit_number
            , title, description
            FROM units
            WHERE level = ? AND id LIKE 'UNIT_HSK%_%'
            ORDER BY unit_number ASC
        """, [level_key]).fetchall()
        
        if not units_rows:
            return {"units": []}
        
        # Get unit IDs for batch status check
        unit_ids = [row[0] for row in units_rows]
        batch_status = selector.get_batch_unit_status(user_id, language_code, unit_ids)
        
        # Build response
        units_list = []
        for row in units_rows:
            unit_id, unit_num, unit_title_raw, unit_desc_raw = row
            status = batch_status.get(unit_id, {"unlocked": False, "failing_count": 0})
            
            # Get word count for this unit
            word_count_row = conn.execute("""
                SELECT COUNT(*) FROM unit_concepts WHERE unit_id = ?
            """, [unit_id]).fetchone()
            word_count = word_count_row[0] if word_count_row else 0
            
            # Calculate progress (words mastered / total words)
            mastered_count = word_count - status["failing_count"]
            progress = mastered_count / word_count if word_count > 0 else 0.0
            title_value = str(unit_title_raw or "").strip() or f"Unit {int(unit_num):03d}"
            desc_value = str(unit_desc_raw or "").strip() or f"{level_key} core training block"
            
            units_list.append({
                "id": unit_id,
                "title": title_value,
                "unit_number": unit_num,
                "description": desc_value,
                "learning_objectives": [],
                "unlocked": status["unlocked"],
                "progress": round(progress, 2),
                "word_count": word_count,
                "failing_count": status["failing_count"]
            })
        
        return {"units": units_list}
    
    finally:
        conn.close()
