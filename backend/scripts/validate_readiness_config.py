#!/usr/bin/env python3
"""Validate readiness config: weights, skill mappings, and reason codes."""
import sys


def main() -> int:
    weights = {
        "meaning": 0.35,
        "character": 0.25,
        "listening": 0.25,
        "reading": 0.15,
        "production": 0.0,
    }
    skill_map = {
        "meaning_select": "meaning",
        "meaning_match": "meaning",
        "character_select": "character",
        "order_sentence": "character",
        "audio_select": "listening",
        "dictation_select": "listening",
        "pinyin_select": "listening",
        "cloze_select": "reading",
        "reading_micro": "reading",
        "reply_select": "production",
        "speak_prompted_reply": "production",
        "speak_read_aloud": "production",
    }
    known_skills = {"meaning", "character", "listening", "reading", "production"}

    # Reason codes used in practice scheduler
    reason_codes = {
        "DUE_REVIEW": "Due for review",
        "NEW_WORD": "New concept",
        "WEAK_SKILL": "Weak skill focus",
        "VARIETY": "Variety in practice",
        "NEW_WORD_CAP": "New word cap",
        "MISTAKE_REVIEW": "Mistake review",
        "GOAL_BALANCE": "Goal balance",
    }

    total = sum(weights.values())
    errors = []
    if abs(total - 1.0) > 1e-6:
        errors.append(f"weights_sum={total:.3f} (expected 1.0)")

    for etype, skill in skill_map.items():
        if skill not in known_skills:
            errors.append(f"unknown_skill for {etype}: {skill}")

    # Validate reason codes are non-empty
    for code, text in reason_codes.items():
        if not text or not text.strip():
            errors.append(f"empty_reason_text for {code}")

    if errors:
        print("Readiness config validation FAILED")
        for err in errors[:20]:
            print(f"- {err}")
        return 1

    print("Readiness config validation OK")
    print(f"weights_sum={total:.3f}")
    print(f"weights={weights}")
    print(f"exercise_type_count={len(skill_map)}")
    print(f"reason_codes_count={len(reason_codes)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

