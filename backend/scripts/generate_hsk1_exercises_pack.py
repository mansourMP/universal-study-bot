#!/usr/bin/env python3
"""Generate deterministic HSK1 pilot exercises (multi-type exam pack)."""

from __future__ import annotations

import argparse
import json
import sqlite3
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Dict, List, Optional, Tuple


@dataclass
class Concept:
    concept_id: int
    text: str
    pinyin: str
    meaning: str
    unit_id: Optional[str]
    hsk_level: int


PINYIN_INITIALS = [
    "zh",
    "ch",
    "sh",
    "b",
    "p",
    "m",
    "f",
    "d",
    "t",
    "n",
    "l",
    "g",
    "k",
    "h",
    "j",
    "q",
    "x",
    "r",
    "z",
    "c",
    "s",
    "y",
    "w",
]

TONE_MAP = str.maketrans(
    {
        "ā": "a",
        "á": "a",
        "ǎ": "a",
        "à": "a",
        "ē": "e",
        "é": "e",
        "ě": "e",
        "è": "e",
        "ī": "i",
        "í": "i",
        "ǐ": "i",
        "ì": "i",
        "ō": "o",
        "ó": "o",
        "ǒ": "o",
        "ò": "o",
        "ū": "u",
        "ú": "u",
        "ǔ": "u",
        "ù": "u",
        "ǖ": "u",
        "ǘ": "u",
        "ǚ": "u",
        "ǜ": "u",
        "ü": "u",
    }
)


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _load_ids(path: Path) -> List[int]:
    ids: List[int] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            ids.append(int(line))
        except ValueError:
            continue
    return ids


def _strip_tones(pinyin: str) -> str:
    if not pinyin:
        return ""
    cleaned = pinyin.translate(TONE_MAP)
    cleaned = "".join(ch for ch in cleaned if not ch.isdigit())
    return cleaned


def _first_syllable(pinyin: str) -> str:
    return pinyin.split()[0] if pinyin else ""


def _pinyin_initial_final(pinyin: str) -> Tuple[str, str]:
    syllable = _first_syllable(_strip_tones(pinyin).lower())
    if not syllable:
        return "", ""
    for initial in PINYIN_INITIALS:
        if syllable.startswith(initial):
            return initial, syllable[len(initial) :]
    return syllable[:1], syllable[1:]


def _parse_manifest(
    manifest_path: Path,
) -> Tuple[Dict[int, str], Dict[int, int], List[dict]]:
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    realms = data.get("realms", {})
    concept_to_unit: Dict[int, str] = {}
    concept_to_level: Dict[int, int] = {}
    units_flat: List[dict] = []
    for realm_id, realm in realms.items():
        try:
            level = int(realm_id)
        except ValueError:
            level = 0
        units = realm.get("units", [])
        for unit in units:
            unit_id = str(unit.get("unit_number", ""))
            units_flat.append(
                {
                    "unit_id": unit_id,
                    "realm_id": str(realm_id),
                    "word_ids": unit.get("word_ids", []) or [],
                }
            )
            for word_id in unit.get("word_ids", []) or []:
                try:
                    cid = int(word_id)
                except ValueError:
                    continue
                concept_to_unit[cid] = unit_id
                concept_to_level[cid] = level
            for lesson in unit.get("lessons", []) or []:
                for word_id in lesson.get("word_ids", []) or []:
                    try:
                        cid = int(word_id)
                    except ValueError:
                        continue
                    concept_to_unit[cid] = unit_id
                    concept_to_level[cid] = level
    return concept_to_unit, concept_to_level, units_flat


def _load_concepts(db_path: Path, concept_to_unit: Dict[int, str], concept_to_level: Dict[int, int]) -> Dict[int, Concept]:
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    rows = conn.execute("SELECT id, text, pinyin, meaning FROM concepts").fetchall()
    conn.close()
    concepts: Dict[int, Concept] = {}
    for row in rows:
        try:
            cid = int(row["id"])
        except ValueError:
            continue
        concepts[cid] = Concept(
            concept_id=cid,
            text=row["text"] or "",
            pinyin=row["pinyin"] or "",
            meaning=row["meaning"] or "",
            unit_id=concept_to_unit.get(cid),
            hsk_level=concept_to_level.get(cid, 0),
        )
    return concepts


def _group_by_level(concepts: Dict[int, Concept]) -> Dict[int, List[int]]:
    level_map: Dict[int, List[int]] = {}
    for cid, concept in concepts.items():
        level_map.setdefault(concept.hsk_level, []).append(cid)
    for level in level_map:
        level_map[level] = sorted(level_map[level])
    return level_map


def _group_by_unit(concepts: Dict[int, Concept]) -> Dict[str, List[int]]:
    unit_map: Dict[str, List[int]] = {}
    for cid, concept in concepts.items():
        if concept.unit_id:
            unit_map.setdefault(concept.unit_id, []).append(cid)
    for unit in unit_map:
        unit_map[unit] = sorted(unit_map[unit])
    return unit_map


def _load_sentence_fill(db_path: Path) -> Dict[int, Dict[str, str]]:
    conn = sqlite3.connect(str(db_path))
    rows = conn.execute(
        "SELECT word_id, payload FROM word_exercises WHERE exercise_type='sentence_fill'"
    ).fetchall()
    conn.close()
    mapping: Dict[int, Dict[str, str]] = {}
    for word_id, payload in rows:
        try:
            cid = int(word_id)
        except ValueError:
            continue
        if cid in mapping:
            continue
        try:
            data = json.loads(payload)
        except Exception:
            continue
        sentence = str(data.get("sentence", ""))
        correct = str(data.get("correct", ""))
        if sentence:
            mapping[cid] = {"sentence": sentence, "correct": correct}
    return mapping


def _level_for_unit(unit_id: Optional[str], hsk1_units: List[str]) -> int:
    if not unit_id or unit_id not in hsk1_units:
        return 1
    idx = hsk1_units.index(unit_id)
    total = max(1, len(hsk1_units))
    ratio = idx / total
    if ratio < 0.5:
        return 1
    if ratio < 0.85:
        return 2
    return 3


def _constraints_for(level: int, skill: str) -> dict:
    timed = None
    if level >= 3:
        if skill == "reading":
            timed = 60
        elif skill == "listening":
            timed = 25
        elif skill == "grammar":
            timed = 25
        else:
            timed = 20
    return {
        "timedSec": timed,
        "retryPolicy": "sameSession" if level == 1 else "none",
    }


def _skill_for_type(exercise_type: str) -> str:
    if exercise_type in ("audio_select", "dictation_select"):
        return "listening"
    if exercise_type in ("speak_read_aloud", "speak_prompted_reply"):
        return "speaking"
    if exercise_type in ("reading_micro",):
        return "reading"
    if exercise_type in ("order_sentence",):
        return "grammar"
    if exercise_type in ("cloze_select",):
        return "reading"
    if exercise_type in ("meaning_match", "meaning_select", "character_select"):
        return "vocab"
    return "vocab"


def _required_assets_for(exercise_type: str) -> dict:
    if exercise_type in ("audio_select", "dictation_select"):
        return {"audio": True, "image": False}
    return {"audio": False, "image": False}


def _stable_hash(text: str) -> int:
    h = 0x811C9DC5
    for ch in text:
        h ^= ord(ch)
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h


def _make_cloze_sentence(sentence: str, correct: str, fallback: str) -> str:
    if "____" in sentence:
        return sentence
    target = correct or fallback
    if target and target in sentence:
        return sentence.replace(target, "____", 1)
    if fallback:
        return f"{fallback} ____"
    return "____"


def _speaking_samples(concept: Concept) -> List[str]:
    candidates: List[str] = []
    if concept.text:
        candidates.append(concept.text)
    if concept.pinyin:
        candidates.append(concept.pinyin)
    meaning = _meaning_for(concept)
    if meaning:
        candidates.append(meaning)
    samples = list(dict.fromkeys(candidates))[:3]
    return samples if samples else ["Sample answer unavailable"]


def _prompted_reply_prompt(concept: Concept) -> str:
    if concept.text:
        return f"Respond using: {concept.text}"
    meaning = _meaning_for(concept)
    if meaning:
        return f"Respond using: {meaning}"
    return "Respond aloud"


def _prompted_reply_samples(concept: Concept) -> List[str]:
    if concept.text:
        samples = [concept.text, f"{concept.text}。"]
    else:
        samples = [_meaning_for(concept)]
    samples = [s for s in samples if s]
    return list(dict.fromkeys(samples))[:3] if samples else ["Sample answer unavailable"]


def _chunk_sentence(sentence: str, level: int) -> Tuple[List[str], List[str]]:
    cleaned = sentence.strip()
    if cleaned.endswith(("。", "！", "？")):
        punctuation = cleaned[-1]
        cleaned = cleaned[:-1]
    else:
        punctuation = ""
    chars = list(cleaned)
    if not chars:
        return ["…"], ["…"]
    target_chunks = 3 if level == 1 else (4 if level == 2 else 5)
    target_chunks = min(max(3, target_chunks), len(chars))
    size = (len(chars) + target_chunks - 1) // target_chunks
    chunks = ["".join(chars[i : i + size]) for i in range(0, len(chars), size)]
    if punctuation and chunks:
        chunks[-1] = chunks[-1] + punctuation
    correct = list(chunks)
    shuffled = sorted(chunks, key=lambda c: _stable_hash(c))
    return shuffled, correct


def _group_by_pinyin_base(concepts: Dict[int, Concept]) -> Dict[str, List[int]]:
    pinyin_map: Dict[str, List[int]] = {}
    for cid, concept in concepts.items():
        base = _first_syllable(_strip_tones(concept.pinyin).lower())
        if base:
            pinyin_map.setdefault(base, []).append(cid)
    for base in pinyin_map:
        pinyin_map[base] = sorted(pinyin_map[base])
    return pinyin_map


def _select_unique_values(
    candidate_ids: List[int],
    concepts: Dict[int, Concept],
    value_fn,
    exclude_values: set,
    needed: int,
) -> List[int]:
    selected: List[int] = []
    seen_values = set(exclude_values)
    for cid in candidate_ids:
        if cid in selected:
            continue
        value = value_fn(concepts[cid])
        if not value:
            continue
        if value in seen_values:
            continue
        selected.append(cid)
        seen_values.add(value)
        if len(selected) >= needed:
            break
    return selected


def _meaning_for(concept: Concept) -> str:
    return concept.meaning.strip() if concept.meaning else "Meaning unavailable"


def _pick_distractors_meaning(
    concept: Concept,
    concepts: Dict[int, Concept],
    level_map: Dict[int, List[int]],
    pinyin_index: Dict[str, List[int]],
    needed: int = 3,
) -> List[int]:
    candidates: List[int] = []
    initial, final = _pinyin_initial_final(concept.pinyin)
    if initial or final:
        similar: List[int] = []
        for cid, c in concepts.items():
            if cid == concept.concept_id:
                continue
            cand_initial, cand_final = _pinyin_initial_final(c.pinyin)
            if (initial and cand_initial == initial) or (final and cand_final == final):
                similar.append(cid)
        candidates.extend(sorted(similar))

    same_level = [cid for cid in level_map.get(concept.hsk_level, []) if cid != concept.concept_id]
    candidates.extend(same_level)

    if len(candidates) < needed:
        for adj in (concept.hsk_level - 1, concept.hsk_level + 1):
            if adj in level_map:
                candidates.extend([cid for cid in level_map[adj] if cid != concept.concept_id])

    # fallback to all concepts
    if len(candidates) < needed:
        candidates.extend(sorted([cid for cid in concepts.keys() if cid != concept.concept_id]))

    answer_value = _meaning_for(concept)
    return _select_unique_values(candidates, concepts, _meaning_for, {answer_value}, needed)


def _pick_distractors_character(
    concept: Concept,
    concepts: Dict[int, Concept],
    level_map: Dict[int, List[int]],
    unit_map: Dict[str, List[int]],
    pinyin_index: Dict[str, List[int]],
    needed: int = 3,
) -> List[int]:
    candidates: List[int] = []
    pinyin_base = _first_syllable(_strip_tones(concept.pinyin).lower())
    if pinyin_base and pinyin_base in pinyin_index:
        candidates.extend([cid for cid in pinyin_index[pinyin_base] if cid != concept.concept_id])

    if concept.unit_id and concept.unit_id in unit_map:
        candidates.extend([cid for cid in unit_map[concept.unit_id] if cid != concept.concept_id])

    candidates.extend([cid for cid in level_map.get(concept.hsk_level, []) if cid != concept.concept_id])

    if len(candidates) < needed:
        for adj in (concept.hsk_level - 1, concept.hsk_level + 1):
            if adj in level_map:
                candidates.extend([cid for cid in level_map[adj] if cid != concept.concept_id])

    if len(candidates) < needed:
        candidates.extend(sorted([cid for cid in concepts.keys() if cid != concept.concept_id]))

    target_len = len(concept.text or "")
    if target_len:
        same_len = [cid for cid in candidates if len(concepts[cid].text or "") == target_len]
        if len(same_len) >= needed:
            candidates = same_len

    def _hanzi(c: Concept) -> str:
        return c.text.strip() if c.text else "<?>"

    return _select_unique_values(candidates, concepts, _hanzi, {_hanzi(concept)}, needed)


def _pick_distractors_pinyin(
    concept: Concept,
    concepts: Dict[int, Concept],
    level_map: Dict[int, List[int]],
    pinyin_index: Dict[str, List[int]],
    needed: int = 3,
) -> List[int]:
    candidates: List[int] = []
    base = _first_syllable(_strip_tones(concept.pinyin).lower())
    if base and base in pinyin_index:
        candidates.extend([cid for cid in pinyin_index[base] if cid != concept.concept_id])
    candidates.extend([cid for cid in level_map.get(concept.hsk_level, []) if cid != concept.concept_id])
    if len(candidates) < needed:
        for adj in (concept.hsk_level - 1, concept.hsk_level + 1):
            if adj in level_map:
                candidates.extend([cid for cid in level_map[adj] if cid != concept.concept_id])
    if len(candidates) < needed:
        candidates.extend(sorted([cid for cid in concepts.keys() if cid != concept.concept_id]))

    def _pinyin(c: Concept) -> str:
        return c.pinyin.strip() if c.pinyin else ""

    return _select_unique_values(candidates, concepts, _pinyin, {concept.pinyin.strip()}, needed)


def _swap_particles(sentence: str) -> List[str]:
    swaps = [
        ("吗", "吧"),
        ("吧", "吗"),
        ("呢", "吗"),
        ("的", "了"),
        ("了", "的"),
        ("个", "本"),
        ("个", "只"),
    ]
    variants: List[str] = []
    for src, dst in swaps:
        if src in sentence:
            variants.append(sentence.replace(src, dst, 1))
    return variants


def _build_dictation_options(
    concept: Concept,
    sentence: str,
    concepts: Dict[int, Concept],
    distractor_ids: List[int],
) -> Tuple[List[str], int, List[dict], str]:
    correct = sentence.strip() if sentence else f"我喜欢{concept.text}。"
    candidates: List[str] = []

    for cid in distractor_ids:
        if cid == concept.concept_id:
            continue
        alt_text = concepts[cid].text or ""
        if not alt_text:
            continue
        if concept.text and concept.text in correct:
            variant = correct.replace(concept.text, alt_text, 1)
        else:
            variant = f"我喜欢{alt_text}。"
        candidates.append(variant)

    candidates.extend(_swap_particles(correct))

    # fallback to additional concept-based sentences
    if len(candidates) < 3:
        for cid in sorted(concepts.keys()):
            if cid == concept.concept_id or cid in distractor_ids:
                continue
            alt_text = concepts[cid].text or ""
            if not alt_text:
                continue
            candidates.append(f"我喜欢{alt_text}。")
            if len(candidates) >= 6:
                break

    # unique while preserving order
    seen = {correct}
    options: List[str] = [correct]
    for cand in candidates:
        if cand in seen:
            continue
        options.append(cand)
        seen.add(cand)
        if len(options) >= 4:
            break

    # ensure 4 options even if repeats are needed
    while len(options) < 4:
        filler = f"{concept.text} 很好。"
        if filler in seen:
            filler = f"{concept.text} 很棒。"
        options.append(filler)
        seen.add(filler)

    ordered = sorted(options, key=_stable_hash)
    correct_index = ordered.index(correct)
    option_dicts = [
        {"id": f"opt_{idx+1}", "text": text} for idx, text in enumerate(ordered)
    ]
    correct_option_id = option_dicts[correct_index]["id"]
    return ordered, correct_index, option_dicts, correct_option_id


def _build_item(
    exercise_id: str,
    exercise_type: str,
    concept: Concept,
    choices: List[str],
    answer_index: int,
    level: int,
    skill: str,
    constraints: dict,
    why: dict,
    audio_url: Optional[str] = None,
    choice_type: Optional[str] = None,
    prompt_text: Optional[str] = None,
    options: Optional[List[dict]] = None,
    correct_option_id: Optional[str] = None,
    attempts_allowed: Optional[int] = None,
    time_limit_ms: Optional[int] = None,
    difficulty_level: Optional[int] = None,
    required_assets: Optional[dict] = None,
    payload: Optional[dict] = None,
) -> dict:
    timed_sec = constraints.get("timedSec") if isinstance(constraints, dict) else None
    if time_limit_ms is None and timed_sec:
        time_limit_ms = int(timed_sec) * 1000
    item = {
        "id": exercise_id,
        "type": exercise_type,
        "exercise_type": exercise_type,
        "concept_id": concept.concept_id,
        "unit_id": concept.unit_id,
        "level": level,
        "skill": skill,
        "constraints": constraints,
        "attempts_allowed": attempts_allowed if attempts_allowed is not None else 3,
        "time_limit_ms": time_limit_ms,
        "difficulty_level": difficulty_level if difficulty_level is not None else level,
        "required_assets": required_assets or _required_assets_for(exercise_type),
        "prompt_text": prompt_text,
        "prompt": {
            "hanzi": concept.text or "",
            "pinyin": concept.pinyin or "",
            "meaning": _meaning_for(concept),
        },
        "choices": choices,
        "answer_index": answer_index,
        "why": why,
        "meta": {
            "hsk_level": concept.hsk_level,
            "unit_id": concept.unit_id,
            "tags": [],
        },
    }
    if audio_url is not None:
        item["audio_url"] = audio_url
    if choice_type is not None:
        item["choice_type"] = choice_type
    if options is not None:
        item["options"] = options
    if correct_option_id is not None:
        item["correct_option_id"] = correct_option_id
    if payload is not None:
        item["payload"] = payload
    return item


def _build_why(concept: Concept, exercise_type: str, skill: str, level: int) -> dict:
    return {
        "reasons": [
            f"HSK{concept.hsk_level} pilot concept",
            f"Skill focus: {skill}",
            f"Level {level} progression",
            f"Exercise type: {exercise_type}",
        ],
        "signals": {
            "accuracy": None,
            "latencyMs": None,
            "mistakeCount": 0,
        },
    }


def _audio_url_for(concept_id: int, repo_root: Path) -> Optional[str]:
    static_path = repo_root / "backend" / "static" / "audio" / f"word_{concept_id}.mp3"
    assets_path = repo_root / "assets" / "audio" / f"word_{concept_id}.mp3"
    if static_path.exists() or assets_path.exists():
        return f"/api/v2/audio/{concept_id}"
    return None


def _load_passage(unit_id: str, repo_root: Path) -> Optional[dict]:
    path = repo_root / "backend" / "content" / "passages" / f"unit_{unit_id}_passage.json"
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate HSK1 pilot exercise pack")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--ids", default="docs/pilot/hsk1_pilot_ids.txt")
    parser.add_argument("--manifest", default="backend/content/paths/zh_standard.json")
    parser.add_argument("--out", default="docs/pilot/hsk1_exercises_v1.json")
    parser.add_argument("--copy-assets", action="store_true", default=True)
    parser.add_argument("--no-copy-assets", action="store_true", default=False)
    parser.add_argument("--assets-out", default="dragon_chinese/assets/pilot/hsk1_exercises_v1.json")
    args = parser.parse_args()

    repo_root = _repo_root()
    ids_path = repo_root / args.ids
    db_path = repo_root / args.db
    manifest_path = repo_root / args.manifest

    if not ids_path.exists():
        print(f"Missing pilot ID list: {ids_path}")
        return 1
    if not db_path.exists():
        print(f"Missing DB: {db_path}")
        return 1

    ids = _load_ids(ids_path)
    concept_to_unit, concept_to_level, units_flat = _parse_manifest(manifest_path)
    concepts = _load_concepts(db_path, concept_to_unit, concept_to_level)

    level_map = _group_by_level(concepts)
    unit_map = _group_by_unit(concepts)
    pinyin_index = _group_by_pinyin_base(concepts)

    items: List[dict] = []
    missing_concepts: List[int] = []
    repo_root = _repo_root()
    sentence_map = _load_sentence_fill(db_path)

    hsk1_units = sorted(
        {u.get("unit_id") for u in units_flat if u.get("realm_id") == "1"},
        key=lambda x: int(x) if x and str(x).isdigit() else 0,
    )

    for cid in ids:
        concept = concepts.get(cid)
        if concept is None:
            missing_concepts.append(cid)
            continue

        level = _level_for_unit(concept.unit_id, hsk1_units)

        # meaning_select
        meaning_distractors = _pick_distractors_meaning(concept, concepts, level_map, pinyin_index)
        meaning_choices_ids = [concept.concept_id] + meaning_distractors
        meaning_choices = [_meaning_for(concepts[c]) for c in meaning_choices_ids]
        meaning_order = sorted(zip(meaning_choices_ids, meaning_choices), key=lambda x: x[0])
        meaning_choices = [c for _, c in meaning_order]
        meaning_answer_index = [cid for cid, _ in meaning_order].index(concept.concept_id)
        skill = "vocab"
        items.append(
            _build_item(
                f"meaning_select_{concept.concept_id}",
                "meaning_select",
                concept,
                meaning_choices,
                meaning_answer_index,
                level,
                skill,
                _constraints_for(level, skill),
                _build_why(concept, "meaning_select", skill, level),
            )
        )

        # character_select
        character_distractors = _pick_distractors_character(
            concept, concepts, level_map, unit_map, pinyin_index
        )
        character_ids = [concept.concept_id] + character_distractors
        character_choices = [concepts[c].text or "<?>" for c in character_ids]
        character_order = sorted(zip(character_ids, character_choices), key=lambda x: x[0])
        character_choices = [c for _, c in character_order]
        character_answer_index = [cid for cid, _ in character_order].index(concept.concept_id)
        items.append(
            _build_item(
                f"character_select_{concept.concept_id}",
                "character_select",
                concept,
                character_choices,
                character_answer_index,
                level,
                skill,
                _constraints_for(level, skill),
                _build_why(concept, "character_select", skill, level),
            )
        )

        # pinyin_select
        pinyin_distractors = _pick_distractors_pinyin(
            concept, concepts, level_map, pinyin_index
        )
        pinyin_ids = [concept.concept_id] + pinyin_distractors
        pinyin_choices = [concepts[c].pinyin or "" for c in pinyin_ids]
        pinyin_order = sorted(zip(pinyin_ids, pinyin_choices), key=lambda x: x[0])
        pinyin_choices = [c for _, c in pinyin_order]
        pinyin_answer_index = [cid for cid, _ in pinyin_order].index(concept.concept_id)
        items.append(
            _build_item(
                f"pinyin_select_{concept.concept_id}",
                "pinyin_select",
                concept,
                pinyin_choices,
                pinyin_answer_index,
                level,
                skill,
                _constraints_for(level, skill),
                _build_why(concept, "pinyin_select", skill, level),
                prompt_text="Choose the correct pinyin",
            )
        )

        # reply_select
        reply_prompt = f"A: {concept.text}"
        unit_ids = unit_map.get(concept.unit_id or "", [])
        reply_correct_id = None
        if unit_ids:
            try:
                idx = unit_ids.index(concept.concept_id)
                reply_correct_id = unit_ids[(idx + 1) % len(unit_ids)]
            except ValueError:
                reply_correct_id = unit_ids[0]
        reply_correct_id = reply_correct_id or concept.concept_id
        reply_candidates = [reply_correct_id] + [
            cid for cid in unit_ids if cid != reply_correct_id
        ]
        if len(reply_candidates) < 4:
            reply_candidates.extend(
                [cid for cid in level_map.get(concept.hsk_level, []) if cid != reply_correct_id]
            )
        reply_candidates = list(dict.fromkeys(reply_candidates))[:4]
        reply_choices = [concepts[c].text or "<?>" for c in reply_candidates]
        reply_order = sorted(zip(reply_candidates, reply_choices), key=lambda x: x[0])
        reply_choices = [c for _, c in reply_order]
        reply_answer_index = [cid for cid, _ in reply_order].index(reply_correct_id)
        items.append(
            _build_item(
                f"reply_select_{concept.concept_id}",
                "reply_select",
                concept,
                reply_choices,
                reply_answer_index,
                level,
                skill,
                _constraints_for(level, skill),
                _build_why(concept, "reply_select", skill, level),
                prompt_text=f"{reply_prompt}\nChoose the best reply",
            )
        )

        # speak_read_aloud
        speak_samples = _speaking_samples(concept)
        speak_skill = "speaking"
        items.append(
            _build_item(
                f"speak_read_aloud_{concept.concept_id}",
                "speak_read_aloud",
                concept,
                [],
                0,
                level,
                speak_skill,
                _constraints_for(level, speak_skill),
                _build_why(concept, "speak_read_aloud", speak_skill, level),
                payload={"sample_answers": speak_samples},
            )
        )

        # speak_prompted_reply
        prompt_text = _prompted_reply_prompt(concept)
        reply_samples = _prompted_reply_samples(concept)
        items.append(
            _build_item(
                f"speak_prompted_reply_{concept.concept_id}",
                "speak_prompted_reply",
                concept,
                [],
                0,
                level,
                speak_skill,
                _constraints_for(level, speak_skill),
                _build_why(concept, "speak_prompted_reply", speak_skill, level),
                prompt_text=prompt_text,
                payload={"sample_answers": reply_samples},
            )
        )

        # audio_select
        choice_type = "hanzi" if concept.concept_id % 2 == 0 else "meaning"
        if choice_type == "hanzi":
            audio_choices = character_choices
            audio_answer_index = character_answer_index
        else:
            audio_choices = meaning_choices
            audio_answer_index = meaning_answer_index
        skill = "listening"
        items.append(
            _build_item(
                f"audio_select_{concept.concept_id}",
                "audio_select",
                concept,
                audio_choices,
                audio_answer_index,
                level,
                skill,
                _constraints_for(level, skill),
                _build_why(concept, "audio_select", skill, level),
                audio_url=_audio_url_for(concept.concept_id, repo_root),
                choice_type=choice_type,
            )
        )

        # dictation_select
        dictation_sentence = sentence_map.get(concept.concept_id, {}).get(
            "sentence", f"我喜欢{concept.text}。"
        )
        dictation_distractors = _pick_distractors_character(
            concept, concepts, level_map, unit_map, pinyin_index
        )
        (
            dictation_choices,
            dictation_answer_index,
            dictation_options,
            dictation_correct_id,
        ) = _build_dictation_options(
            concept,
            dictation_sentence,
            concepts,
            dictation_distractors,
        )
        items.append(
            _build_item(
                f"dictation_select_{concept.concept_id}",
                "dictation_select",
                concept,
                dictation_choices,
                dictation_answer_index,
                level,
                skill,
                _constraints_for(level, skill),
                _build_why(concept, "dictation_select", skill, level),
                audio_url=_audio_url_for(concept.concept_id, repo_root),
                prompt_text="Listen and choose the correct sentence",
                options=dictation_options,
                correct_option_id=dictation_correct_id,
            )
        )

        # cloze_select
        sentence_info = sentence_map.get(concept.concept_id, {})
        raw_sentence = sentence_info.get("sentence", f"我喜欢{concept.text}。")
        correct = sentence_info.get("correct") or concept.text
        cloze_sentence = _make_cloze_sentence(raw_sentence, correct, concept.text)
        cloze_distractors = _pick_distractors_character(
            concept, concepts, level_map, unit_map, pinyin_index
        )
        cloze_ids = [concept.concept_id] + cloze_distractors
        cloze_choices = [concepts[c].text or "<?>" for c in cloze_ids]
        cloze_order = sorted(zip(cloze_ids, cloze_choices), key=lambda x: x[0])
        cloze_choices = [c for _, c in cloze_order]
        cloze_answer_index = [cid for cid, _ in cloze_order].index(concept.concept_id)
        cloze_skill = "grammar" if level >= 2 else "reading"
        items.append(
            _build_item(
                f"cloze_select_{concept.concept_id}",
                "cloze_select",
                concept,
                cloze_choices,
                cloze_answer_index,
                level,
                cloze_skill,
                _constraints_for(level, cloze_skill),
                _build_why(concept, "cloze_select", cloze_skill, level),
                payload={"sentence": cloze_sentence},
            )
        )

        # order_sentence
        full_sentence = raw_sentence.replace("____", correct) if raw_sentence else f"{concept.text}。"
        order_chunks, order_answer = _chunk_sentence(full_sentence, level)
        items.append(
            _build_item(
                f"order_sentence_{concept.concept_id}",
                "order_sentence",
                concept,
                [],
                0,
                level,
                "grammar",
                _constraints_for(level, "grammar"),
                _build_why(concept, "order_sentence", "grammar", level),
                payload={
                    "chunks": order_chunks,
                    "answer": order_answer,
                    "sentence": full_sentence,
                },
            )
        )

    # reading_micro per unit
    unit_ids = [u.get("unit_id") for u in units_flat if u.get("unit_id")]
    # reading_micro per unit (one per unit with passage + concept)
    for unit in units_flat:
        unit_id = unit.get("unit_id")
        if not unit_id:
            continue
        passage = _load_passage(unit_id, repo_root)
        if not passage:
            continue
        unit_word_ids = [int(w) for w in unit.get("word_ids", []) if str(w).isdigit()]
        concept_id = unit_word_ids[0] if unit_word_ids else None
        if concept_id is None:
            continue
        concept = concepts.get(concept_id)
        if concept is None:
            continue

        # Question 1: meaning_select based on unit's first concept
        meaning_distractors = _pick_distractors_meaning(concept, concepts, level_map, pinyin_index)
        meaning_choices_ids = [concept.concept_id] + meaning_distractors
        meaning_choices = [_meaning_for(concepts[c]) for c in meaning_choices_ids]
        meaning_order = sorted(zip(meaning_choices_ids, meaning_choices), key=lambda x: x[0])
        meaning_choices = [c for _, c in meaning_order]
        meaning_answer_index = [cid for cid, _ in meaning_order].index(concept.concept_id)

        # Question 2: detail_select using passage first sentence (EN)
        story_en = (passage.get("story_en") or "").strip()
        sentences = [s.strip() for s in story_en.split(".") if s.strip()]
        correct_detail = sentences[0] + "." if sentences else story_en
        # pick 3 other unit sentences deterministically
        distractors: List[str] = []
        for other_unit in unit_ids:
            if other_unit == unit_id:
                continue
            other_passage = _load_passage(other_unit, repo_root)
            if not other_passage:
                continue
            other_story = (other_passage.get("story_en") or "").strip()
            other_sents = [s.strip() for s in other_story.split(".") if s.strip()]
            if other_sents:
                candidate = other_sents[0] + "."
                if candidate != correct_detail and candidate not in distractors:
                    distractors.append(candidate)
            if len(distractors) >= 3:
                break
        while len(distractors) < 3:
            distractors.append("Detail unavailable.")

        detail_choices = [correct_detail] + distractors
        detail_choices = sorted(detail_choices)
        detail_answer_index = detail_choices.index(correct_detail)

        level = _level_for_unit(concept.unit_id, hsk1_units)
        skill = "reading"
        reading_payload = {
            "reading": {
                "title_zh": passage.get("title_zh") or "",
                "title_en": passage.get("title_en") or "",
                "story_zh": passage.get("story_zh") or "",
                "story_pinyin": passage.get("story_pinyin") or "",
                "story_en": passage.get("story_en") or "",
            },
            "questions": [
                {
                    "type": "meaning_select",
                    "prompt": {
                        "hanzi": concept.text or "",
                        "pinyin": concept.pinyin or "",
                        "meaning": _meaning_for(concept),
                    },
                    "choices": meaning_choices,
                    "answer_index": meaning_answer_index,
                },
                {
                    "type": "detail_select",
                    "prompt": {
                        "question": "Which detail appears in the passage?",
                    },
                    "choices": detail_choices,
                    "answer_index": detail_answer_index,
                },
            ],
        }
        items.append(
            _build_item(
                f"reading_micro_{unit_id}",
                "reading_micro",
                concept,
                [],
                0,
                level,
                skill,
                _constraints_for(level, skill),
                _build_why(concept, "reading_micro", skill, level),
                payload=reading_payload,
            )
        )

    # meaning_match per unit
    for unit in units_flat:
        unit_id = unit.get("unit_id")
        if not unit_id:
            continue
        unit_word_ids = [int(w) for w in unit.get("word_ids", []) if str(w).isdigit()]
        if len(unit_word_ids) < 2:
            continue
        concept_id = unit_word_ids[0]
        concept = concepts.get(concept_id)
        if concept is None:
            continue
        sample_ids = unit_word_ids[:5]
        pairs = []
        for cid in sample_ids:
            c = concepts.get(cid)
            if not c:
                continue
            pairs.append({"hanzi": c.text or "", "meaning": _meaning_for(c)})
        left = [p["hanzi"] for p in pairs]
        right = sorted([p["meaning"] for p in pairs], key=lambda x: _stable_hash(x))
        mapping = [right.index(p["meaning"]) for p in pairs] if pairs else []
        level = _level_for_unit(concept.unit_id, hsk1_units)
        skill = "vocab"
        items.append(
            _build_item(
                f"meaning_match_{unit_id}",
                "meaning_match",
                concept,
                [],
                0,
                level,
                skill,
                _constraints_for(level, skill),
                _build_why(concept, "meaning_match", skill, level),
                payload={
                    "pairs": pairs,
                    "left": left,
                    "right": right,
                    "mapping": mapping,
                },
            )
        )

    output = {
        "schema_version": 3,
        "generated_at": date.today().isoformat(),
        "items": items,
        "missing_concepts": missing_concepts,
    }

    out_path = repo_root / args.out
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")

    copy_assets = args.copy_assets and not args.no_copy_assets
    if copy_assets:
        assets_path = repo_root / args.assets_out
        assets_path.parent.mkdir(parents=True, exist_ok=True)
        assets_path.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")

    type_counts = {
        "meaning_select": sum(1 for item in items if item["exercise_type"] == "meaning_select"),
        "character_select": sum(1 for item in items if item["exercise_type"] == "character_select"),
        "pinyin_select": sum(1 for item in items if item["exercise_type"] == "pinyin_select"),
        "reply_select": sum(1 for item in items if item["exercise_type"] == "reply_select"),
        "speak_read_aloud": sum(1 for item in items if item["exercise_type"] == "speak_read_aloud"),
        "speak_prompted_reply": sum(
            1 for item in items if item["exercise_type"] == "speak_prompted_reply"
        ),
        "audio_select": sum(1 for item in items if item["exercise_type"] == "audio_select"),
        "dictation_select": sum(1 for item in items if item["exercise_type"] == "dictation_select"),
        "cloze_select": sum(1 for item in items if item["exercise_type"] == "cloze_select"),
        "order_sentence": sum(1 for item in items if item["exercise_type"] == "order_sentence"),
        "reading_micro": sum(1 for item in items if item["exercise_type"] == "reading_micro"),
        "meaning_match": sum(1 for item in items if item["exercise_type"] == "meaning_match"),
    }
    skill_counts: Dict[str, int] = {}
    level_counts: Dict[int, int] = {}
    for item in items:
        skill_counts[item["skill"]] = skill_counts.get(item["skill"], 0) + 1
        level_counts[item["level"]] = level_counts.get(item["level"], 0) + 1

    print(f"Generated {len(items)} items")
    print(f"meaning_select: {type_counts['meaning_select']}")
    print(f"character_select: {type_counts['character_select']}")
    print(f"pinyin_select: {type_counts['pinyin_select']}")
    print(f"reply_select: {type_counts['reply_select']}")
    print(f"speak_read_aloud: {type_counts['speak_read_aloud']}")
    print(f"speak_prompted_reply: {type_counts['speak_prompted_reply']}")
    print(f"audio_select: {type_counts['audio_select']}")
    print(f"dictation_select: {type_counts['dictation_select']}")
    print(f"cloze_select: {type_counts['cloze_select']}")
    print(f"order_sentence: {type_counts['order_sentence']}")
    print(f"reading_micro: {type_counts['reading_micro']}")
    print(f"meaning_match: {type_counts['meaning_match']}")
    print(f"by_skill: {dict(sorted(skill_counts.items()))}")
    print(f"by_level: {dict(sorted(level_counts.items()))}")
    if missing_concepts:
        print(f"Missing concepts: {len(missing_concepts)}")
    print(f"Wrote {out_path}")
    if copy_assets:
        print(f"Wrote {assets_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
