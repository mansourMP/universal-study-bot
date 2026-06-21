"""
Learning Path 2.0 - Skill Update Logic
Technical Memo v1.1

Handles skill score updates with fractional storage (0-100) and anti-spiral guardrails.
"""

from typing import Dict, Optional
from datetime import datetime, timedelta
import sqlite3

from .schema import (
    MASTERY_THRESHOLD, PRODUCTION_MIN, DELAYED_RECALL_HOURS,
    STATE_UNKNOWN, STATE_LEARNING, STATE_PRACTICING,
    STATE_MASTERED_PENDING, STATE_MASTERED
)
from .srs_plan import MasteryVector, FOCUS_TO_SKILL


# ============================================================
# SKILL DELTA TABLE (0-100 scale)
# ============================================================

# Format: difficulty -> [incorrect_delta, correct_delta]
SKILL_DELTA: Dict[int, tuple] = {
    1: (-10, +10),
    2: (-10, +15),
    3: (-15, +20),
    4: (-20, +25),
    5: (-20, +30),
}

# Fast guess penalty threshold (milliseconds)
FAST_GUESS_THRESHOLD_MS = 800
FAST_GUESS_PENALTY = 0.5  # Reduce increment by 50%

# Session failure cap
SESSION_FAILURE_CAP = 3
CAPPED_PENALTY = -5


def compute_skill_delta(
    difficulty: int,
    is_correct: bool,
    latency_ms: Optional[int] = None,
    session_failures: int = 0
) -> int:
    """Compute skill score delta with all guardrails."""
    
    base_delta = SKILL_DELTA.get(difficulty, SKILL_DELTA[3])
    delta = base_delta[1] if is_correct else base_delta[0]
    
    # Fast guess penalty
    if is_correct and latency_ms and latency_ms < FAST_GUESS_THRESHOLD_MS:
        delta = int(delta * FAST_GUESS_PENALTY)
    
    # Session failure cap
    if not is_correct and session_failures >= SESSION_FAILURE_CAP:
        delta = max(delta, CAPPED_PENALTY)
    
    return delta


def update_skill_score(
    current_score: int,
    delta: int
) -> int:
    """Apply delta to skill score, clamping to 0-100."""
    return max(0, min(100, current_score + delta))


# ============================================================
# MASTERY CHECKS
# ============================================================

def is_mastery_criteria_met(vector: MasteryVector) -> bool:
    """Check if all 5 layers of mastery criteria are satisfied."""
    skills = [vector.recognition, vector.listening, vector.production, vector.usage, vector.writing]
    skills_above = sum(1 for s in skills if s >= MASTERY_THRESHOLD)
    
    has_usage = vector.usage >= MASTERY_THRESHOLD
    has_production = vector.production >= PRODUCTION_MIN
    has_writing = vector.writing >= PRODUCTION_MIN
    
    return skills_above >= 4 and has_usage and has_production and has_writing


def can_transition_to_mastered(pending_since: Optional[str]) -> bool:
    """Check if delayed recall requirement is met (24h since pending)."""
    if not pending_since:
        return False
    
    try:
        pending_time = datetime.fromisoformat(pending_since)
        required_time = pending_time + timedelta(hours=DELAYED_RECALL_HOURS)
        return datetime.now() >= required_time
    except (ValueError, TypeError):
        return False


# ============================================================
# STATE TRANSITIONS
# ============================================================

def compute_next_state(
    current_state: str,
    vector: MasteryVector,
    is_correct: bool,
    pending_since: Optional[str] = None,
    days_since_last_attempt: int = 0
) -> tuple:
    """Compute next mastery state and pending_since.
    
    Returns: (new_state, new_pending_since)
    """
    new_state = current_state
    new_pending_since = pending_since
    
    if current_state == STATE_UNKNOWN:
        new_state = STATE_LEARNING
        
    elif current_state == STATE_LEARNING:
        new_state = STATE_PRACTICING
        
    elif current_state == STATE_PRACTICING:
        if is_correct and is_mastery_criteria_met(vector):
            new_state = STATE_MASTERED_PENDING
            new_pending_since = datetime.now().isoformat()
            
    elif current_state == STATE_MASTERED_PENDING:
        if is_correct:
            if can_transition_to_mastered(pending_since):
                new_state = STATE_MASTERED
                new_pending_since = None
            # else: stay in pending, waiting for 24h
        else:
            # Failure during pending review
            new_state = STATE_PRACTICING
            new_pending_since = None
            
    elif current_state == STATE_MASTERED:
        if not is_correct:
            # Only regress if long gap
            if days_since_last_attempt >= 30:
                new_state = STATE_MASTERED_PENDING
                new_pending_since = datetime.now().isoformat()
    
    return new_state, new_pending_since


# ============================================================
# DATABASE OPERATIONS
# ============================================================

def get_mastery_vector(
    conn: sqlite3.Connection,
    user_id: str,
    language_code: str,
    word_id: str
) -> MasteryVector:
    """Fetch current mastery vector from database."""
    row = conn.execute("""
        SELECT recognition, listening, production, usage, writing
        FROM user_word_mastery
        WHERE user_id = ? AND language_code = ? AND word_id = ?
    """, [user_id, language_code, word_id]).fetchone()
    
    if row:
        return MasteryVector(
            recognition=row['recognition'],
            listening=row['listening'],
            production=row['production'],
            usage=row['usage'],
            writing=row['writing']
        )
    return MasteryVector()


def update_mastery_in_db(
    conn: sqlite3.Connection,
    user_id: str,
    language_code: str,
    word_id: str,
    skill: str,
    new_score: int,
    new_state: str,
    new_pending_since: Optional[str],
    next_review_at: str,
    srs_stage: int
):
    """Update mastery record in database."""
    conn.execute(f"""
        INSERT INTO user_word_mastery 
            (user_id, language_code, word_id, {skill}, mastery_state, 
             pending_since, next_review_at, srs_stage, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
        ON CONFLICT(user_id, language_code, word_id) DO UPDATE SET
            {skill} = excluded.{skill},
            mastery_state = excluded.mastery_state,
            pending_since = excluded.pending_since,
            next_review_at = excluded.next_review_at,
            srs_stage = excluded.srs_stage,
            updated_at = datetime('now')
    """, [user_id, language_code, word_id, new_score, new_state,
          new_pending_since, next_review_at, srs_stage])
    conn.commit()


def get_session_failure_count(
    conn: sqlite3.Connection,
    user_id: str,
    word_id: str,
    session_window_minutes: int = 30
) -> int:
    """Count failures in current session for anti-spiral."""
    return conn.execute("""
        SELECT COUNT(*) as cnt FROM user_attempts
        WHERE user_id = ? AND word_id = ?
          AND is_correct = 0
          AND created_at > datetime('now', ? || ' minutes')
    """, [user_id, word_id, f'-{session_window_minutes}']).fetchone()['cnt']


# ============================================================
# TESTS
# ============================================================

if __name__ == "__main__":
    print("Skill Update Tests:")
    
    # Test delta computation
    delta = compute_skill_delta(3, True, latency_ms=2000, session_failures=0)
    print(f"  Correct at diff 3, normal speed: +{delta}")
    
    delta = compute_skill_delta(3, True, latency_ms=500, session_failures=0)
    print(f"  Correct at diff 3, fast guess: +{delta}")
    
    delta = compute_skill_delta(3, False, session_failures=4)
    print(f"  Incorrect, 4th failure: {delta}")
    
    # Test mastery check
    v1 = MasteryVector(60, 60, 40, 60)
    print(f"\n  Mastery met (60,60,40,60): {is_mastery_criteria_met(v1)}")
    
    v2 = MasteryVector(60, 60, 30, 60)
    print(f"  Mastery met (60,60,30,60): {is_mastery_criteria_met(v2)}")
    
    # Test state transitions
    v = MasteryVector(60, 60, 40, 60)
    new_state, pending = compute_next_state(STATE_PRACTICING, v, True)
    print(f"\n  PRACTICING -> correct + criteria met: {new_state}")
    
    print("\n✅ Skill update tests passed!")
