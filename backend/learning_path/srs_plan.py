"""
Learning Path 2.0 - SRS Plan Configuration
Technical Memo v1.1

Defines the SRS stage-to-exercise mapping with explicit tone focus.
"""

from typing import List, Tuple, Callable, Dict
from dataclasses import dataclass


@dataclass
class MasteryVector:
    """User's skill scores for a word (stored as 0-100)."""
    recognition: int = 0
    listening: int = 0
    production: int = 0
    usage: int = 0
    writing: int = 0
    
    def display_score(self, skill: str) -> int:
        """Convert raw 0-100 to display 0-5."""
        return getattr(self, skill, 0) // 20
    
    def weakest_skill(self) -> str:
        """Return the skill with lowest score."""
        skills = {
            'recognition': self.recognition,
            'listening': self.listening,
            'production': self.production,
            'usage': self.usage,
            'writing': self.writing
        }
        return min(skills, key=skills.get)
    
    def skill_gap(self) -> int:
        """Return difference between highest and lowest skill."""
        scores = [self.recognition, self.listening, self.production, self.usage, self.writing]
        return max(scores) - min(scores)


# ============================================================
# SRS PLAN: Stage -> [(focus, difficulty), ...]
# ============================================================

def get_weakest_focus(vector: MasteryVector) -> List[Tuple[str, int]]:
    """Stage 4: Focus on weakest skill. Double up if far behind."""
    weakest = vector.weakest_skill()
    gap = vector.skill_gap()
    
    if gap >= 40:  # 2 display levels difference (40 raw points)
        return [(weakest, 3), (weakest, 4)]
    return [(weakest, 3)]


# Static SRS plan (stages 0-5)
# Focus "tone" is explicit and maps to tone_select, but updates listening skill
SRS_PLAN: Dict[int, List[Tuple[str, int]] | Callable] = {
    # Stage 0 intentionally mixes modalities for first-contact learning.
    # This prevents "all-image/all-flashcard" lessons for new words.
    0: [("recognition", 1), ("listening", 1), ("production", 2)],
    1: [("listening", 1), ("tone", 1)],         # Listening + explicit tone
    2: [("production", 2)],                      # Production practice
    3: [("usage", 3)],                           # Contextual usage
    4: get_weakest_focus,                        # Adaptive weakest skill
    5: [("usage", 4)],                           # Advanced usage
}


def get_srs_plan(stage: int, vector: MasteryVector, profile=None) -> List[Tuple[str, int]]:
    """Get the exercise plan for a given SRS stage. Personas disabled (Full Mastery mode)."""
    capped_stage = min(stage, 5)
    base_plan = SRS_PLAN.get(capped_stage, [("usage", 3)])

    if callable(base_plan):
        return base_plan(vector)

    return base_plan


# ============================================================
# SKILL TO EXERCISE TYPE MAPPING
# ============================================================

SKILL_TO_TYPES: Dict[str, List[str]] = {
    # Mapped to stable exercise types supported by the current Flutter runner.
    'recognition': ['meaning_select', 'flashcard'],
    'listening': ['audio_select'],
    'tone': ['audio_select'],      # Tone contributes to listening score
    'production': [
        'character_select',
        'speak_read_aloud',
        'order_sentence',
        'speak_prompted_reply',
    ],
    'usage': ['order_sentence', 'reading_micro'],
    'writing': ['character_select'],
}

# Which skill score to update for each focus
FOCUS_TO_SKILL: Dict[str, str] = {
    'recognition': 'recognition',
    'listening': 'listening',
    'tone': 'listening',          # Tone updates listening score
    'production': 'production',
    'usage': 'usage',
    'writing': 'writing',
}


# ============================================================
# SRS INTERVALS
# ============================================================

SRS_INTERVALS_HOURS: Dict[int, int] = {
    0: 4,       # 4 hours (same-day / within-session)
    1: 24,      # 1 day
    2: 72,      # 3 days
    3: 168,     # 7 days
    4: 336,     # 14 days
    5: 504,     # 21 days
    6: 720,     # 30 days (MASTERED review cycle)
}


def get_interval_hours(stage: int, is_correct: bool) -> int:
    """Get next review interval in hours."""
    base_interval = SRS_INTERVALS_HOURS.get(min(stage, 6), 720)
    
    if not is_correct:
        # Halve interval on failure, minimum 2 hours
        return max(base_interval // 2, 2)
    
    return base_interval


# ============================================================
# SLOT KEY GENERATION
# ============================================================

def make_slot_key(focus: str, difficulty: int) -> str:
    """Generate slot_key from focus and difficulty."""
    return f"{focus}:{difficulty}"


def make_plan_slot_id(review_instance_id: str, slot_key: str) -> str:
    """Generate unique plan_slot_id per review instance."""
    return f"{review_instance_id}:{slot_key}"


def parse_plan_slot_id(plan_slot_id: str) -> Tuple[str, str, int]:
    """Parse plan_slot_id into (review_instance_id, focus, difficulty)."""
    parts = plan_slot_id.split(':')
    if len(parts) >= 3:
        review_instance_id = parts[0]
        focus = parts[1]
        difficulty = int(parts[2])
        return review_instance_id, focus, difficulty
    raise ValueError(f"Invalid plan_slot_id: {plan_slot_id}")


# ============================================================
# TESTS
# ============================================================

if __name__ == "__main__":
    # Test SRS plan
    vector = MasteryVector(recognition=60, listening=60, production=20, usage=60)
    
    print("SRS Plan Tests:")
    for stage in range(6):
        plan = get_srs_plan(stage, vector)
        print(f"  Stage {stage}: {plan}")
    
    # Test weakest skill
    print(f"\nWeakest skill: {vector.weakest_skill()}")
    print(f"Skill gap: {vector.skill_gap()}")
    
    # Test slot key generation
    slot_key = make_slot_key("tone", 1)
    plan_slot_id = make_plan_slot_id("ri_abc123", slot_key)
    print(f"\nSlot key: {slot_key}")
    print(f"Plan slot ID: {plan_slot_id}")
    print(f"Parsed: {parse_plan_slot_id(plan_slot_id)}")
    
    print("\n✅ SRS plan tests passed!")
