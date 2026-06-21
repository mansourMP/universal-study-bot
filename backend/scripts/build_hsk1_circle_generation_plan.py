#!/usr/bin/env python3
"""Build deterministic HSK1 circle generation plan from DB + template.

Outputs a JSON plan that content generators can consume directly.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sqlite3
from pathlib import Path
from typing import Any, Dict, List


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _read_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _load_units(conn: sqlite3.Connection) -> List[Dict[str, Any]]:
    rows = conn.execute(
        """
        SELECT id, level, unit_number, title
        FROM units
        WHERE id LIKE 'UNIT_HSK1_%'
        ORDER BY unit_number ASC
        """
    ).fetchall()
    return [
        {
            "unit_id": str(r[0]),
            "level": str(r[1]),
            "unit_number": int(r[2]),
            "title": str(r[3]),
        }
        for r in rows
    ]


def _load_unit_words(conn: sqlite3.Connection, unit_id: str) -> List[str]:
    rows = conn.execute(
        """
        SELECT concept_id
        FROM unit_concepts
        WHERE unit_id = ?
        ORDER BY sequence ASC, concept_id ASC
        """,
        (unit_id,),
    ).fetchall()
    return [str(r[0]) for r in rows]


def _load_primary_sense_map(conn: sqlite3.Connection, word_ids: List[str]) -> Dict[str, str]:
    if not word_ids:
        return {}
    placeholders = ",".join("?" for _ in word_ids)
    rows = conn.execute(
        f"""
        SELECT concept_id, sense_id
        FROM concept_senses
        WHERE is_primary = 1 AND concept_id IN ({placeholders})
        """,
        tuple(word_ids),
    ).fetchall()
    out = {str(r[0]): str(r[1]) for r in rows}
    for wid in word_ids:
        out.setdefault(wid, f"{wid}::s01")
    return out


def _load_word_text_map(conn: sqlite3.Connection, word_ids: List[str]) -> Dict[str, Dict[str, str]]:
    if not word_ids:
        return {}
    placeholders = ",".join("?" for _ in word_ids)
    rows = conn.execute(
        f"""
        SELECT id, text, COALESCE(pinyin,''), COALESCE(meaning,'')
        FROM concepts
        WHERE id IN ({placeholders})
        """,
        tuple(word_ids),
    ).fetchall()
    return {
        str(r[0]): {"text": str(r[1]), "pinyin": str(r[2]), "meaning": str(r[3])}
        for r in rows
    }


def _load_sentence_counts(conn: sqlite3.Connection, word_ids: List[str]) -> Dict[str, int]:
    if not word_ids:
        return {}
    placeholders = ",".join("?" for _ in word_ids)
    rows = conn.execute(
        f"""
        SELECT ws.word_id, COUNT(DISTINCT ws.sentence_id) AS c
        FROM word_sentences ws
        JOIN sentences s ON s.id = ws.sentence_id
        WHERE ws.word_id IN ({placeholders})
          AND TRIM(COALESCE(s.text,'')) != ''
        GROUP BY ws.word_id
        """,
        tuple(word_ids),
    ).fetchall()
    return {str(r[0]): int(r[1] or 0) for r in rows}


def _load_exercise_coverage(
    conn: sqlite3.Connection, word_ids: List[str]
) -> Dict[str, Dict[str, Any]]:
    if not word_ids:
        return {}
    placeholders = ",".join("?" for _ in word_ids)
    rows = conn.execute(
        f"""
        SELECT word_id, exercise_type
        FROM word_exercises
        WHERE word_id IN ({placeholders})
        ORDER BY word_id ASC, exercise_type ASC
        """,
        tuple(word_ids),
    ).fetchall()
    out: Dict[str, Dict[str, Any]] = {}
    for row in rows:
        wid = str(row[0])
        ex_type = str(row[1])
        bucket = out.setdefault(wid, {"types": []})
        if ex_type not in bucket["types"]:
            bucket["types"].append(ex_type)
    for wid in word_ids:
        bucket = out.setdefault(wid, {"types": []})
        bucket["type_count"] = len(bucket["types"])
    return out


def _circle_targets(template: Dict[str, Any]) -> Dict[str, Dict[str, Any]]:
    circles = template.get("circle_sequence") or []
    out: Dict[str, Dict[str, Any]] = {}
    for c in circles:
        cid = str(c.get("circle_id") or "")
        if not cid:
            continue
        out[cid] = c
    return out


def _pick_new_words(word_ids: List[str], n: int, offset: int) -> List[str]:
    return word_ids[offset : offset + n]


def main() -> int:
    parser = argparse.ArgumentParser(description="Build HSK1 circle generation plan")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--template", default="docs/specs/hsk1_circle_template_v1.json")
    parser.add_argument("--report-dir", default="docs/reports")
    parser.add_argument("--out", default="")
    args = parser.parse_args()

    root = _repo_root()
    db_path = root / args.db
    template_path = root / args.template
    report_dir = root / args.report_dir
    report_dir.mkdir(parents=True, exist_ok=True)

    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1
    if not template_path.exists():
        print(f"Template not found: {template_path}")
        return 1

    template = _read_json(template_path)
    circles = _circle_targets(template)
    if len(circles) != 7:
        print(f"Expected 7 circles in template, got {len(circles)}")
        return 1

    min_sentences = int(template.get("content_quota_per_sense", {}).get("min_sentences_total", 5))
    min_ex_types = int(template.get("content_quota_per_sense", {}).get("min_exercise_types_total", 3))

    conn = sqlite3.connect(str(db_path), timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout = 30000")

    try:
        units = _load_units(conn)
        if len(units) != 32:
            print(f"Expected 32 UNIT_HSK1 units, got {len(units)}")
            return 1

        all_word_ids: List[str] = []
        for unit in units:
            all_word_ids.extend(_load_unit_words(conn, unit["unit_id"]))
        all_word_ids = sorted(set(all_word_ids))

        sense_map = _load_primary_sense_map(conn, all_word_ids)
        text_map = _load_word_text_map(conn, all_word_ids)
        sentence_counts = _load_sentence_counts(conn, all_word_ids)
        exercise_cov = _load_exercise_coverage(conn, all_word_ids)

        plan_units: List[Dict[str, Any]] = []
        todo_rows: List[Dict[str, Any]] = []

        for unit in units:
            unit_id = unit["unit_id"]
            word_ids = _load_unit_words(conn, unit_id)
            new_a_n = int(circles["C1"].get("new_senses_target", 4))
            new_b_n = int(circles["C4"].get("new_senses_target", 4))
            new_a_words = _pick_new_words(word_ids, new_a_n, 0)
            new_b_words = _pick_new_words(word_ids, new_b_n, new_a_n)

            all_senses = [sense_map[w] for w in word_ids]
            new_a_senses = [sense_map[w] for w in new_a_words]
            new_b_senses = [sense_map[w] for w in new_b_words]

            circles_plan: List[Dict[str, Any]] = []
            for cid in ["C1", "C2", "C3", "C4", "C5", "C6", "C7"]:
                c = circles[cid]
                row = {
                    "circle_id": cid,
                    "title": c.get("title"),
                    "duration_target_sec": int(c.get("duration_seconds_target", 240)),
                    "exercise_mix": c.get("exercise_mix", {}),
                    "pass_rules": c.get("pass_rules", {}),
                    "retry_mode": (c.get("on_fail") or {}).get("retry_mode"),
                }
                if cid in {"C1", "C2", "C3"}:
                    row["focus_sense_ids"] = new_a_senses
                elif cid in {"C4", "C5"}:
                    row["focus_sense_ids"] = new_b_senses
                else:
                    row["focus_sense_ids"] = all_senses
                circles_plan.append(row)

            words_snapshot: List[Dict[str, Any]] = []
            for wid in word_ids:
                text_info = text_map.get(wid, {})
                ex_info = exercise_cov.get(wid, {"type_count": 0, "types": []})
                sent_count = int(sentence_counts.get(wid, 0))
                needed_sentences = max(0, min_sentences - sent_count)
                needed_ex_types = max(0, min_ex_types - int(ex_info.get("type_count", 0)))
                snapshot = {
                    "word_id": wid,
                    "sense_id": sense_map[wid],
                    "text": text_info.get("text", ""),
                    "pinyin": text_info.get("pinyin", ""),
                    "meaning": text_info.get("meaning", ""),
                    "sentence_count_proxy": sent_count,
                    "exercise_type_count": int(ex_info.get("type_count", 0)),
                    "exercise_types": list(ex_info.get("types", [])),
                    "needs_sentences": needed_sentences,
                    "needs_exercise_types": needed_ex_types,
                }
                words_snapshot.append(snapshot)
                if needed_sentences > 0 or needed_ex_types > 0:
                    todo_rows.append(
                        {
                            "unit_id": unit_id,
                            "word_id": wid,
                            "sense_id": sense_map[wid],
                            "text": text_info.get("text", ""),
                            "needs_sentences": needed_sentences,
                            "needs_exercise_types": needed_ex_types,
                        }
                    )

            plan_units.append(
                {
                    "unit_id": unit_id,
                    "unit_number": unit["unit_number"],
                    "title": unit["title"],
                    "word_ids": word_ids,
                    "circle_plan": circles_plan,
                    "words_snapshot": words_snapshot,
                }
            )

        payload = {
            "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
            "template_id": template.get("id"),
            "template_version": template.get("version"),
            "db": str(db_path),
            "units_total": len(plan_units),
            "words_total": len(all_word_ids),
            "min_sentences_total": min_sentences,
            "min_exercise_types_total": min_ex_types,
            "todo_count": len(todo_rows),
            "todo": todo_rows,
            "units": plan_units,
        }

        if args.out:
            out_path = root / args.out
        else:
            out_path = report_dir / f"hsk1_circle_generation_plan_{dt.date.today().isoformat()}.json"
        out_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        print(
            json.dumps(
                {
                    "ok": True,
                    "units_total": len(plan_units),
                    "words_total": len(all_word_ids),
                    "todo_count": len(todo_rows),
                    "out": str(out_path),
                }
            )
        )
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
