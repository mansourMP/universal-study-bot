#!/usr/bin/env python3
"""Report exercise variant coverage by unit and lesson."""

from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path
from typing import Dict, List, Set, Tuple
import importlib.util


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _load_srs_plan(repo_root: Path):
    srs_path = repo_root / "backend" / "learning_path" / "srs_plan.py"
    spec = importlib.util.spec_from_file_location("srs_plan", srs_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load srs_plan from {srs_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _connect(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    return conn


def _load_manifest(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def _collect_unit_lesson_words(manifest: dict) -> Tuple[Dict[str, List[str]], Dict[str, List[str]]]:
    unit_words: Dict[str, List[str]] = {}
    lesson_words: Dict[str, List[str]] = {}

    realms = manifest.get("realms", {})
    for realm in realms.values():
        for unit in realm.get("units", []):
            unit_id = str(unit.get("unit_number"))
            words: List[str] = []
            for lesson in unit.get("lessons", []):
                lesson_number = lesson.get("lesson_number")
                lesson_id = f"unit_{unit_id}_l_{lesson_number}"
                lesson_word_ids = [str(w) for w in lesson.get("word_ids", [])]
                lesson_words[lesson_id] = lesson_word_ids
                words.extend(lesson_word_ids)
            unit_words[unit_id] = words

    return unit_words, lesson_words


def _exercise_counts(conn: sqlite3.Connection) -> Dict[str, Dict[str, int]]:
    rows = conn.execute(
        "SELECT word_id, exercise_type, COUNT(*) FROM word_exercises GROUP BY word_id, exercise_type"
    ).fetchall()
    counts: Dict[str, Dict[str, int]] = {}
    for row in rows:
        word_id = str(row[0])
        ex_type = row[1]
        count = int(row[2])
        counts.setdefault(word_id, {})[ex_type] = count
    return counts


def _has_any_type(ex_types: Dict[str, int], allowed: Set[str]) -> bool:
    return any(t in ex_types for t in allowed)


def _total_variants(ex_types: Dict[str, int]) -> int:
    return sum(ex_types.values())


def _percent(part: int, total: int) -> float:
    return (part / total) * 100 if total else 0.0


def _report_group(title: str, word_ids: List[str], ex_counts: Dict[str, Dict[str, int]],
                  stage0_types: Set[str], tone_types: Set[str], usage_types: Set[str]) -> None:
    total = len(word_ids)
    if total == 0:
        print(f"{title}: 0 words")
        return

    stage0_ok = 0
    tone_ok = 0
    usage_ok = 0
    worst: List[Tuple[str, int]] = []

    for wid in word_ids:
        ex_types = ex_counts.get(wid, {})
        if _has_any_type(ex_types, stage0_types):
            stage0_ok += 1
        if _has_any_type(ex_types, tone_types):
            tone_ok += 1
        if _has_any_type(ex_types, usage_types):
            usage_ok += 1
        worst.append((wid, _total_variants(ex_types)))

    worst.sort(key=lambda x: (x[1], x[0]))

    print(f"{title}: {total} words")
    print(f"  Stage0 coverage ({sorted(stage0_types)}): {stage0_ok}/{total} ({_percent(stage0_ok, total):.1f}%)")
    print(f"  Tone coverage ({sorted(tone_types)}): {tone_ok}/{total} ({_percent(tone_ok, total):.1f}%)")
    print(f"  Usage coverage ({sorted(usage_types)}): {usage_ok}/{total} ({_percent(usage_ok, total):.1f}%)")
    print("  Worst covered (fewest variants):")
    for wid, count in worst[:10]:
        print(f"    {wid}: {count}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Report variant coverage by unit and lesson")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--manifest", default="backend/content/paths/zh_standard.json")
    args = parser.parse_args()

    repo_root = _repo_root()
    db_path = repo_root / args.db
    manifest_path = repo_root / args.manifest

    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1
    if not manifest_path.exists():
        print(f"Manifest not found: {manifest_path}")
        return 1

    manifest = _load_manifest(manifest_path)
    unit_words, lesson_words = _collect_unit_lesson_words(manifest)

    conn = _connect(db_path)
    try:
        ex_counts = _exercise_counts(conn)
    finally:
        conn.close()

    srs_plan = _load_srs_plan(repo_root)
    stage0_types = set(srs_plan.SKILL_TO_TYPES.get("recognition", []))
    tone_types = set(srs_plan.SKILL_TO_TYPES.get("tone", []))
    usage_types = set(srs_plan.SKILL_TO_TYPES.get("usage", []))

    print("--- Variant Coverage Report ---")
    print(f"Stage0 types from srs_plan: {sorted(stage0_types)}")
    print(f"Tone types from srs_plan: {sorted(tone_types)}")
    print(f"Usage types from srs_plan: {sorted(usage_types)}")

    print("\n--- By Unit ---")
    for unit_id in sorted(unit_words.keys(), key=lambda x: int(x)):
        _report_group(f"Unit {unit_id}", unit_words[unit_id], ex_counts, stage0_types, tone_types, usage_types)

    if lesson_words:
        print("\n--- By Lesson ---")
        for lesson_id in sorted(lesson_words.keys()):
            _report_group(lesson_id, lesson_words[lesson_id], ex_counts, stage0_types, tone_types, usage_types)

    # Overall worst covered words
    manifest_words = sorted({w for words in unit_words.values() for w in words})
    overall = [(wid, _total_variants(ex_counts.get(wid, {}))) for wid in manifest_words]
    overall.sort(key=lambda x: (x[1], x[0]))

    print("\n--- Overall Worst Covered (Top 50) ---")
    for wid, count in overall[:50]:
        print(f"{wid}: {count}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
