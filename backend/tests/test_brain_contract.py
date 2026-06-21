
import pytest
import sqlite3
import json
from fastapi.testclient import TestClient
import sys
import os

# Ensure backend is in path
sys.path.append(os.path.join(os.getcwd(), 'backend'))

from main import app
from learning_path.brain_selector import create_selector, SelectionReason
from learning_path.srs_plan import MasteryVector
from learning_path.schema import get_schema_sql

client = TestClient(app)

USER_ID = "test_contract_user"
HEADERS = {"X-User-Id": USER_ID}

@pytest.fixture
def clean_db():
    db_path = "backend/learning_path.db"
    conn = sqlite3.connect(db_path)
    conn.execute("DELETE FROM user_word_mastery WHERE user_id = ?", (USER_ID,))
    conn.execute("DELETE FROM user_word_stage_progress WHERE user_id = ?", (USER_ID,))
    conn.execute("DELETE FROM user_exercise_history WHERE user_id = ?", (USER_ID,))
    conn.execute("DELETE FROM user_attempts WHERE user_id = ?", (USER_ID,))
    conn.commit()
    yield conn
    conn.close()

def test_learn_mission_hard_contract(clean_db):
    """
    HARD CONTRACT: For intent=learn, every forced_id must get at least one exercise
    if content exists.
    """
    forced_ids = ["36", "37", "38", "40", "42"] # Unit 1 Lesson 1
    
    payload = {
        "intent": "learn",
        "limit": 5,
        "forced_ids": forced_ids
    }
    
    resp = client.post("/api/v2/brain/mission", json=payload, headers=HEADERS)
    assert resp.status_code == 200
    data = resp.json()
    
    exercises = data["exercises"]
    assert len(exercises) >= 5
    
    returned_word_ids = [str(ex["word_id"]) for ex in exercises]
    for fid in forced_ids:
        assert fid in returned_word_ids, f"Word {fid} missing from mission despite being forced"

def test_learn_mission_budgeting_priority(clean_db):
    """
    Test that even if words have multiple exercises (Stage 1 has 2), 
    we prioritize 1-per-word to fill the mission before adding secondary ones.
    """
    # Force words to Stage 1
    # Stage 1 plan has 2 exercises: ('listening', 1), ('tone', 1)
    forced_ids = ["36", "37", "38"]
    
    for fid in forced_ids:
        clean_db.execute(
            "INSERT INTO user_word_mastery (user_id, language_code, word_id, mastery_state, srs_stage, next_review_at) VALUES (?, 'zh', ?, 'LEARNING', 1, datetime('now'))",
            (USER_ID, fid)
        )
    clean_db.commit()
    
    # Request with limit 3. 
    # If we didn't prioritize 1-per-word, we might get 2 for '36' and 1 for '37', skipping '38'.
    payload = {
        "intent": "learn",
        "limit": 3,
        "forced_ids": forced_ids
    }
    
    resp = client.post("/api/v2/brain/mission", json=payload, headers=HEADERS)
    assert resp.status_code == 200
    data = resp.json()
    
    exercises = data["exercises"]
    assert len(exercises) == 3
    
    returned_word_ids = [str(ex["word_id"]) for ex in exercises]
    assert "36" in returned_word_ids
    assert "37" in returned_word_ids
    assert "38" in returned_word_ids

def test_learn_mission_hard_contract_limit_lt_forced(clean_db):
    """
    HARD CONTRACT: limit < len(forced_ids) must still return >= len(forced_ids)
    and include every forced_id.
    """
    forced_ids = ["36", "37", "38", "40", "42"]
    payload = {
        "intent": "learn",
        "limit": 2,
        "forced_ids": forced_ids
    }

    resp = client.post("/api/v2/brain/mission", json=payload, headers=HEADERS)
    assert resp.status_code == 200
    data = resp.json()

    exercises = data["exercises"]
    assert len(exercises) >= len(forced_ids)

    returned_word_ids = [str(ex["word_id"]) for ex in exercises]
    for fid in forced_ids:
        assert fid in returned_word_ids, f"Word {fid} missing from mission despite being forced"

def test_forced_ids_abuse_guard():
    """Verify forced_ids length cap (20)."""
    too_many_ids = [str(i) for i in range(21)]
    payload = {
        "intent": "learn",
        "limit": 5,
        "forced_ids": too_many_ids
    }
    resp = client.post("/api/v2/brain/mission", json=payload, headers=HEADERS)
    assert resp.status_code == 422 # Validation error

def test_determinism_with_overflow(clean_db):
    """Ensure identical requests return identical overflow order."""
    forced_ids = ["36"] # Just one word
    # Word 36 has multiple exercises at Stage 1
    clean_db.execute(
        "INSERT INTO user_word_mastery (user_id, language_code, word_id, mastery_state, srs_stage, next_review_at) VALUES (?, 'zh', '36', 'LEARNING', 1, datetime('now'))",
        (USER_ID,)
    )
    clean_db.commit()
    
    payload = {
        "intent": "learn",
        "limit": 2,
        "forced_ids": forced_ids
    }
    
    # Run 1
    resp1 = client.post("/api/v2/brain/mission", json=payload, headers=HEADERS)
    ex1 = resp1.json()["exercises"]
    
    # Run 2
    resp2 = client.post("/api/v2/brain/mission", json=payload, headers=HEADERS)
    ex2 = resp2.json()["exercises"]
    
    assert [e["exercise_id"] for e in ex1] == [e["exercise_id"] for e in ex2]
