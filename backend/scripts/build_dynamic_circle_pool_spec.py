#!/usr/bin/env python3
"""
Build dynamic circle pool config from a unit spec.

Input: docs/specs/hsk1_unit_001_gold_v1.json (or compatible)
Output: docs/specs/hsk1_unit_001_dynamic_pool_v1.json
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Dict, List, Tuple


def _pool_target_for_circle(circle_id: str, role: str) -> int:
    if circle_id in {"C6", "C7"} or role in {"story_radio", "checkpoint"}:
        return 60
    if role == "speaking":
        return 45
    return 50


def _modality_mix(role: str) -> Dict[str, int]:
    if role == "speaking":
        return {"listening": 10, "reading": 8, "usage": 12, "speaking": 15}
    if role == "story_radio":
        return {"listening": 18, "reading": 14, "usage": 16, "speaking": 8}
    if role == "checkpoint":
        return {"listening": 16, "reading": 14, "usage": 18, "speaking": 12}
    if role == "new":
        return {"listening": 12, "reading": 12, "usage": 18, "speaking": 8}
    return {"listening": 12, "reading": 12, "usage": 18, "speaking": 8}


def _build_circle_pool(circle: Dict[str, Any]) -> Dict[str, Any]:
    circle_id = str(circle.get("circle_id", ""))
    role = str(circle.get("role", "review"))
    focus_words = list(circle.get("focus_word_ids", []))

    pool_size = _pool_target_for_circle(circle_id, role)
    serve_min, serve_target = 10, 12
    serve_cap = 18 if role in {"story_radio", "checkpoint"} else 15

    is_new_circle = circle_id in {"C1", "C4"} or role == "new"

    return {
        "circle_id": circle_id,
        "role": role,
        "focus_word_ids": focus_words,
        "pool": {
            "candidate_pool_size": pool_size,
            "modality_distribution_target": _modality_mix(role),
            "new_target_checks_per_word_min": 2 if is_new_circle else 0,
            "appearances_per_target_word_min": 6 if is_new_circle else 4,
            "pattern_key_unique_within_run": True,
        },
        "runtime_serving": {
            "serve_min": serve_min,
            "serve_target": serve_target,
            "serve_cap": serve_cap,
            "early_pass": {
                "evaluate_after_n": 10,
                "accuracy_gte": 0.85,
                "critical_misses_eq": 0,
                "spam_fast_eq": False,
            },
            "extension": {
                "trigger_accuracy_lt": 0.75,
                "trigger_repeated_target_misses_gte": 2,
                "append_items_min": 3,
                "append_items_max": 6,
                "prioritize": [
                    "missed_targets",
                    "weakest_modality",
                    "lower_difficulty_by_one",
                ],
            },
        },
    }


def build(input_path: Path) -> Dict[str, Any]:
    payload = json.loads(input_path.read_text(encoding="utf-8"))
    unit = payload.get("unit", payload)
    unit_id = unit.get("unit_id")
    circles = unit.get("circles", [])
    if not unit_id or not isinstance(circles, list) or not circles:
        raise ValueError("Invalid unit payload: missing unit_id/circles")

    return {
        "id": f"{unit_id}_dynamic_pool_v1",
        "unit_id": unit_id,
        "unit_name": unit.get("unit_name"),
        "objective": unit.get("objective"),
        "rules": {
            "no_unseen_in": ["C5", "C6", "C7"],
            "checkpoint_must_be_last": True,
            "speaking_mandatory_circle": "C3",
        },
        "run_defaults": {
            "serve_min": 10,
            "serve_target": 12,
            "serve_cap_normal": 15,
            "serve_cap_struggle": 18,
        },
        "circles": [_build_circle_pool(c) for c in circles],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--input",
        default="docs/specs/hsk1_unit_001_gold_v1.json",
        help="Input unit spec JSON",
    )
    parser.add_argument(
        "--out",
        default="docs/specs/hsk1_unit_001_dynamic_pool_v1.json",
        help="Output dynamic pool spec JSON",
    )
    args = parser.parse_args()

    in_path = Path(args.input).resolve()
    out_path = Path(args.out).resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)

    result = build(in_path)
    out_path.write_text(
        json.dumps(result, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(json.dumps({"ok": True, "out": str(out_path), "unit_id": result["unit_id"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

