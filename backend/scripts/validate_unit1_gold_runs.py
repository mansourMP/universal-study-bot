#!/usr/bin/env python3
"""Validate UNIT_HSK1_001 end-to-end mission flow across multiple runs.

This script exercises the live Brain mission contract by simulating full
circle progression (C1..C7) and submitting every returned exercise.

Checks:
- Mission creation succeeds for each circle.
- Each circle returns at least one exercise.
- C3 includes speaking exercise types.
- C6/C7 do not include unseen words (must be subset of words introduced in C1..C5).
- Exercise submission succeeds for every exercise in every circle.

Output:
- JSON report in docs/reports/
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import logging
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Set

from fastapi.testclient import TestClient


ROOT = Path(__file__).resolve().parents[2]
BACKEND_DIR = ROOT / "backend"
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from main import app  # noqa: E402


SPEAKING_TYPES = {"speak_read_aloud", "speak_prompted_reply", "speaking"}
DEFAULT_CIRCLES = ["C1", "C2", "C3", "C4", "C5", "C6", "C7"]


@dataclass
class CircleResult:
    circle_id: str
    mission_ok: bool
    submit_ok: bool
    exercise_count: int
    types: List[str] = field(default_factory=list)
    words: List[str] = field(default_factory=list)
    failures: List[str] = field(default_factory=list)


@dataclass
class RunResult:
    run_index: int
    user_id: str
    ok: bool
    circles: List[CircleResult] = field(default_factory=list)
    failures: List[str] = field(default_factory=list)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate Unit 1 gold runs")
    parser.add_argument("--unit-id", default="UNIT_HSK1_001")
    parser.add_argument("--runs", type=int, default=10)
    parser.add_argument("--limit", type=int, default=12)
    parser.add_argument("--intent", default="learn")
    parser.add_argument("--language-code", default="zh")
    parser.add_argument("--user-prefix", default="gold_unit1_validator")
    parser.add_argument("--report-dir", default="docs/reports")
    parser.add_argument(
        "--out",
        default="",
        help="Optional explicit report path. If empty, auto-generated in report-dir.",
    )
    return parser.parse_args()


def _mission_payload(
    *,
    unit_id: str,
    circle_index: int,
    intent: str,
    limit: int,
    language_code: str,
) -> Dict[str, Any]:
    return {
        "language_code": language_code,
        "intent": intent,
        "limit": limit,
        "unit_id": unit_id,
        "node_id": f"{unit_id}_L{circle_index}",
    }


def _submit_payload(
    *,
    user_id: str,
    language_code: str,
    mission_id: str,
    exercise: Dict[str, Any],
) -> Dict[str, Any]:
    return {
        "user_id": user_id,
        "language_code": language_code,
        "mission_id": mission_id,
        "exercise_id": exercise["exercise_id"],
        "word_id": exercise["word_id"],
        "sense_id": exercise.get("sense_id"),
        "plan_slot_id": exercise["plan_slot_id"],
        "is_correct": True,
        "latency_ms": 1400,
    }


def _as_sorted_list(items: Set[str]) -> List[str]:
    return sorted(items, key=lambda x: (len(x), x))


def _run_once(
    client: TestClient,
    *,
    run_index: int,
    user_id: str,
    unit_id: str,
    intent: str,
    limit: int,
    language_code: str,
) -> RunResult:
    run = RunResult(run_index=run_index, user_id=user_id, ok=True)
    headers = {"X-User-Id": user_id}
    introduced_words: Set[str] = set()

    for idx, circle_id in enumerate(DEFAULT_CIRCLES, start=1):
        circle = CircleResult(
            circle_id=circle_id,
            mission_ok=False,
            submit_ok=True,
            exercise_count=0,
        )
        payload = _mission_payload(
            unit_id=unit_id,
            circle_index=idx,
            intent=intent,
            limit=limit,
            language_code=language_code,
        )

        mission_resp = client.post("/api/v2/brain/mission", json=payload, headers=headers)
        if mission_resp.status_code != 200:
            circle.failures.append(
                f"mission_status_{mission_resp.status_code}: {mission_resp.text[:220]}"
            )
            circle.mission_ok = False
            circle.submit_ok = False
            run.ok = False
            run.failures.append(f"{circle_id}: mission failed")
            run.circles.append(circle)
            continue

        body = mission_resp.json()
        exercises = body.get("exercises", [])
        mission_id = body.get("mission_id")
        circle.mission_ok = True
        circle.exercise_count = len(exercises)

        if not mission_id:
            circle.failures.append("missing_mission_id")
            circle.submit_ok = False
            run.ok = False
            run.failures.append(f"{circle_id}: missing mission_id")

        if not exercises:
            circle.failures.append("no_exercises_returned")
            circle.submit_ok = False
            run.ok = False
            run.failures.append(f"{circle_id}: no exercises")

        types: Set[str] = set()
        words: Set[str] = set()
        for ex in exercises:
            ex_type = str(ex.get("type", "")).strip()
            word_id = str(ex.get("word_id", "")).strip()
            if ex_type:
                types.add(ex_type)
            if word_id:
                words.add(word_id)

        circle.types = _as_sorted_list(types)
        circle.words = _as_sorted_list(words)

        if circle_id == "C3":
            if not any(t in SPEAKING_TYPES for t in types):
                circle.failures.append("c3_missing_speaking_type")
                run.ok = False
                run.failures.append("C3 missing speaking type")

        if circle_id in {"C1", "C2", "C3", "C4", "C5"}:
            introduced_words.update(words)

        if circle_id in {"C6", "C7"}:
            unseen = words.difference(introduced_words)
            if unseen:
                circle.failures.append(f"unseen_words_in_{circle_id}: {sorted(unseen)}")
                run.ok = False
                run.failures.append(f"{circle_id} contains unseen words")

        if mission_id:
            for ex in exercises:
                submit_payload = _submit_payload(
                    user_id=user_id,
                    language_code=language_code,
                    mission_id=mission_id,
                    exercise=ex,
                )
                submit_resp = client.post(
                    "/api/v2/brain/submit",
                    json=submit_payload,
                    headers=headers,
                )
                if submit_resp.status_code != 200:
                    circle.submit_ok = False
                    circle.failures.append(
                        f"submit_status_{submit_resp.status_code} "
                        f"exercise={ex.get('exercise_id')}"
                    )
                    run.ok = False
                    run.failures.append(
                        f"{circle_id} submit failed ({ex.get('exercise_id')})"
                    )
                    break

        run.circles.append(circle)

    return run


def main() -> int:
    args = _parse_args()
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("uvicorn").setLevel(logging.WARNING)
    logging.getLogger("apscheduler").setLevel(logging.WARNING)
    timestamp = dt.datetime.now(dt.UTC).strftime("%Y-%m-%dT%H-%M-%SZ")
    report_dir = (ROOT / args.report_dir).resolve()
    report_dir.mkdir(parents=True, exist_ok=True)

    if args.out:
        out_path = Path(args.out).resolve()
        out_path.parent.mkdir(parents=True, exist_ok=True)
    else:
        out_path = report_dir / f"unit1_gold_validation_{timestamp}.json"

    runs: List[RunResult] = []
    with TestClient(app) as client:
        for i in range(1, max(1, args.runs) + 1):
            user_id = f"{args.user_prefix}_{i:02d}"
            run = _run_once(
                client,
                run_index=i,
                user_id=user_id,
                unit_id=args.unit_id,
                intent=args.intent,
                limit=args.limit,
                language_code=args.language_code,
            )
            runs.append(run)

    run_ok_count = sum(1 for r in runs if r.ok)
    circle_failures = sum(
        1 for r in runs for c in r.circles if c.failures
    )
    types_all: Set[str] = set()
    types_by_circle: Dict[str, Set[str]] = {cid: set() for cid in DEFAULT_CIRCLES}
    avg_exercises_by_circle: Dict[str, float] = {}
    for cid in DEFAULT_CIRCLES:
        counts = []
        for r in runs:
            for c in r.circles:
                if c.circle_id == cid:
                    counts.append(c.exercise_count)
                    types_by_circle[cid].update(c.types)
                    types_all.update(c.types)
        avg_exercises_by_circle[cid] = round(sum(counts) / len(counts), 2) if counts else 0.0

    payload = {
        "ok": run_ok_count == len(runs),
        "unit_id": args.unit_id,
        "runs_requested": args.runs,
        "runs_ok": run_ok_count,
        "runs_failed": len(runs) - run_ok_count,
        "circle_failures": circle_failures,
        "coverage": {
            "exercise_types_all": sorted(types_all),
            "exercise_types_by_circle": {
                cid: sorted(types_by_circle[cid]) for cid in DEFAULT_CIRCLES
            },
            "avg_exercises_by_circle": avg_exercises_by_circle,
        },
        "config": {
            "intent": args.intent,
            "limit": args.limit,
            "language_code": args.language_code,
            "circles": DEFAULT_CIRCLES,
        },
        "runs": [
            {
                "run_index": r.run_index,
                "user_id": r.user_id,
                "ok": r.ok,
                "failures": r.failures,
                "circles": [
                    {
                        "circle_id": c.circle_id,
                        "mission_ok": c.mission_ok,
                        "submit_ok": c.submit_ok,
                        "exercise_count": c.exercise_count,
                        "types": c.types,
                        "words": c.words,
                        "failures": c.failures,
                    }
                    for c in r.circles
                ],
            }
            for r in runs
        ],
    }

    out_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"ok": payload["ok"], "out": str(out_path), "runs_ok": run_ok_count, "runs_total": len(runs)}))
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
