from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from typing import List, Optional
import random
from db_v2 import DatabaseV2
from pathlib import Path

router = APIRouter(tags=["placement"])
DB_V2 = DatabaseV2(str(Path(__file__).parent.parent.parent / "vocabulary_v2.db"))

class PlacementQuestion(BaseModel):
    id: str
    level: int
    text: str
    options: List[str]
    correct_index: int
    type: str = "vocab" # vocab or sentence

class PlacementTestResponse(BaseModel):
    questions: List[PlacementQuestion]

@router.get("/api/v2/placement/test")
async def get_placement_test():
    """
    Generates a progressive placement test (HSK 1-6).
    Returns 12 questions (2 per level).
    """
    questions = []
    
    conn = DB_V2._get_conn()
    try:
        for level in range(1, 7):
            # Fetch 2 random words for this level
            # We need correct answer + 3 distractors
            
            # Get 10 candidates
            candidates = conn.execute("""
                SELECT c.word, c.pronunciation, t.translation 
                FROM concepts c
                JOIN translations t ON c.id = t.concept_id
                WHERE c.level = ? AND t.native_lang = 'en'
                ORDER BY RANDOM() LIMIT 10
            """, (level,)).fetchall()
            
            if len(candidates) < 4:
                continue # Not enough data for this level
            
            # Create 2 questions
            level_subset = candidates[:2]
            
            for idx, correct in enumerate(level_subset):
                # Pick 3 distractors from the remaining candidates
                others = [c for c in candidates if c['word'] != correct['word']]
                distractors = random.sample(others, min(3, len(others)))
                
                choices_data = [correct] + distractors
                random.shuffle(choices_data)
                
                correct_idx = -1
                options = []
                for i, choice in enumerate(choices_data):
                    display = choice['word']
                    if choice['pronunciation']:
                        display = f"{display} ({choice['pronunciation']})"
                    options.append(display)
                    if choice['word'] == correct['word']:
                        correct_idx = i
                
                q = PlacementQuestion(
                    id=f"lvl{level}_q{idx}",
                    level=level,
                    text=correct['translation'],
                    options=options,
                    correct_index=correct_idx
                )
                questions.append(q)
                
    finally:
        conn.close()
        
    return PlacementTestResponse(questions=questions)
