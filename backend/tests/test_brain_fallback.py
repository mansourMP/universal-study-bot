
import pytest
import sqlite3
import json
import os
import sys

# Ensure backend is in path
sys.path.append(os.path.join(os.getcwd(), 'backend'))

from learning_path.brain_selector import create_selector, SelectionReason
from learning_path.srs_plan import MasteryVector
from learning_path.schema import get_schema_sql

@pytest.fixture
def db_conn():
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    conn.executescript(get_schema_sql())
    return conn

def test_fallback_generation(db_conn):
    """
    Test that if word_exercises is empty, we fallback to concepts table.
    """
    user_id = "u_fall"
    word_id = "missing_ex"
    
    # 1. Seed Concept only (No Exercise)
    db_conn.execute("INSERT INTO concepts (id, text, pinyin, meaning) VALUES (?, 'Missing', 'ms', 'gone')", (word_id,))
    
    # 2. Select
    selector = create_selector(db_conn, "seed_fb")
    
    # We ask for stage 0 (recognition) which maps to 'flashcard' usually.
    # But even if we asked for 'usage', fallback forces 'flashcard'.
    res = selector.select_exercises_for_word(user_id, 'zh', word_id, 0, MasteryVector(), "ri", "m")
    
    assert len(res) == 1
    ex = res[0]
    
    # 3. Verify Fallback Properties
    assert ex.selected_by == SelectionReason.FALLBACK
    assert ex.exercise_id.startswith("fallback_")
    assert ex.payload["front"] == "Missing"
    assert ex.payload["back"] == "gone"
    assert ex.exercise_type == "flashcard"

def test_fallback_exhaustion(db_conn):
    """
    Test that if NEITHER exercise NOR concept exists, we return nothing (Exhausted).
    """
    user_id = "u_void"
    word_id = "void_word"
    
    # No seeds at all
    
    selector = create_selector(db_conn, "seed_void")
    res = selector.select_exercises_for_word(user_id, 'zh', word_id, 0, MasteryVector(), "ri", "m")
    
    assert len(res) == 0
    
    # Check exhaustion log
    log = selector.get_exhaustion_log()
    assert len(log) > 0
    assert log[0]['word_id'] == word_id
    assert log[0]['reason'] == "no_variants_exist"
