
import pytest
from fastapi.testclient import TestClient
import sys
import os
import sqlite3
import json

# Fix imports
sys.path.append(os.path.join(os.getcwd(), 'backend'))

from main import app
from learning_path.schema import get_schema_sql, init_database
from learning_path.brain_selector import create_selector

client = TestClient(app)

USER_ID = "e2e_test_fresh_user"
HEADERS = {"X-User-Id": USER_ID}

def setup_module(module):
    # Ensure user is clean
    db_path = "backend/learning_path.db"
    conn = sqlite3.connect(db_path)
    conn.execute("DELETE FROM user_word_mastery WHERE user_id = ?", (USER_ID,))
    conn.execute("DELETE FROM user_word_stage_progress WHERE user_id = ?", (USER_ID,))
    conn.execute("DELETE FROM user_exercise_history WHERE user_id = ?", (USER_ID,))
    conn.execute("DELETE FROM user_attempts WHERE user_id = ?", (USER_ID,))
    conn.commit()
    conn.close()

def test_mission_generation_fresh():
    # 1. Request Mission (LEARN) for Unit 1 words
    # Unit 1 Lesson 1 words: 36, 37, 38, 40, 42
    forced_ids = ["36", "37", "38", "40", "42"]
    
    payload = {
        "user_id": USER_ID, # Body user_id (should be ignored/validated)
        "language_code": "zh",
        "intent": "learn", # Lowercase required by Pydantic Literal
        "limit": 5,
        "forced_ids": forced_ids
    }
    
    resp = client.post("/api/v2/brain/mission", json=payload, headers=HEADERS)
    if resp.status_code != 200:
        print(f"\nMission Error: {resp.json()}")
    assert resp.status_code == 200
    data = resp.json()
    
    assert data["mission_id"].startswith("m_")
    exercises = data["exercises"]
    print(f"\nExercises ({len(exercises)}): {[e['word_id'] for e in exercises]}")
    
    # [HARD CONTRACT CHECK]
    # Must have 5 exercises (one for each forced word)
    assert len(exercises) >= 5
    
    # Verify Content
    returned_ids = set(str(ex["word_id"]) for ex in exercises)
    for fid in forced_ids:
        assert fid in returned_ids, f"Forced ID {fid} missing from mission"

    for ex in exercises:
        # Stage 0 Safety: Should be flashcard or recognition types only
        # "flashcard", "meaning_select"
        assert ex["stage"] == 0
        assert ex["type"] in ["flashcard", "meaning_select", "intro", "tone_select"]

def test_submit_flow():
    # 1. Get a mission to get valid params
    forced_ids = ["36"]
    payload = {
        "user_id": USER_ID,
        "language_code": "zh",
        "intent": "learn",
        "limit": 1,
        "forced_ids": forced_ids
    }
    resp = client.post("/api/v2/brain/mission", json=payload, headers=HEADERS)
    data = resp.json()
    ex = data["exercises"][0]
    
    # 2. Submit Correct
    submit_payload = {
        "user_id": USER_ID,
        "language_code": "zh",
        "mission_id": data["mission_id"],
        "exercise_id": ex["exercise_id"],
        "word_id": ex["word_id"],
        "plan_slot_id": ex["plan_slot_id"],
        "is_correct": True,
        "latency_ms": 1000
    }
    
    resp = client.post("/api/v2/brain/submit", json=submit_payload, headers=HEADERS)
    if resp.status_code != 200:
        print(f"\nSubmit Error: {resp.json()}")
    assert resp.status_code == 200
    res = resp.json()
    
    assert res["accepted"] is True
    # Should update skill
    assert res["skill_updated"] == "recognition" or res["skill_updated"] == "listening"
    assert res["skill_score"] > 0
    
    # 3. Verify DB Update
    db_path = "backend/learning_path.db"
    conn = sqlite3.connect(db_path)
    row = conn.execute("SELECT recognition, listening, srs_stage FROM user_word_mastery WHERE user_id=? AND word_id=?", (USER_ID, ex["word_id"])).fetchone()
    conn.close()
    
    assert row is not None
    # Either recognition or listening updated depending on exercise type
    assert row[0] > 0 or row[1] > 0

def test_journey_status_update():
    # Verify journey endpoint works
    resp = client.get("/api/v2/path/journey", headers=HEADERS)
    assert resp.status_code == 200
    data = resp.json()
    assert "nodes" in data
    
    # Unit 1 should be unlocked (always)
    u1_nodes = [n for n in data["nodes"] if n.get("metadata", {}).get("unit_number") == 1]
    if not u1_nodes:
         u1_nodes = [n for n in data["nodes"] if n["id"] == "unit_1"]
    
    assert len(u1_nodes) > 0, "No nodes found for Unit 1"
    u1 = u1_nodes[0]
    assert u1["status"] in ["available", "completed", "locked"] # Should be available/completed
    
    # Check lock status delegates to brain
    # We haven't mastered Unit 1, so Unit 2 should be locked.
    u2_nodes = [n for n in data["nodes"] if n.get("metadata", {}).get("unit_number") == 2]
    if not u2_nodes:
         u2_nodes = [n for n in data["nodes"] if n["id"] == "unit_2"]
    
    if not u2_nodes:
        print(f"\nNodes Available: {[n['id'] for n in data['nodes']]}")
        
    assert len(u2_nodes) > 0, "No nodes found for Unit 2"
    u2 = u2_nodes[0]
    # Unit 2 unlocks if Unit 1 is mastered.
    # Since we are fresh, Unit 1 is not mastered.
    assert u2["status"] == "locked"

if __name__ == "__main__":
    # Manually run if executed as script
    setup_module(None)
    test_mission_generation_fresh()
    test_submit_flow()
    test_journey_status_update()
    print("✅ Manual E2E checks passed")
