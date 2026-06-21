
import pytest
import sqlite3
import json
import os
import sys
from datetime import datetime, timedelta

# Ensure backend is in path
sys.path.append(os.path.join(os.getcwd(), 'backend'))

from learning_path.brain_selector import BrainSelector, create_selector
from learning_path.srs_plan import MasteryVector
from learning_path.schema import get_schema_sql

@pytest.fixture
def db_conn():
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    conn.executescript(get_schema_sql())
    return conn

@pytest.fixture
def selector(db_conn):
    return create_selector(db_conn, mission_seed="test_seed")

def seed_exercise(conn, word_id, ex_type="sentence_fill", correct="text", options=None):
    if options is None:
        options = []
    payload = json.dumps({
        "word": correct, # text representation
        "sentence": "___", 
        "correct": correct, 
        "options": options
    })
    conn.execute(
        "INSERT INTO word_exercises (id, word_id, exercise_type, difficulty, payload, variant_index, created_at) VALUES (?, ?, ?, 3, ?, 0, datetime('now'))",
        (f"ex_{word_id}_{ex_type}", word_id, ex_type, payload)
    )

def seed_flashcard_lookup(conn, word_id, text):
    """Seed a flashcard so the brain can resolve ID->Text"""
    # Legacy: seed word_exercises for fallback (if any)
    payload = json.dumps({"front": text, "back": "def"})
    conn.execute(
        "INSERT INTO word_exercises (id, word_id, exercise_type, difficulty, payload, variant_index, created_at) VALUES (?, ?, 'flashcard', 1, ?, 0, datetime('now'))",
        (f"ex_{word_id}_fc", word_id, payload)
    )
    # Canonical: seed concepts table
    conn.execute(
        "INSERT INTO concepts (id, text, pinyin, meaning) VALUES (?, ?, 'py', 'mean')",
        (word_id, text)
    )

def test_determinism_strict(db_conn):
    """
    Verify that calling select_exercises_for_word twice with the same seed/inputs
    produces IDENTICAL output, including option order.
    """
    user_id = "u_det"
    word_id = "101"
    word_text = "Apple"
    
    # Setup
    seed_flashcard_lookup(db_conn, word_id, word_text)
    seed_exercise(db_conn, word_id, correct=word_text, options=["placeholder"])
    
    # Siblings
    db_conn.execute("INSERT INTO unit_concepts VALUES ('u1', '101', 1)")
    db_conn.execute("INSERT INTO unit_concepts VALUES ('u1', '102', 2)")
    seed_flashcard_lookup(db_conn, "102", "Banana")
    
    # Run 1
    s1 = create_selector(db_conn, "seed_A")
    res1 = s1.select_exercises_for_word(user_id, 'zh', word_id, 3, MasteryVector(100,100,100,0), "ri", "m")
    opts1 = res1[0].payload['options']
    
    # Run 2
    s2 = create_selector(db_conn, "seed_A")
    res2 = s2.select_exercises_for_word(user_id, 'zh', word_id, 3, MasteryVector(100,100,100,0), "ri", "m")
    opts2 = res2[0].payload['options']
    
    assert opts1 == opts2
    assert "Apple" in opts1
    assert "Banana" in opts1
    assert res1[0].payload['option_type'] == 'hanzi'

def test_distractor_type_invariant(db_conn, selector):
    """
    Ensure options are always Strings matching payload.correct type,
    not internal IDs.
    """
    user_id = "u_type"
    # Word ID "101" -> Text "你好"
    seed_flashcard_lookup(db_conn, "101", "你好")
    seed_exercise(db_conn, "101", correct="你好")
    
    # Sibling "102" -> "再见"
    db_conn.execute("INSERT INTO unit_concepts VALUES ('u1', '101', 1), ('u1', '102', 2)")
    seed_flashcard_lookup(db_conn, "102", "再见")
    
    res = selector.select_exercises_for_word(user_id, 'zh', "101", 3, MasteryVector(100,100,100,0), "ri", "m")
    options = res[0].payload['options']
    
    assert isinstance(options, list)
    assert all(isinstance(x, str) for x in options)
    assert "你好" in options
    assert "再见" in options
    # Ensure IDs didn't leak
    assert "101" not in options
    assert "102" not in options
    assert res[0].payload.get('option_type') == 'hanzi'

def test_learn_priority_no_trap(db_conn, selector):
    """
    Test that forced_ids prioritizes unmastered words (First-3-Words Trap Fix).
    """
    user_id = "u_prio"
    # Manifest asks for w1..w5
    forced = ["w1", "w2", "w3", "w4", "w5"]
    
    # User has mastered w1, w2, w3
    db_conn.execute("INSERT INTO user_word_mastery (user_id, language_code, word_id, mastery_state, srs_stage) VALUES (?, 'zh', 'w1', 'MASTERED', 6)", (user_id,))
    db_conn.execute("INSERT INTO user_word_mastery (user_id, language_code, word_id, mastery_state, srs_stage) VALUES (?, 'zh', 'w2', 'MASTERED', 6)", (user_id,))
    db_conn.execute("INSERT INTO user_word_mastery (user_id, language_code, word_id, mastery_state, srs_stage) VALUES (?, 'zh', 'w3', 'MASTERED', 6)", (user_id,))
    
    cands = selector.get_candidates_for_intent(user_id, 'zh', 'LEARN', forced_ids=forced, max_new=3)
    ids = [c['word_id'] for c in cands]
    
    # Should get w4, w5
    assert ids[0] == "w4"
    assert ids[1] == "w5"
    assert "w1" not in ids

def test_backfill_and_dedup(db_conn, selector):
    """
    Test that we backfill from due reviews if forced list is exhausted/mastered,
    AND we don't duplicate words if they are both forced and due.
    """
    user_id = "u_dedup"
    
    # w1: Forced + Due
    # w2: Forced (No Record)
    # w3: Due (Not Forced)
    
    # Forced list from UI
    forced = ["w1", "w2"]
    
    # DB State
    # w1 is due
    db_conn.execute("INSERT INTO user_word_mastery (user_id, language_code, word_id, mastery_state, srs_stage, next_review_at) VALUES (?, 'zh', 'w1', 'LEARNING', 1, '2020-01-01 00:00:00')", (user_id,))
    # w3 is due
    db_conn.execute("INSERT INTO user_word_mastery (user_id, language_code, word_id, mastery_state, srs_stage, next_review_at) VALUES (?, 'zh', 'w3', 'LEARNING', 1, '2020-01-01 00:00:00')", (user_id,))
    
    # Request
    cands = selector.get_candidates_for_intent(user_id, 'zh', 'LEARN', forced_ids=forced, max_new=2, max_review=2)
    ids = [c['word_id'] for c in cands]
    
    # Expectation:
    # 1. w1 (Forced) - kept, marked as forced
    # 2. w2 (Forced) - kept
    # 3. w3 (Due) - added as backfill/review
    # w1 (Due) - skipped because already added
    
    assert ids.count("w1") == 1
    assert "w2" in ids
    assert "w3" in ids
    
    w1_cand = next(c for c in cands if c['word_id'] == 'w1')
    assert w1_cand['reason'] == 'forced_from_manifest' # Priority check

def test_fallback_distractors_when_siblings_empty(db_conn, selector):
    user_id = "u_fallback"
    word_id = "solo_word"
    
    seed_flashcard_lookup(db_conn, word_id, "Solo")
    seed_exercise(db_conn, word_id, correct="Solo")
    
    # No unit siblings!
    # But we seed "seen words" (mastery > 0)
    db_conn.execute("INSERT INTO user_word_mastery (user_id, language_code, word_id, srs_stage) VALUES (?, 'zh', 'seen1', 2)", (user_id,))
    seed_flashcard_lookup(db_conn, "seen1", "SeenWord1")
    
    res = selector.select_exercises_for_word(user_id, 'zh', word_id, 3, MasteryVector(100,100,100,0), "ri", "m")
    opts = res[0].payload['options']
    
    # Should have picked up "SeenWord1"
    assert len(opts) > 1
    assert "Solo" in opts
    assert "SeenWord1" in opts
