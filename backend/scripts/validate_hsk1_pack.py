#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Dict, List


MCQ_TYPES = {
    "meaning_select",
    "character_select",
    "pinyin_select",
    "reply_select",
    "audio_select",
    "dictation_select",
    "cloze_select",
}

SPEAK_TYPES = {
    "speak_read_aloud",
    "speak_prompted_reply",
}


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _load_pack(path: Path) -> Dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _add_error(errors: List[str], message: str):
    if len(errors) < 20:
        errors.append(message)


def _validate_item(item: Dict, errors: List[str]):
    ex_type = item.get("exercise_type") or item.get("type") or ""
    item_id = item.get("id") or f"{ex_type}:{item.get('concept_id')}"

    if not item.get("level") or not item.get("skill") or not item.get("why"):
        _add_error(errors, f"{item_id}: missing level/skill/why")
    if "attempts_allowed" not in item:
        _add_error(errors, f"{item_id}: missing attempts_allowed")
    if "difficulty_level" not in item:
        _add_error(errors, f"{item_id}: missing difficulty_level")
    if "required_assets" not in item:
        _add_error(errors, f"{item_id}: missing required_assets")
    else:
        assets = item.get("required_assets") or {}
        if not isinstance(assets, dict):
            _add_error(errors, f"{item_id}: required_assets not dict")
        else:
            if "audio" not in assets or "image" not in assets:
                _add_error(errors, f"{item_id}: required_assets missing audio/image")
            if assets.get("audio") not in (True, False):
                _add_error(errors, f"{item_id}: required_assets.audio not bool")
            if assets.get("image") not in (True, False):
                _add_error(errors, f"{item_id}: required_assets.image not bool")
    attempts_allowed = item.get("attempts_allowed")
    if attempts_allowed is None or not isinstance(attempts_allowed, int) or attempts_allowed < 1:
        _add_error(errors, f"{item_id}: invalid attempts_allowed")
    difficulty_level = item.get("difficulty_level")
    if difficulty_level is None or not isinstance(difficulty_level, int):
        _add_error(errors, f"{item_id}: invalid difficulty_level")
    if "time_limit_ms" in item and item.get("time_limit_ms") is not None:
        if not isinstance(item.get("time_limit_ms"), int):
            _add_error(errors, f"{item_id}: invalid time_limit_ms")

    if ex_type in MCQ_TYPES:
        choices = item.get("choices") or []
        if len(choices) < 4:
            _add_error(errors, f"{item_id}: options < 4")
        if len(set(choices)) != len(choices):
            _add_error(errors, f"{item_id}: duplicate option text")
        answer_index = item.get("answer_index")
        if answer_index is None or answer_index >= len(choices):
            _add_error(errors, f"{item_id}: invalid answer_index")

    if ex_type == "dictation_select":
        options = item.get("options") or []
        if len(options) < 4:
            _add_error(errors, f"{item_id}: dictation options < 4")
        texts = [opt.get("text") for opt in options]
        if len(set(texts)) != len(texts):
            _add_error(errors, f"{item_id}: dictation duplicate option text")
        correct_id = item.get("correct_option_id")
        if correct_id is None or not any(opt.get("id") == correct_id for opt in options):
            _add_error(errors, f"{item_id}: correct_option_id missing")

    if ex_type == "cloze_select":
        payload = item.get("payload") or {}
        sentence = payload.get("sentence", "")
        if "____" not in sentence:
            _add_error(errors, f"{item_id}: cloze sentence missing blank")

    if ex_type == "order_sentence":
        payload = item.get("payload") or {}
        answer = payload.get("answer") or []
        sentence = payload.get("sentence") or ""
        reconstructed = "".join(answer).replace(" ", "")
        expected = str(sentence).replace(" ", "")
        if sentence and reconstructed != expected:
            _add_error(errors, f"{item_id}: order_sentence chunks mismatch")

    if ex_type == "meaning_match":
        payload = item.get("payload") or {}
        left = payload.get("left") or []
        right = payload.get("right") or []
        if len(set(left)) != len(left):
            _add_error(errors, f"{item_id}: meaning_match duplicate left")
        if len(set(right)) != len(right):
            _add_error(errors, f"{item_id}: meaning_match duplicate right")

    if ex_type in SPEAK_TYPES:
        payload = item.get("payload") or {}
        samples = payload.get("sample_answers") or []
        if not isinstance(samples, list) or len(samples) == 0:
            _add_error(errors, f"{item_id}: missing sample_answers")
        if ex_type == "speak_prompted_reply":
            if not item.get("prompt_text"):
                _add_error(errors, f"{item_id}: missing prompt_text")

    if ex_type == "reading_micro":
        questions = item.get("questions") or []
        for idx, q in enumerate(questions):
            choices = q.get("choices") or []
            if len(choices) < 4:
                _add_error(errors, f"{item_id}: question {idx} has <4 choices")


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate HSK1 pilot pack JSON")
    parser.add_argument(
        "--pack",
        default="docs/pilot/hsk1_exercises_v1.json",
        help="Path to JSON pack",
    )
    args = parser.parse_args()

    pack_path = _repo_root() / args.pack
    if not pack_path.exists():
        print(f"Missing pack: {pack_path}")
        return 1

    data = _load_pack(pack_path)
    items = data.get("items", [])
    errors: List[str] = []
    for item in items:
        _validate_item(item, errors)

    print(f"Validated {len(items)} items")
    if errors:
        print(f"Errors: {len(errors)} (showing first {min(20, len(errors))})")
        for err in errors[:20]:
            print(f"- {err}")
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
