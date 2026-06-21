from fastapi import APIRouter, HTTPException, Depends, Request
from pydantic import BaseModel
from typing import List, Optional
import json
import sqlite3
from pathlib import Path
from db_v2 import DatabaseV2

router = APIRouter(tags=["gym"])
DB_V2 = DatabaseV2(str(Path(__file__).parent.parent.parent / "vocabulary_v2.db"))
PROGRESS_DB_PATH = str(Path(__file__).parent.parent.parent / "progress.db")

class GymQuestion(BaseModel):
    text: str
    options: List[str]
    correct_index: int
    explanation: str
    target_word: str

class GymWorkoutResponse(BaseModel):
    workout_id: str
    title: str
    questions: List[GymQuestion]

def get_weak_words(user_id: str, limit: int = 5):
    """
    Fetch words with low 'ease_factor' or high failure counts from progress.db
    """
    conn = sqlite3.connect(PROGRESS_DB_PATH)
    try:
        # Get items with low ease factor (hard for user) or newly failed
        rows = conn.execute("""
            SELECT item_id FROM progress 
            WHERE user_id = ? AND item_type = 'word'
            ORDER BY ease_factor ASC, repetitions ASC
            LIMIT ?
        """, (user_id, limit)).fetchall()
        
        return [r[0] for r in rows]
    finally:
        conn.close()

@router.post("/api/v2/gym/generate")
async def generate_gym_workout(
    request: Request,
    user_id: str = "anonymous" # simplified for demo
):
    """
    AI constructs a workout based on user's specific weak words.
    """
    # 1. Identify Weakness
    weak_ids = get_weak_words(user_id)
    
    # If no history, pick random HSK1 words as fallback
    target_words_data = []
    
    conn = DB_V2._get_conn()
    try:
        if weak_ids:
            # We assume item_id in progress.db corresponds to semantic_key or word
            # For this v2, let's assume it matches 'word' or we search for it.
            # Ideally, progress.db should store the stable semantic_key or ID.
            # Let's try to match by word for now.
            placeholders = ",".join(["?"] * len(weak_ids))
            query = f"SELECT * FROM concepts WHERE word IN ({placeholders})"
            rows = conn.execute(query, weak_ids).fetchall()
            target_words_data = [dict(r) for r in rows]
        
        if not target_words_data:
            # Fallback: Random 5 words from HSK 1
            rows = conn.execute("SELECT * FROM concepts WHERE level = 1 ORDER BY RANDOM() LIMIT 5").fetchall()
            target_words_data = [dict(r) for r in rows]
            
    finally:
        conn.close()
    
    # 2. Construct AI Prompt
    words_str = ", ".join([f"{w['word']} ({w['pronunciation']})" for w in target_words_data])
    
    system_prompt = (
        "You are an expert exam creator. "
        f"The student is struggling with these specific words: {words_str}. "
        "Create a 5-question multiple-choice quiz testing these words in context. "
        "Return ONLY valid JSON with this structure: "
        "{ 'title': 'Motivational Title', 'questions': [ { 'text': 'Sentence with ____', 'options': ['A','B','C','D'], 'correct_index': 0, 'explanation': '...', 'target_word': '...' } ] }"
    )
    
    messages = [{"role": "system", "content": system_prompt}]
    
    try:
        # Local import to avoid circular dependency with main.py
        from main import run_chat_completion, extract_json_blob

        # Re-using the main.py run_chat_completion via direct import might cause circular deps if not careful.
        # But we imported it safely above.
        raw_response = await run_chat_completion(messages, temperature=0.7, ai_provider="deepseek")
        
        json_str = extract_json_blob(raw_response)
        data = json.loads(json_str)
        
        questions = []
        for q in data.get("questions", []):
            questions.append(GymQuestion(
                text=q["text"],
                options=q["options"],
                correct_index=q["correct_index"],
                explanation=q["explanation"],
                target_word=q.get("target_word", "")
            ))
            
        return GymWorkoutResponse(
            workout_id="generated",
            title=data.get("title", "Weakness Workout"),
            questions=questions
        )
        
    except Exception as e:
        # Fallback if AI fails
        print(f"Gym generation failed: {e}")
        return GymWorkoutResponse(
            workout_id="fallback",
            title="Review Session",
            questions=[]
        )
