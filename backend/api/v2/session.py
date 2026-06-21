"""
Quick Study Session API - Batch Learning Endpoints
Allows users to learn 5-10 words in a single session instead of 1 word per lesson.
"""
from fastapi import APIRouter, Depends, HTTPException
from typing import List, Dict, Any, Optional
import sqlite3
import uuid
from datetime import datetime, timedelta
from pathlib import Path

# Import from backend modules (same pattern as path.py)
from auth import get_user_id
from learning_path.sense_store import get_primary_gloss
from learning_path.schema import init_database

# Database connection (same as other v2 APIs)
DB_PATH = Path(__file__).parent.parent / "learning_path.db"
_db_runtime_verified = False

def get_db() -> sqlite3.Connection:
    """Get database connection with row factory."""
    global _db_runtime_verified
    if not _db_runtime_verified:
        # Apply compatibility migrations once (legacy dbs may miss these).
        bootstrap_conn = init_database(DB_PATH)
        bootstrap_conn.close()
        _db_runtime_verified = True
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    return conn

router = APIRouter(prefix="/session", tags=["session"])


@router.post("/start")
async def start_study_session(
    unit_id: str,
    word_count: int = 5,
    user_id: str = Depends(get_user_id),
    language_code: str = "zh"
):
    """
    Start a Quick Study session with a batch of words.
    
    Args:
        unit_id: Unit to study from (e.g., "UNIT_HSK1_001")
        word_count: Number of words to learn (5-10)
        user_id: User ID from auth
        language_code: Target language
    
    Returns:
        {
            "session_id": "sess_abc123",
            "unit_title": "Greetings & Politeness",
            "words": [...],
            "exercises": [...]
        }
    """
    if word_count < 3 or word_count > 10:
        raise HTTPException(400, "word_count must be between 3 and 10")
    
    conn = get_db()
    try:
        # Get unit info
        unit_row = conn.execute(
            "SELECT title, description FROM units WHERE id = ?",
            (unit_id,)
        ).fetchone()
        
        if not unit_row:
            raise HTTPException(404, f"Unit {unit_id} not found")
        
        # Get words from this unit that user hasn't mastered
        # Joining with concepts table to get canonical text/pinyin/meaning
        words_query = """
            SELECT c.id as word_id, c.text, c.pinyin, c.meaning
            FROM unit_concepts uc
            JOIN concepts c ON uc.concept_id = c.id
            LEFT JOIN user_word_mastery um ON c.id = um.word_id 
                AND um.user_id = ? AND um.language_code = ?
            WHERE uc.unit_id = ?
                AND (um.mastery_state IS NULL OR um.mastery_state NOT IN ('MASTERED', 'MASTERED_PENDING_REVIEW'))
            ORDER BY RANDOM()
            LIMIT ?
        """
        
        word_rows = conn.execute(
            words_query,
            (user_id, language_code, unit_id, word_count)
        ).fetchall()
        
        if not word_rows:
            raise HTTPException(404, "No words available in this unit")
        
        # Format words
        words = []
        word_ids = []
        for row in word_rows:
            word_ids.append(row['word_id'])
            primary_gloss = get_primary_gloss(
                conn,
                str(row['word_id']),
                fallback=str(row['meaning'] or ''),
            )
            words.append({
                "word_id": row['word_id'],
                "headword": row['text'],
                "pronunciation": row['pinyin'] or "",
                "translation": primary_gloss or (row['meaning'] or ""),
                "example_sentence": "" # Will be populated by brain if available
            })
        
        # Generate session ID
        session_id = f"sess_{uuid.uuid4().hex[:12]}"
        
        # Generate batch exercises
        exercises = _generate_batch_exercises(conn, word_ids, language_code, user_id)
        
        # Store session in database
        conn.execute("""
            INSERT INTO study_sessions (session_id, user_id, unit_id, word_ids, 
                                         started_at, language_code)
            VALUES (?, ?, ?, ?, ?, ?)
        """, (
            session_id,
            user_id,
            unit_id,
            ','.join(word_ids),
            datetime.utcnow().isoformat(),
            language_code
        ))
        conn.commit()
        
        return {
            "session_id": session_id,
            "unit_id": unit_id,
            "unit_title": str(unit_row["title"] or "Unit"),
            "unit_description": str(unit_row["description"] or "Core vocabulary training block"),
            "word_count": len(words),
            "words": words,
            "exercises": exercises
        }
    finally:
        conn.close()


@router.post("/{session_id}/complete")
async def complete_study_session(
    session_id: str,
    results: Dict[str, Any],
    user_id: str = Depends(get_user_id)
):
    """
    Complete a study session and update progress.
    
    Args:
        session_id: Session ID
        results: {
            "word_scores": {"W00001": 0.8, "W00002": 0.6, ...},
            "time_spent_seconds": 480,
            "exercises_completed": 4
        }
    """
    conn = get_db()
    try:
        # Verify session exists and belongs to user
        session_row = conn.execute(
            "SELECT word_ids, unit_id, language_code FROM study_sessions WHERE session_id = ? AND user_id = ?",
            (session_id, user_id)
        ).fetchone()
        
        if not session_row:
            raise HTTPException(404, "Session not found")
        
        word_ids = session_row['word_ids'].split(',')
        word_scores = results.get('word_scores', {})
        session_lang = session_row['language_code'] or 'zh'
        
        # Update mastery for each word (lightweight update path for batch study)
        for word_id in word_ids:
            raw_score = word_scores.get(word_id, 0.5)  # Default to 50% if not provided
            try:
                score = max(0.0, min(1.0, float(raw_score)))
            except (TypeError, ValueError):
                score = 0.5

            row = conn.execute(
                """
                SELECT recognition, listening, production, usage, writing, srs_stage, mastery_state
                FROM user_word_mastery
                WHERE user_id = ? AND language_code = ? AND word_id = ?
                """,
                (user_id, session_lang, word_id),
            ).fetchone()

            rec = int(round(6 + score * 12))
            lis = int(round(5 + score * 10))
            prod = int(round(3 + score * 8))
            use = int(round(4 + score * 10))

            if row:
                new_rec = min(100, (row["recognition"] or 0) + rec)
                new_lis = min(100, (row["listening"] or 0) + lis)
                new_prod = min(100, (row["production"] or 0) + prod)
                new_use = min(100, (row["usage"] or 0) + use)
                new_writing = row["writing"] or 0
                new_stage = max(row["srs_stage"] or 0, 1 if score >= 0.8 else 0)
                avg_core = (new_rec + new_lis + new_prod + new_use) / 4.0
                if avg_core >= 60 and new_prod >= 40 and new_use >= 60:
                    new_state = "MASTERED_PENDING_REVIEW"
                elif avg_core >= 35:
                    new_state = "PRACTICING"
                else:
                    new_state = row["mastery_state"] or "LEARNING"
            else:
                new_rec = rec
                new_lis = lis
                new_prod = prod
                new_use = use
                new_writing = 0
                new_stage = 1 if score >= 0.8 else 0
                avg_core = (new_rec + new_lis + new_prod + new_use) / 4.0
                new_state = "PRACTICING" if avg_core >= 35 else "LEARNING"

            review_hours = 24 if score >= 0.8 else (12 if score >= 0.6 else 4)
            next_review_at = (datetime.utcnow() + timedelta(hours=review_hours)).isoformat()

            conn.execute(
                """
                INSERT INTO user_word_mastery
                    (user_id, language_code, word_id, recognition, listening, production, usage, writing,
                     mastery_state, srs_stage, next_review_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
                ON CONFLICT(user_id, language_code, word_id) DO UPDATE SET
                    recognition = excluded.recognition,
                    listening = excluded.listening,
                    production = excluded.production,
                    usage = excluded.usage,
                    writing = excluded.writing,
                    mastery_state = excluded.mastery_state,
                    srs_stage = excluded.srs_stage,
                    next_review_at = excluded.next_review_at,
                    updated_at = datetime('now')
                """,
                (
                    user_id,
                    session_lang,
                    word_id,
                    new_rec,
                    new_lis,
                    new_prod,
                    new_use,
                    new_writing,
                    new_state,
                    new_stage,
                    next_review_at,
                ),
            )
        
        # Mark session as completed
        conn.execute("""
            UPDATE study_sessions 
            SET completed_at = ?, 
                time_spent_seconds = ?,
                exercises_completed = ?
            WHERE session_id = ?
        """, (
            datetime.utcnow().isoformat(),
            results.get('time_spent_seconds', 0),
            results.get('exercises_completed', 0),
            session_id
        ))
        conn.commit()
        
        # Calculate summary stats
        normalized_scores: List[float] = []
        for raw in word_scores.values():
            try:
                normalized_scores.append(max(0.0, min(1.0, float(raw))))
            except (TypeError, ValueError):
                normalized_scores.append(0.5)

        avg_score = (
            sum(normalized_scores) / len(normalized_scores)
            if normalized_scores
            else 0
        )
        words_mastered = sum(1 for s in normalized_scores if s >= 0.8)
        
        return {
            "session_id": session_id,
            "completed": True,
            "words_practiced": len(word_ids),
            "words_mastered": words_mastered,
            "average_score": round(avg_score, 2),
            "time_spent_seconds": results.get('time_spent_seconds', 0)
        }
    finally:
        conn.close()


def _generate_batch_exercises(
    conn: sqlite3.Connection,
    word_ids: List[str],
    language_code: str,
    user_id: str
) -> List[Dict[str, Any]]:
    """Generate exercises that practice all words together."""
    
    exercises = []
    
    # Exercise 1: Match Chinese to English (all words)
    exercises.append({
        "exercise_id": f"batch_match_{uuid.uuid4().hex[:8]}",
        "type": "match_pairs",
        "instruction": "Match the Chinese words to their English meanings",
        "word_ids": word_ids,
        "pairs": _get_word_pairs(conn, word_ids, language_code)
    })
    
    # Exercise 2: Multiple choice recognition (3 questions, using all words)
    exercises.append({
        "exercise_id": f"batch_mc_{uuid.uuid4().hex[:8]}",
        "type": "multiple_choice",
        "instruction": "Choose the correct meaning",
        "questions": _generate_mc_questions(conn, word_ids, language_code, count=min(5, len(word_ids)))
    })
    
    # Exercise 3: Type pinyin (for each word)
    exercises.append({
        "exercise_id": f"batch_type_{uuid.uuid4().hex[:8]}",
        "type": "type_pinyin",
        "instruction": "Type the pinyin for each character",
        "word_ids": word_ids
    })
    
    return exercises


def _get_word_pairs(conn: sqlite3.Connection, word_ids: List[str], language_code: str) -> List[Dict]:
    """Get word pairs for matching exercise."""
    import json
    placeholders = ','.join('?' * len(word_ids))
    rows = conn.execute(f"""
        SELECT word_id, payload
        FROM word_exercises
        WHERE word_id IN ({placeholders}) AND exercise_type = 'flashcard'
    """, (*word_ids,)).fetchall()
    
    pairs = []
    for row in rows:
        payload = json.loads(row['payload'])
        pairs.append({
            "chinese": payload.get('front', ''),
            "english": payload.get('back', ''),
            "word_id": row['word_id']
        })
    return pairs


def _generate_mc_questions(
    conn: sqlite3.Connection,
    word_ids: List[str],
    language_code: str,
    count: int = 5
) -> List[Dict]:
    """Generate multiple choice questions."""
    import random
    import json
    
    questions = []
    placeholders = ','.join('?' * len(word_ids))
    
    # Get all words
    rows = conn.execute(f"""
        SELECT word_id, payload
        FROM word_exercises
        WHERE word_id IN ({placeholders}) AND exercise_type = 'flashcard'
    """, (*word_ids,)).fetchall()
    
    words = []
    for row in rows:
        payload = json.loads(row['payload'])
        words.append({
            'word_id': row['word_id'],
            'headword': payload.get('front', ''),
            'translation': payload.get('back', '')
        })
    
    for word in random.sample(words, min(count, len(words))):
        # Get 3 wrong answers from the same batch
        wrong_answers = [w['translation'] for w in words if w['word_id'] != word['word_id']]
        options = random.sample(wrong_answers, min(3, len(wrong_answers)))
        options.append(word['translation'])
        random.shuffle(options)
        
        questions.append({
            "word_id": word['word_id'],
            "question": word['headword'],
            "options": options,
            "correct_answer": word['translation']
        })
    
    return questions


# Add table creation SQL (to be run in schema migration)
CREATE_SESSION_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS study_sessions (
    session_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    unit_id TEXT NOT NULL,
    word_ids TEXT NOT NULL,  -- Comma-separated word IDs
    language_code TEXT DEFAULT 'zh',
    started_at TEXT NOT NULL,
    completed_at TEXT,
    time_spent_seconds INTEGER DEFAULT 0,
    exercises_completed INTEGER DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_sessions_user ON study_sessions(user_id, started_at DESC);
"""
