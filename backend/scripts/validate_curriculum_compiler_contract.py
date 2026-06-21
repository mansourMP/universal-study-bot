#!/usr/bin/env python3
"""Validate HSK1 curriculum compiler contract against DB integrity rules."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sqlite3
from pathlib import Path
from typing import Any, Dict, List, Set, Tuple


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _load_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _db_primary_sense_map(conn: sqlite3.Connection) -> Dict[str, str]:
    rows = conn.execute(
        """
        SELECT concept_id, sense_id
        FROM concept_senses
        WHERE is_primary = 1
        """
    ).fetchall()
    return {str(r[0]): str(r[1]) for r in rows}


def _db_concepts(conn: sqlite3.Connection) -> Dict[str, Tuple[str, str, str]]:
    rows = conn.execute(
        """
        SELECT id, COALESCE(text,''), COALESCE(pinyin,''), COALESCE(meaning,'')
        FROM concepts
        """
    ).fetchall()
    return {str(r[0]): (str(r[1]), str(r[2]), str(r[3])) for r in rows}


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate curriculum compiler contract")
    parser.add_argument("--contract", default="docs/specs/hsk1_unit_word_contract_v1.json")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--report-dir", default="docs/reports")
    args = parser.parse_args()

    root = _repo_root()
    contract_path = root / args.contract
    db_path = root / args.db
    report_dir = root / args.report_dir
    report_dir.mkdir(parents=True, exist_ok=True)

    if not contract_path.exists():
        print(json.dumps({"ok": False, "error": f"Contract not found: {contract_path}"}))
        return 1
    if not db_path.exists():
        print(json.dumps({"ok": False, "error": f"DB not found: {db_path}"}))
        return 1

    contract = _load_json(contract_path)

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout = 20000")
    try:
        concepts = _db_concepts(conn)
        primary_sense = _db_primary_sense_map(conn)
    finally:
        conn.close()

    expected_circles = ["C1", "C2", "C3", "C4", "C5", "C6", "C7"]
    violations: List[str] = []
    warnings: List[str] = []

    policy = contract.get("policy", {}) if isinstance(contract, dict) else {}
    review_cap = int(policy.get("review_item_cap", 10))
    min_duration = 180
    max_duration = 300

    units = contract.get("units") or []
    if not isinstance(units, list):
        print(json.dumps({"ok": False, "error": "contract.units must be an array"}))
        return 1

    if str(contract.get("standard", "")).strip().upper() != "HSK3.0":
        violations.append("standard must be HSK3.0")
    if str(contract.get("level", "")).strip().upper() != "HSK1":
        violations.append("level must be HSK1")
    if len(units) != 32:
        violations.append(f"units count must be 32 (got {len(units)})")

    distinct_words: Set[str] = set()
    distinct_senses: Set[str] = set()

    for unit in units:
        unit_id = str(unit.get("unit_id", ""))
        words = unit.get("words") or []
        circles = unit.get("circles") or []
        declared_size = int(unit.get("size", len(words)))

        if not unit_id.startswith("UNIT_HSK1_"):
            violations.append(f"{unit_id}: invalid unit_id")

        if not isinstance(words, list) or not words:
            violations.append(f"{unit_id}: words missing/empty")
            continue

        if len(words) != declared_size:
            violations.append(f"{unit_id}: size mismatch declared={declared_size} actual={len(words)}")

        unit_word_ids = [str(w.get("word_id", "")) for w in words]
        if len(set(unit_word_ids)) != len(unit_word_ids):
            violations.append(f"{unit_id}: duplicate word_id in unit words")

        unit_word_set = set(unit_word_ids)
        for w in words:
            wid = str(w.get("word_id", ""))
            sid = str(w.get("sense_id", ""))
            hanzi = str(w.get("hanzi", ""))
            pinyin = str(w.get("pinyin", ""))
            meaning = str(w.get("meaning_en", ""))
            distinct_words.add(wid)
            if sid:
                distinct_senses.add(sid)

            if wid not in concepts:
                violations.append(f"{unit_id}: word not in DB: {wid}")
                continue
            db_hanzi, db_pinyin, db_meaning = concepts[wid]
            if hanzi and db_hanzi and hanzi != db_hanzi:
                violations.append(f"{unit_id}:{wid}: hanzi mismatch contract='{hanzi}' db='{db_hanzi}'")
            if pinyin and db_pinyin and pinyin != db_pinyin:
                warnings.append(f"{unit_id}:{wid}: pinyin differs contract='{pinyin}' db='{db_pinyin}'")
            if meaning and db_meaning and meaning != db_meaning:
                warnings.append(f"{unit_id}:{wid}: meaning differs contract='{meaning}' db='{db_meaning}'")

            ps = primary_sense.get(wid, "")
            if not sid:
                violations.append(f"{unit_id}:{wid}: missing sense_id")
            elif ps and sid != ps:
                violations.append(f"{unit_id}:{wid}: sense_id not primary (contract={sid}, db={ps})")

        if not isinstance(circles, list) or len(circles) != 7:
            violations.append(f"{unit_id}: circles must contain 7 entries")
            continue

        actual_circle_ids = [str(c.get("circle_id", "")) for c in circles]
        if actual_circle_ids != expected_circles:
            violations.append(f"{unit_id}: circle order must be {expected_circles} (got {actual_circle_ids})")

        circle_map = {str(c.get("circle_id", "")): c for c in circles}
        introduced = set()
        for cid in ("C1", "C2", "C3", "C4", "C5"):
            c = circle_map.get(cid, {})
            focus = c.get("focus") or []
            if not isinstance(focus, list):
                violations.append(f"{unit_id}:{cid}: focus must be list")
                continue
            for item in focus:
                wid = str(item.get("word_id", ""))
                sid = str(item.get("sense_id", ""))
                if wid not in unit_word_set:
                    violations.append(f"{unit_id}:{cid}: focus word not in unit words: {wid}")
                if sid and primary_sense.get(wid, sid) != sid:
                    violations.append(f"{unit_id}:{cid}:{wid}: focus sense mismatch primary")
                introduced.add(wid)

            d = int(c.get("duration_target_sec", 0) or 0)
            if d < min_duration or d > max_duration:
                violations.append(f"{unit_id}:{cid}: duration_target_sec out of range [{min_duration},{max_duration}]")

        for cid in ("C6", "C7"):
            c = circle_map.get(cid, {})
            focus = c.get("focus") or []
            if not isinstance(focus, list):
                violations.append(f"{unit_id}:{cid}: focus must be list")
                continue
            for item in focus:
                wid = str(item.get("word_id", ""))
                if wid not in introduced:
                    violations.append(f"{unit_id}:{cid}: unseen review word: {wid}")
                if wid not in unit_word_set:
                    violations.append(f"{unit_id}:{cid}: focus word not in unit words: {wid}")

            tcount = int(c.get("target_exercise_count", 0) or 0)
            if tcount > review_cap:
                violations.append(f"{unit_id}:{cid}: target_exercise_count {tcount} exceeds review cap {review_cap}")
            d = int(c.get("duration_target_sec", 0) or 0)
            if d < min_duration or d > max_duration:
                violations.append(f"{unit_id}:{cid}: duration_target_sec out of range [{min_duration},{max_duration}]")

    if len(distinct_words) != 500:
        violations.append(f"distinct words must be 500 (got {len(distinct_words)})")

    report = {
        "ok": len(violations) == 0,
        "date": dt.date.today().isoformat(),
        "contract": str(contract_path),
        "db": str(db_path),
        "checks": {
            "units": len(units),
            "distinct_words": len(distinct_words),
            "distinct_senses": len(distinct_senses),
            "review_item_cap": review_cap,
            "duration_range_sec": [min_duration, max_duration],
            "violations": len(violations),
            "warnings": len(warnings),
        },
        "violations": violations[:400],
        "warnings": warnings[:400],
    }

    out = report_dir / f"validate_curriculum_compiler_contract_{dt.date.today().isoformat()}.json"
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"ok": report["ok"], "checks": report["checks"], "report": str(out)}, ensure_ascii=False))
    return 0 if report["ok"] else 2


if __name__ == "__main__":
    raise SystemExit(main())

