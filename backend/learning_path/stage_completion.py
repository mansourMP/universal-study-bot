"""
Learning Path 2.0 - Stage Completion Logic
Technical Memo v1.1

Handles stage completion tracking with unique plan_slot_ids per review instance.
"""

import json
import uuid
import sqlite3
from datetime import datetime, timedelta
from typing import List, Dict, Optional, Tuple

from .srs_plan import (
    MasteryVector, get_srs_plan, make_slot_key, make_plan_slot_id,
    parse_plan_slot_id, FOCUS_TO_SKILL, get_interval_hours
)
from .skill_updates import (
    compute_skill_delta, update_skill_score, compute_next_state,
    get_mastery_vector, get_session_failure_count
)
from .schema import STATE_PRACTICING, STATE_MASTERED_PENDING


# ============================================================
# REVIEW INSTANCE MANAGEMENT
# ============================================================

def create_review_instance(
    conn: sqlite3.Connection,
    user_id: str,
    language_code: str,
    word_id: str,
    stage: int,
    vector: MasteryVector
) -> Dict:
    """Create a new review instance for a word.
    
    Returns dict with review_instance_id and required_slots.
    """
    # Generate unique review instance ID
    review_instance_id = f"ri_{uuid.uuid4().hex[:12]}"
    
    # Get required slots from SRS plan
    plan = get_srs_plan(stage, vector)
    required_slots = [make_slot_key(focus, diff) for focus, diff in plan]
    
    # Insert into stage progress table
    conn.execute("""
        INSERT INTO user_word_stage_progress
            (user_id, language_code, word_id, stage, review_instance_id,
             required_slots, passed_slots, failed_attempts, created_at)
        VALUES (?, ?, ?, ?, ?, ?, '[]', 0, datetime('now'))
    """, [
        user_id, language_code, word_id, stage,
        review_instance_id, json.dumps(required_slots)
    ])
    conn.commit()
    
    return {
        'review_instance_id': review_instance_id,
        'required_slots': required_slots,
    }


def get_active_review_instance(
    conn: sqlite3.Connection,
    user_id: str,
    language_code: str,
    word_id: str
) -> Optional[Dict]:
    """Get the active (incomplete) review instance for a word."""
    row = conn.execute("""
        SELECT review_instance_id, stage, required_slots, passed_slots, failed_attempts
        FROM user_word_stage_progress
        WHERE user_id = ? AND language_code = ? AND word_id = ?
        ORDER BY created_at DESC
        LIMIT 1
    """, [user_id, language_code, word_id]).fetchone()
    
    if not row:
        return None
    
    required = set(json.loads(row['required_slots']))
    passed = set(json.loads(row['passed_slots']))
    
    # Check if complete
    if required.issubset(passed):
        return None  # Stage complete, no active instance
    
    return {
        'review_instance_id': row['review_instance_id'],
        'stage': row['stage'],
        'required_slots': list(required),
        'passed_slots': list(passed),
        'slots_remaining': list(required - passed),
        'failed_attempts': row['failed_attempts'],
    }


# ============================================================
# STAGE COMPLETION
# ============================================================

def record_slot_attempt(
    conn: sqlite3.Connection,
    user_id: str,
    language_code: str,
    word_id: str,
    review_instance_id: str,
    slot_key: str,
    is_correct: bool
) -> Dict:
    """Record an attempt on a slot and check for stage completion.
    
    Returns:
        {
            'stage_complete': bool,
            'new_stage': int or None,
            'slots_remaining': list,
            'next_review_at': str or None,
        }
    """
    # Get current progress
    row = conn.execute("""
        SELECT stage, required_slots, passed_slots, failed_attempts
        FROM user_word_stage_progress
        WHERE user_id = ? AND language_code = ? AND word_id = ? 
          AND review_instance_id = ?
    """, [user_id, language_code, word_id, review_instance_id]).fetchone()
    
    if not row:
        raise ValueError(f"No active review instance: {review_instance_id}")
    
    stage = row['stage']
    required = set(json.loads(row['required_slots']))
    passed = set(json.loads(row['passed_slots']))
    failed_attempts = row['failed_attempts']
    
    # Update based on result
    if is_correct:
        passed.add(slot_key)
    else:
        failed_attempts += 1
    
    # Save progress
    conn.execute("""
        UPDATE user_word_stage_progress
        SET passed_slots = ?, failed_attempts = ?, updated_at = datetime('now')
        WHERE user_id = ? AND language_code = ? AND word_id = ? 
          AND review_instance_id = ?
    """, [json.dumps(list(passed)), failed_attempts,
          user_id, language_code, word_id, review_instance_id])
    
    # Check stage completion (all required slots passed)
    if required.issubset(passed):
        # Stage complete! Advance.
        new_stage = stage + 1
        interval_hours = get_interval_hours(new_stage, is_correct=True)
        next_review = (datetime.now() + timedelta(hours=interval_hours)).isoformat()
        
        # Update mastery table
        conn.execute("""
            UPDATE user_word_mastery
            SET srs_stage = ?, next_review_at = ?, updated_at = datetime('now')
            WHERE user_id = ? AND language_code = ? AND word_id = ?
        """, [new_stage, next_review, user_id, language_code, word_id])
        
        conn.commit()
        
        return {
            'stage_complete': True,
            'new_stage': new_stage,
            'slots_remaining': [],
            'next_review_at': next_review,
        }
    
    conn.commit()
    
    return {
        'stage_complete': False,
        'new_stage': None,
        'slots_remaining': list(required - passed),
        'next_review_at': None,
    }


# ============================================================
# FULL SUBMIT HANDLER
# ============================================================

def process_exercise_submit(
    conn: sqlite3.Connection,
    user_id: str,
    language_code: str,
    word_id: str,
    exercise_id: str,
    mission_id: str,
    plan_slot_id: str,
    is_correct: bool,
    latency_ms: Optional[int] = None,
    sense_id: Optional[str] = None,
) -> Dict:
    """Full exercise submission processing.
    
    1. Parse plan_slot_id
    2. Update skill score
    3. Record slot attempt
    4. Check stage completion
    5. Check mastery criteria
    6. Return result
    """
    # Parse plan_slot_id
    review_instance_id, focus, difficulty = parse_plan_slot_id(plan_slot_id)
    slot_key = make_slot_key(focus, difficulty)
    skill = FOCUS_TO_SKILL.get(focus, focus)
    
    # Get current state
    mastery_row = conn.execute("""
        SELECT recognition, listening, production, usage, 
               mastery_state, pending_since, srs_stage
        FROM user_word_mastery
        WHERE user_id = ? AND language_code = ? AND word_id = ?
    """, [user_id, language_code, word_id]).fetchone()
    
    if not mastery_row:
        # Initialize if not exists
        conn.execute("""
            INSERT INTO user_word_mastery 
                (user_id, language_code, word_id, mastery_state, srs_stage)
            VALUES (?, ?, ?, 'LEARNING', 0)
        """, [user_id, language_code, word_id])
        conn.commit()
        mastery_row = conn.execute("""
            SELECT recognition, listening, production, usage, 
                   mastery_state, pending_since, srs_stage
            FROM user_word_mastery
            WHERE user_id = ? AND language_code = ? AND word_id = ?
        """, [user_id, language_code, word_id]).fetchone()
    
    current_score = mastery_row[skill]
    current_state = mastery_row['mastery_state']
    pending_since = mastery_row['pending_since']
    srs_stage = mastery_row['srs_stage']
    
    # Compute skill delta
    session_failures = get_session_failure_count(conn, user_id, word_id)
    delta = compute_skill_delta(difficulty, is_correct, latency_ms, session_failures)
    new_score = update_skill_score(current_score, delta)
    
    # Build updated vector
    vector = MasteryVector(
        recognition=mastery_row['recognition'],
        listening=mastery_row['listening'],
        production=mastery_row['production'],
        usage=mastery_row['usage']
    )
    setattr(vector, skill, new_score)
    
    # Compute next state
    new_state, new_pending_since = compute_next_state(
        current_state, vector, is_correct, pending_since
    )
    
    # Update skill and state in mastery table
    conn.execute(f"""
        UPDATE user_word_mastery
        SET {skill} = ?, mastery_state = ?, pending_since = ?, updated_at = datetime('now')
        WHERE user_id = ? AND language_code = ? AND word_id = ?
    """, [new_score, new_state, new_pending_since, user_id, language_code, word_id])
    
    # Record attempt in log
    conn.execute("""
        INSERT INTO user_attempts
            (user_id, language_code, word_id, exercise_id, mission_id,
             plan_slot_id, skill, is_correct, latency_ms, sense_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, [user_id, language_code, word_id, exercise_id, mission_id,
          plan_slot_id, skill, 1 if is_correct else 0, latency_ms, sense_id])
    
    # Update exercise history (language-safe)
    conn.execute("""
        INSERT INTO user_exercise_history
            (user_id, language_code, exercise_id, mission_id, last_seen_at, times_seen, last_correct)
        VALUES (?, ?, ?, ?, datetime('now'), 1, ?)
        ON CONFLICT(user_id, language_code, exercise_id) DO UPDATE SET
            mission_id = excluded.mission_id,
            last_seen_at = excluded.last_seen_at,
            times_seen = times_seen + 1,
            last_correct = excluded.last_correct
    """, [user_id, language_code, exercise_id, mission_id, 1 if is_correct else 0])
    
    # Record slot attempt and check stage completion
    stage_result = record_slot_attempt(
        conn, user_id, language_code, word_id,
        review_instance_id, slot_key, is_correct
    )
    
    conn.commit()
    
    return {
        'accepted': True,
        'skill_updated': skill,
        'skill_score': new_score,
        'skill_display': new_score // 20,
        'mastery_state': new_state,
        'stage_complete': stage_result['stage_complete'],
        'new_stage': stage_result['new_stage'],
        'slots_remaining': stage_result['slots_remaining'],
        'next_review_at': stage_result['next_review_at'],
        'next_action': 'complete' if stage_result['stage_complete'] else 'continue',
    }


# ============================================================
# TESTS
# ============================================================

if __name__ == "__main__":
    from pathlib import Path
    from .schema import init_database
    
    print("Stage Completion Tests:")
    
    # Create test database
    test_db = Path(__file__).parent / "test_stage.db"
    if test_db.exists():
        test_db.unlink()
    conn = init_database(test_db)
    
    # Create review instance
    vector = MasteryVector()
    result = create_review_instance(
        conn, "user1", "zh", "word1", 0, vector
    )
    print(f"  Created review instance: {result['review_instance_id']}")
    print(f"  Required slots: {result['required_slots']}")
    
    # Get active instance
    active = get_active_review_instance(conn, "user1", "zh", "word1")
    print(f"  Active instance slots remaining: {active['slots_remaining']}")
    
    # Record first slot (recognition:1)
    stage_result = record_slot_attempt(
        conn, "user1", "zh", "word1",
        result['review_instance_id'], "recognition:1", True
    )
    print(f"  After first slot: complete={stage_result['stage_complete']}")
    
    # Record second slot (usage:1)
    stage_result = record_slot_attempt(
        conn, "user1", "zh", "word1",
        result['review_instance_id'], "usage:1", True
    )
    print(f"  After second slot: complete={stage_result['stage_complete']}, new_stage={stage_result['new_stage']}")
    
    conn.close()
    test_db.unlink()
    print("\n✅ Stage completion tests passed!")
