#!/usr/bin/env python3
"""Validate HSK1 data against circle template quotas.

This is a release gate validator:
- Fails if any UNIT_HSK1 word/sense proxy misses sentence quota.
- Fails if any UNIT_HSK1 word/sense proxy misses exercise-type quota.
- Fails if unit sizes are out of configured bounds.
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


def _resolve_path(root: Path, raw: str) -> Path:
    p = Path(raw)
    return p if p.is_absolute() else root / p


def _apply_contract_defaults(args: argparse.Namespace, parser: argparse.ArgumentParser, contract: Dict[str, Any]) -> None:
    sources = contract.get("sources", {}) if isinstance(contract, dict) else {}
    outputs = contract.get("outputs", {}) if isinstance(contract, dict) else {}
    runtime = contract.get("runtime", {}) if isinstance(contract, dict) else {}

    if args.template == parser.get_default("template") and sources.get("circle_template"):
        args.template = str(sources["circle_template"])
    if args.db == parser.get_default("db") and runtime.get("default_db"):
        args.db = str(runtime["default_db"])
    if args.report_dir == parser.get_default("report_dir") and outputs.get("build_report_dir"):
        args.report_dir = str(outputs["build_report_dir"])


def _load_units(conn: sqlite3.Connection) -> List[Dict[str, Any]]:
    rows = conn.execute(
        """
        SELECT id, unit_number, title
        FROM units
        WHERE id LIKE 'UNIT_HSK1_%'
        ORDER BY unit_number ASC
        """
    ).fetchall()
    return [{"unit_id": str(r[0]), "unit_number": int(r[1]), "title": str(r[2])} for r in rows]


def _unit_word_ids(conn: sqlite3.Connection, unit_id: str) -> List[str]:
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


def _sentence_counts(conn: sqlite3.Connection, word_ids: List[str]) -> Dict[str, int]:
    if not word_ids:
        return {}
    placeholders = ",".join("?" for _ in word_ids)
    rows = conn.execute(
        f"""
        SELECT ws.word_id, COUNT(DISTINCT ws.sentence_id)
        FROM word_sentences ws
        JOIN sentences s ON s.id = ws.sentence_id
        WHERE ws.word_id IN ({placeholders})
          AND TRIM(COALESCE(s.text,'')) != ''
        GROUP BY ws.word_id
        """,
        tuple(word_ids),
    ).fetchall()
    return {str(r[0]): int(r[1] or 0) for r in rows}


def _exercise_types(conn: sqlite3.Connection, word_ids: List[str]) -> Dict[str, List[str]]:
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
    out: Dict[str, List[str]] = {}
    for r in rows:
        wid = str(r[0])
        ex = str(r[1])
        bucket = out.setdefault(wid, [])
        if ex not in bucket:
            bucket.append(ex)
    for wid in word_ids:
        out.setdefault(wid, [])
    return out


def _primary_sense_map(conn: sqlite3.Connection, word_ids: List[str]) -> Dict[str, str]:
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


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate HSK1 circle template quotas")
    parser.add_argument("--contract", default="", help="Canonical contract JSON (optional)")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--template", default="docs/specs/hsk1_circle_template_v1.json")
    parser.add_argument("--report-dir", default="docs/reports")
    parser.add_argument("--max-misses-preview", type=int, default=50)
    args = parser.parse_args()

    root = _repo_root()
    contract: Dict[str, Any] = {}
    contract_path = _resolve_path(root, args.contract) if str(args.contract).strip() else None
    if contract_path is not None:
        if not contract_path.exists():
            print(json.dumps({"ok": False, "error": f"Contract not found: {contract_path}"}))
            return 1
        contract = _read_json(contract_path)
        if str(contract.get("standard", "")).strip() not in {"", "HSK3.0"}:
            print(json.dumps({"ok": False, "error": "contract standard must be HSK3.0"}))
            return 1
        if str(contract.get("level", "")).strip() not in {"", "HSK1"}:
            print(json.dumps({"ok": False, "error": "contract level must be HSK1"}))
            return 1
        _apply_contract_defaults(args, parser, contract)

    db_path = _resolve_path(root, args.db)
    template_path = _resolve_path(root, args.template)
    report_dir = _resolve_path(root, args.report_dir)
    report_dir.mkdir(parents=True, exist_ok=True)

    if not db_path.exists():
        print(json.dumps({"ok": False, "error": f"DB not found: {db_path}"}))
        return 1
    if not template_path.exists():
        print(json.dumps({"ok": False, "error": f"Template not found: {template_path}"}))
        return 1

    template = _read_json(template_path)
    units_target = int(template.get("scope", {}).get("units_total_target", 32))
    bounds = template.get("scope", {}).get("unit_words_target", {}) or {}
    unit_min = int(bounds.get("min", 15))
    unit_max = int(bounds.get("max", 16))
    min_sentences = int(template.get("content_quota_per_sense", {}).get("min_sentences_total", 5))
    min_ex_types = int(template.get("content_quota_per_sense", {}).get("min_exercise_types_total", 3))

    conn = sqlite3.connect(str(db_path), timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout = 30000")

    try:
        units = _load_units(conn)
        all_word_ids: List[str] = []
        unit_sizes: Dict[str, int] = {}
        for unit in units:
            word_ids = _unit_word_ids(conn, unit["unit_id"])
            unit_sizes[unit["unit_id"]] = len(word_ids)
            all_word_ids.extend(word_ids)
        all_word_ids = sorted(set(all_word_ids))

        sentence_counts = _sentence_counts(conn, all_word_ids)
        ex_types = _exercise_types(conn, all_word_ids)
        sense_map = _primary_sense_map(conn, all_word_ids)

        unit_size_violations: List[Dict[str, Any]] = []
        missing_primary_sense: List[Dict[str, Any]] = []
        sentence_quota_misses: List[Dict[str, Any]] = []
        exercise_quota_misses: List[Dict[str, Any]] = []

        for unit in units:
            unit_id = unit["unit_id"]
            word_ids = _unit_word_ids(conn, unit_id)
            size = len(word_ids)
            if size < unit_min or size > unit_max:
                unit_size_violations.append(
                    {
                        "unit_id": unit_id,
                        "unit_number": unit["unit_number"],
                        "title": unit["title"],
                        "size": size,
                        "expected_min": unit_min,
                        "expected_max": unit_max,
                    }
                )

            for wid in word_ids:
                sid = sense_map.get(wid)
                if not sid or not sid.startswith(f"{wid}::"):
                    missing_primary_sense.append({"unit_id": unit_id, "word_id": wid, "sense_id": sid})
                    continue

                sent_count = int(sentence_counts.get(wid, 0))
                if sent_count < min_sentences:
                    sentence_quota_misses.append(
                        {
                            "unit_id": unit_id,
                            "word_id": wid,
                            "sense_id": sid,
                            "sentence_count_proxy": sent_count,
                            "required": min_sentences,
                        }
                    )

                types = ex_types.get(wid, [])
                if len(types) < min_ex_types:
                    exercise_quota_misses.append(
                        {
                            "unit_id": unit_id,
                            "word_id": wid,
                            "sense_id": sid,
                            "exercise_types": types,
                            "exercise_type_count": len(types),
                            "required": min_ex_types,
                        }
                    )

        checks = {
            "units_found": len(units),
            "units_target": units_target,
            "unit_size_bounds": {"min": unit_min, "max": unit_max},
            "words_in_hsk1_units": len(all_word_ids),
            "missing_primary_sense": len(missing_primary_sense),
            "unit_size_violations": len(unit_size_violations),
            "sentence_quota_misses": len(sentence_quota_misses),
            "exercise_quota_misses": len(exercise_quota_misses),
            "min_sentences_total_required": min_sentences,
            "min_exercise_types_total_required": min_ex_types,
            "note": "sense coverage uses primary-sense proxy from word-level sentence/exercise links",
        }

        fail = (
            checks["units_found"] != units_target
            or checks["missing_primary_sense"] > 0
            or checks["unit_size_violations"] > 0
            or checks["sentence_quota_misses"] > 0
            or checks["exercise_quota_misses"] > 0
        )

        stamp = dt.date.today().isoformat()
        report_path = report_dir / f"validate_hsk1_circle_template_{stamp}.json"
        payload = {
            "ok": not fail,
            "contract_id": contract.get("id") if contract else "",
            "contract_version": contract.get("version") if contract else None,
            "contract_file": str(contract_path) if contract_path is not None else "",
            "template_id": template.get("id"),
            "template_version": template.get("version"),
            "db": str(db_path),
            "checks": checks,
            "preview": {
                "unit_size_violations": unit_size_violations[: args.max_misses_preview],
                "missing_primary_sense": missing_primary_sense[: args.max_misses_preview],
                "sentence_quota_misses": sentence_quota_misses[: args.max_misses_preview],
                "exercise_quota_misses": exercise_quota_misses[: args.max_misses_preview],
            },
        }
        report_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps({"ok": payload["ok"], "checks": checks, "report": str(report_path)}))
        return 1 if fail else 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
