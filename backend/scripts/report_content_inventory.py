#!/usr/bin/env python3
"""Generate a read-only content inventory report for HSK pilot planning."""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import subprocess
from dataclasses import asdict, dataclass
from datetime import date
from pathlib import Path
from typing import Dict, List, Optional, Tuple


@dataclass
class ToneAudit:
    total: int
    missing_tone: int
    mismatches: int
    mismatch_rate: float
    raw_output: str


@dataclass
class SentenceCoverage:
    total_concepts: int
    covered_concepts: int
    raw_output: str


@dataclass
class PassageCoverage:
    units: int
    passages_found: int
    missing_passages: int
    raw_output: str


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _connect(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    return conn


def _run_script(args: List[str]) -> str:
    result = subprocess.run(args, capture_output=True, text=True, check=False)
    output = result.stdout.strip()
    if result.stderr:
        output = (output + "\n\n[stderr]\n" + result.stderr.strip()).strip()
    return output


def _parse_tone_audit(raw: str) -> ToneAudit:
    total = _extract_int(raw, r"Total tone_select rows: (\d+)")
    missing = _extract_int(raw, r"Missing tone in pinyin: (\d+)")
    mismatches = _extract_int(raw, r"Mismatches .*?: (\d+)")
    mismatch_rate = _extract_float(raw, r"\((\d+\.?\d*)%\)")
    return ToneAudit(
        total=total,
        missing_tone=missing,
        mismatches=mismatches,
        mismatch_rate=mismatch_rate,
        raw_output=raw,
    )


def _parse_sentence_coverage(raw: str) -> SentenceCoverage:
    total = _extract_int(raw, r"Concepts \(unit_concepts distinct\): (\d+)")
    covered = _extract_int(raw, r"Concepts with usage exercises .*?: (\d+)")
    return SentenceCoverage(total_concepts=total, covered_concepts=covered, raw_output=raw)


def _parse_passage_coverage(raw: str) -> PassageCoverage:
    units = _extract_int(raw, r"Units in manifest: (\d+)")
    found = _extract_int(raw, r"Passages found: (\d+)")
    missing = _extract_int(raw, r"Missing passages: (\d+)")
    return PassageCoverage(units=units, passages_found=found, missing_passages=missing, raw_output=raw)


def _extract_int(text: str, pattern: str) -> int:
    match = re.search(pattern, text)
    return int(match.group(1)) if match else 0


def _extract_float(text: str, pattern: str) -> float:
    match = re.search(pattern, text)
    return float(match.group(1)) if match else 0.0


def _percent(part: int, total: int) -> float:
    return (part / total) * 100 if total else 0.0


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate content inventory report")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--out-dir", default="docs/reports")
    args = parser.parse_args()

    repo_root = _repo_root()
    db_path = repo_root / args.db
    out_dir = repo_root / args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1

    conn = _connect(db_path)
    try:
        schema_version = conn.execute(
            "SELECT value FROM schema_info WHERE key = 'version'"
        ).fetchone()
        schema_version = schema_version[0] if schema_version else "UNKNOWN"

        concepts_count = conn.execute("SELECT COUNT(*) FROM concepts").fetchone()[0]
        unit_concepts_distinct = conn.execute(
            "SELECT COUNT(DISTINCT concept_id) FROM unit_concepts"
        ).fetchone()[0]
        unit_concepts_total = conn.execute("SELECT COUNT(*) FROM unit_concepts").fetchone()[0]
        word_exercises_total = conn.execute("SELECT COUNT(*) FROM word_exercises").fetchone()[0]

        exercise_types = conn.execute(
            """
            SELECT exercise_type,
                   COUNT(*) as total,
                   COUNT(DISTINCT word_id) as concepts
            FROM word_exercises
            GROUP BY exercise_type
            ORDER BY total DESC
            """
        ).fetchall()

        unit_ids = [
            row[0]
            for row in conn.execute(
                "SELECT DISTINCT unit_id FROM unit_concepts ORDER BY CAST(unit_id AS INTEGER)"
            ).fetchall()
        ]

        unit_coverage = []
        for unit_id in unit_ids:
            concepts = conn.execute(
                "SELECT COUNT(DISTINCT concept_id) FROM unit_concepts WHERE unit_id = ?",
                (unit_id,),
            ).fetchone()[0]
            exercises = conn.execute(
                """
                SELECT COUNT(*)
                FROM word_exercises
                WHERE word_id IN (
                    SELECT concept_id FROM unit_concepts WHERE unit_id = ?
                )
                """,
                (unit_id,),
            ).fetchone()[0]

            worst = conn.execute(
                """
                SELECT uc.concept_id, COUNT(we.id) as variants
                FROM unit_concepts uc
                LEFT JOIN word_exercises we ON we.word_id = uc.concept_id
                WHERE uc.unit_id = ?
                GROUP BY uc.concept_id
                ORDER BY variants ASC, uc.concept_id ASC
                LIMIT 10
                """,
                (unit_id,),
            ).fetchall()

            unit_coverage.append(
                {
                    "unit_id": unit_id,
                    "concepts": concepts,
                    "exercises": exercises,
                    "worst_covered": [
                        {"concept_id": row[0], "variants": int(row[1])}
                        for row in worst
                    ],
                }
            )

        variant_counts = conn.execute(
            """
            SELECT uc.concept_id, COUNT(we.id) as variants
            FROM unit_concepts uc
            LEFT JOIN word_exercises we ON we.word_id = uc.concept_id
            GROUP BY uc.concept_id
            """
        ).fetchall()
    finally:
        conn.close()

    variants = [int(row[1]) for row in variant_counts]
    total_concepts = len(variants)
    v2 = sum(1 for v in variants if v >= 2)
    v3 = sum(1 for v in variants if v >= 3)
    v5 = sum(1 for v in variants if v >= 5)

    tone_raw = _run_script(["python3", "backend/scripts/audit_tone_select.py"])
    tone = _parse_tone_audit(tone_raw)

    sentence_raw = _run_script(["python3", "backend/scripts/report_sentence_coverage.py"])
    sentence = _parse_sentence_coverage(sentence_raw)

    passage_raw = _run_script(["python3", "backend/scripts/report_passage_coverage.py"])
    passage = _parse_passage_coverage(passage_raw)

    readiness_score = None
    if total_concepts > 0 and sentence.total_concepts > 0 and passage.units > 0:
        v3_pct = _percent(v3, total_concepts)
        sentence_pct = _percent(sentence.covered_concepts, sentence.total_concepts)
        passage_pct = _percent(passage.passages_found, passage.units)
        tone_quality = max(0.0, 100.0 - tone.mismatch_rate)
        readiness_score = round(
            0.4 * v3_pct + 0.3 * sentence_pct + 0.2 * passage_pct + 0.1 * tone_quality,
            2,
        )

    report = {
        "date": date.today().isoformat(),
        "db": {
            "schema_version": schema_version,
            "concepts": concepts_count,
            "unit_concepts_distinct": unit_concepts_distinct,
            "unit_concepts_total": unit_concepts_total,
            "word_exercises_total": word_exercises_total,
        },
        "exercise_types": [
            {
                "exercise_type": row[0],
                "count": int(row[1]),
                "concept_coverage": int(row[2]),
            }
            for row in exercise_types
        ],
        "unit_coverage": unit_coverage,
        "variant_thresholds": {
            "total_concepts": total_concepts,
            "at_least_2": v2,
            "at_least_3": v3,
            "at_least_5": v5,
            "pct_at_least_2": round(_percent(v2, total_concepts), 2),
            "pct_at_least_3": round(_percent(v3, total_concepts), 2),
            "pct_at_least_5": round(_percent(v5, total_concepts), 2),
        },
        "tone_select": asdict(tone),
        "sentence_coverage": asdict(sentence),
        "passage_coverage": asdict(passage),
        "hsk_readiness_score": readiness_score,
        "hsk_readiness_formula": (
            "score = 0.4*(% concepts with >=3 variants) + "
            "0.3*(sentence coverage %) + 0.2*(passage coverage %) + "
            "0.1*(100 - tone mismatch %)"
        ),
    }

    date_str = report["date"]
    json_path = out_dir / f"content_inventory_{date_str}.json"
    md_path = out_dir / f"content_inventory_{date_str}.md"

    json_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

    md_lines = []
    md_lines.append(f"# Content Inventory ({date_str})")
    md_lines.append("")
    md_lines.append("## DB basics")
    md_lines.append(f"- schema_info.version: {schema_version}")
    md_lines.append(f"- concepts: {concepts_count}")
    md_lines.append(f"- unit_concepts distinct: {unit_concepts_distinct}")
    md_lines.append(f"- unit_concepts total: {unit_concepts_total}")
    md_lines.append(f"- word_exercises total: {word_exercises_total}")
    md_lines.append("")

    md_lines.append("## Exercise types present")
    md_lines.append("| exercise_type | total | distinct concepts |")
    md_lines.append("| --- | ---: | ---: |")
    for row in exercise_types:
        md_lines.append(f"| {row[0]} | {int(row[1])} | {int(row[2])} |")
    md_lines.append("")

    md_lines.append("## HSK unit coverage")
    for unit in unit_coverage:
        md_lines.append(
            f"- Unit {unit['unit_id']}: {unit['concepts']} concepts, {unit['exercises']} exercises"
        )
        worst = ", ".join(
            f"{w['concept_id']}({w['variants']})" for w in unit["worst_covered"]
        )
        md_lines.append(f"  - Worst covered concepts: {worst}")
    md_lines.append("")

    md_lines.append("## Variant coverage thresholds")
    md_lines.append(
        f"- >=2 variants: {v2}/{total_concepts} ({_percent(v2, total_concepts):.2f}%)"
    )
    md_lines.append(
        f"- >=3 variants: {v3}/{total_concepts} ({_percent(v3, total_concepts):.2f}%)"
    )
    md_lines.append(
        f"- >=5 variants: {v5}/{total_concepts} ({_percent(v5, total_concepts):.2f}%)"
    )
    md_lines.append("")

    md_lines.append("## Tone_select quality (audit)")
    md_lines.append("```")
    md_lines.append(tone_raw)
    md_lines.append("```")
    md_lines.append("")

    md_lines.append("## Sentence coverage")
    md_lines.append("```")
    md_lines.append(sentence_raw)
    md_lines.append("```")
    md_lines.append("")

    md_lines.append("## Passage coverage")
    md_lines.append("```")
    md_lines.append(passage_raw)
    md_lines.append("```")
    md_lines.append("")

    md_lines.append("## HSK readiness score")
    md_lines.append(f"Formula: {report['hsk_readiness_formula']}")
    md_lines.append(f"Score: {readiness_score if readiness_score is not None else 'UNKNOWN'}")

    md_path.write_text("\n".join(md_lines), encoding="utf-8")

    print(f"Wrote {md_path}")
    print(f"Wrote {json_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
