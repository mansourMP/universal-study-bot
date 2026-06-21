#!/usr/bin/env python3
"""Validate HSK meaning quality for primary sense + English anchor consistency.

Release-gate checks (per selected HSK level/core band):
- Each concept has exactly one primary sense row.
- Primary gloss is non-empty and sane (not JSON/code/non-language noise).
- English localization exists and matches the primary gloss (normalized).
- concepts.meaning matches the primary gloss (normalized).
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sqlite3
from pathlib import Path
from typing import Any, Dict, List, Tuple


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _normalize_text(value: str) -> str:
    value = (value or "").strip().lower()
    value = re.sub(r"\s+", " ", value)
    value = re.sub(r"[^\w\s'-]", "", value)
    return value.strip()


def _has_non_latin_script(value: str) -> bool:
    if not value:
        return False
    patterns = [
        r"[\u4e00-\u9fff]",   # CJK
        r"[\u3040-\u30ff]",   # Hiragana/Katakana
        r"[\u0400-\u04ff]",   # Cyrillic
        r"[\u0600-\u06ff]",   # Arabic
        r"[\u0590-\u05ff]",   # Hebrew
        r"[\u0900-\u097f]",   # Devanagari
    ]
    return any(re.search(p, value) for p in patterns)


def _looks_corrupted(value: str) -> bool:
    v = (value or "").strip()
    if not v:
        return True
    if len(v) > 80:
        return True
    lowered = v.lower()
    bad_markers = ["```", "{", "}", "translations", "json", "http://", "https://"]
    if any(m in lowered for m in bad_markers):
        return True
    if "\n" in v or "\r" in v or "\t" in v:
        return True
    return False


def _load_target_concepts(
    conn: sqlite3.Connection,
    standard: str,
    level: str,
    band: str,
) -> List[Tuple[str, str]]:
    rows = conn.execute(
        """
        SELECT c.id, c.meaning
        FROM concepts c
        JOIN concept_curriculum_map m ON m.concept_id = c.id
        WHERE m.standard = ? AND m.level = ? AND m.band = ?
        ORDER BY c.id
        """,
        (standard, level, band),
    ).fetchall()
    return [(str(r[0]), str(r[1] or "")) for r in rows]


def _load_primary_senses(conn: sqlite3.Connection, concept_ids: List[str]) -> Dict[str, List[str]]:
    if not concept_ids:
        return {}
    placeholders = ",".join("?" for _ in concept_ids)
    rows = conn.execute(
        f"""
        SELECT concept_id, gloss
        FROM concept_senses
        WHERE is_primary = 1
          AND concept_id IN ({placeholders})
        ORDER BY concept_id
        """,
        tuple(concept_ids),
    ).fetchall()
    out: Dict[str, List[str]] = {cid: [] for cid in concept_ids}
    for concept_id, gloss in rows:
        out[str(concept_id)].append(str(gloss or ""))
    return out


def _load_en_localizations(conn: sqlite3.Connection, concept_ids: List[str]) -> Dict[str, str]:
    if not concept_ids:
        return {}
    placeholders = ",".join("?" for _ in concept_ids)
    rows = conn.execute(
        f"""
        SELECT concept_id, meaning
        FROM concept_localizations
        WHERE language_code = 'en'
          AND concept_id IN ({placeholders})
        """,
        tuple(concept_ids),
    ).fetchall()
    out = {str(r[0]): str(r[1] or "") for r in rows}
    for cid in concept_ids:
        out.setdefault(cid, "")
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate HSK meaning quality")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--standard", default="HSK3.0")
    parser.add_argument("--level", default="HSK1")
    parser.add_argument("--band", default="core")
    parser.add_argument("--report-dir", default="docs/reports")
    parser.add_argument("--max-preview", type=int, default=50)
    args = parser.parse_args()

    root = _repo_root()
    db_path = root / args.db
    report_dir = root / args.report_dir
    report_dir.mkdir(parents=True, exist_ok=True)

    if not db_path.exists():
        print(json.dumps({"ok": False, "error": f"DB not found: {db_path}"}))
        return 1

    conn = sqlite3.connect(str(db_path), timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout = 30000")
    try:
        standard = args.standard.upper()
        level = args.level.upper()
        band = args.band.lower()

        concepts = _load_target_concepts(conn, standard, level, band)
        concept_ids = [c[0] for c in concepts]
        concepts_meaning = {c[0]: c[1] for c in concepts}
        primary_map = _load_primary_senses(conn, concept_ids)
        en_map = _load_en_localizations(conn, concept_ids)

        missing_primary: List[Dict[str, Any]] = []
        duplicate_primary: List[Dict[str, Any]] = []
        empty_primary_gloss: List[Dict[str, Any]] = []
        suspicious_primary_gloss: List[Dict[str, Any]] = []
        non_latin_primary_gloss: List[Dict[str, Any]] = []
        missing_en: List[Dict[str, Any]] = []
        en_primary_mismatch: List[Dict[str, Any]] = []
        concept_primary_mismatch: List[Dict[str, Any]] = []

        for cid in concept_ids:
            primaries = primary_map.get(cid, [])
            concept_meaning = concepts_meaning.get(cid, "")
            en_meaning = en_map.get(cid, "")

            if len(primaries) == 0:
                missing_primary.append({"concept_id": cid})
                continue
            if len(primaries) > 1:
                duplicate_primary.append({"concept_id": cid, "primary_rows": primaries})
                continue

            primary = primaries[0].strip()
            if not primary:
                empty_primary_gloss.append({"concept_id": cid})
                continue

            if _looks_corrupted(primary):
                suspicious_primary_gloss.append({"concept_id": cid, "gloss": primary})
            if _has_non_latin_script(primary):
                non_latin_primary_gloss.append({"concept_id": cid, "gloss": primary})

            if not en_meaning.strip():
                missing_en.append({"concept_id": cid, "primary_gloss": primary})
            elif _normalize_text(en_meaning) != _normalize_text(primary):
                en_primary_mismatch.append(
                    {
                        "concept_id": cid,
                        "primary_gloss": primary,
                        "en_localization": en_meaning,
                    }
                )

            if _normalize_text(concept_meaning) != _normalize_text(primary):
                concept_primary_mismatch.append(
                    {
                        "concept_id": cid,
                        "concept_meaning": concept_meaning,
                        "primary_gloss": primary,
                    }
                )

        checks = {
            "scope": {
                "standard": standard,
                "level": level,
                "band": band,
                "concepts": len(concept_ids),
            },
            "missing_primary": len(missing_primary),
            "duplicate_primary": len(duplicate_primary),
            "empty_primary_gloss": len(empty_primary_gloss),
            "suspicious_primary_gloss": len(suspicious_primary_gloss),
            "non_latin_primary_gloss": len(non_latin_primary_gloss),
            "missing_en_localization": len(missing_en),
            "en_primary_mismatch": len(en_primary_mismatch),
            "concept_primary_mismatch": len(concept_primary_mismatch),
        }

        fail = any(
            [
                checks["missing_primary"] > 0,
                checks["duplicate_primary"] > 0,
                checks["empty_primary_gloss"] > 0,
                checks["suspicious_primary_gloss"] > 0,
                checks["non_latin_primary_gloss"] > 0,
                checks["missing_en_localization"] > 0,
                checks["en_primary_mismatch"] > 0,
                checks["concept_primary_mismatch"] > 0,
            ]
        )

        stamp = dt.date.today().isoformat()
        report_path = report_dir / f"validate_hsk_meaning_quality_{level.lower()}_{stamp}.json"
        payload = {
            "ok": not fail,
            "db": str(db_path),
            "checks": checks,
            "preview": {
                "missing_primary": missing_primary[: args.max_preview],
                "duplicate_primary": duplicate_primary[: args.max_preview],
                "empty_primary_gloss": empty_primary_gloss[: args.max_preview],
                "suspicious_primary_gloss": suspicious_primary_gloss[: args.max_preview],
                "non_latin_primary_gloss": non_latin_primary_gloss[: args.max_preview],
                "missing_en_localization": missing_en[: args.max_preview],
                "en_primary_mismatch": en_primary_mismatch[: args.max_preview],
                "concept_primary_mismatch": concept_primary_mismatch[: args.max_preview],
            },
        }
        report_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps({"ok": payload["ok"], "checks": checks, "report": str(report_path)}))
        return 1 if fail else 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
