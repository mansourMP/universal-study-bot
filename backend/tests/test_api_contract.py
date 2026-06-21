
import pytest
import sqlite3
import json
import os
import sys

# Ensure backend is in path
sys.path.append(os.path.join(os.getcwd(), 'backend'))

from learning_path.brain_selector import create_selector
from learning_path.srs_plan import MasteryVector
from learning_path.schema import get_schema_sql

@pytest.fixture
def db_conn():
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    conn.executescript(get_schema_sql())
    return conn

def test_api_contract_structure(db_conn):
    """
    Simulate BrainSelector output and verify API contract:
    - payload.option_type exists
    - options are strings
    - correct answer is in options
    """
    user_id = "u_api"
    word_id = "101"
    
    # Seed Data
    db_conn.execute("INSERT INTO concepts (id, text, pinyin, meaning) VALUES (?, 'Apple', 'pg', 'fruit')", (word_id,))
    
    # Siblings
    db_conn.execute("INSERT INTO unit_concepts VALUES ('u1', '101', 1), ('u1', '102', 2)")
    db_conn.execute("INSERT INTO concepts (id, text, pinyin, meaning) VALUES ('102', 'Banana', 'xj', 'fruit')")
    
    # Exercise
    payload = json.dumps({
        "word": "Apple",
        "sentence": "I eat ___", 
        "correct": "Apple", 
        "options": [] # Empty, to be filled by selector
    })
    
    db_conn.execute(
        "INSERT INTO word_exercises (id, word_id, exercise_type, difficulty, payload, variant_index, created_at) VALUES (?, ?, 'sentence_fill', 3, ?, 0, datetime('now'))",
        (f"ex_{word_id}", word_id, payload)
    )
    
    selector = create_selector(db_conn, "seed_api")
    
    # Select
    res = selector.select_exercises_for_word(user_id, 'zh', word_id, 3, MasteryVector(100,100,100,0), "ri_1", "m_1")
    item = res[0]
    
    payload = item.payload
    
    # Assertions
    print(f"Payload: {payload}")
    
    assert "option_type" in payload, "❌ Missing option_type in payload"
    assert payload["option_type"] == "hanzi", "❌ option_type must be 'hanzi'"
    
    assert "options" in payload, "❌ Missing options in payload"
    options = payload["options"]
    
    assert isinstance(options, list), "❌ Options must be a list"
    assert len(options) >= 2, "❌ Too few options"
    assert all(isinstance(x, str) for x in options), "❌ All options must be strings"
    
    assert payload["correct"] in options, "❌ Correct answer not in options"
    
    # Verify Determinism (Hash stability check)
    selector_2 = create_selector(db_conn, "seed_api")
    res_2 = selector_2.select_exercises_for_word(user_id, 'zh', word_id, 3, MasteryVector(100,100,100,0), "ri_1", "m_1")
    assert res_2[0].payload["options"] == options, "❌ Options order mismatch (nondeterministic)"

