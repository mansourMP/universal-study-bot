#!/usr/bin/env python3
"""Remap HSK1 UNIT_HSK1_* unit_concepts using a season blueprint.

Pipeline:
1) Load HSK1 core words from concept_curriculum_map + concepts.
2) Assign anchors from blueprint (hanzi exact match).
3) Assign by keyword scoring on English meaning.
4) Fill remaining words to balanced capacities.
5) Optionally apply mapping + unit titles/descriptions to DB.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import re
import sqlite3
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Tuple


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _norm(s: str | None) -> str:
    return re.sub(r"\s+", " ", str(s or "").strip())


def _norm_key(s: str | None) -> str:
    return _norm(s).lower()


def _load_blueprint(path: Path) -> List[Dict]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    seasons = raw.get("seasons") or []
    units: List[Dict] = []
    for season in seasons:
        season_id = str(season.get("season_id") or "")
        season_title = str(season.get("title") or "")
        for unit in season.get("units") or []:
            units.append(
                {
                    "unit_number": int(unit["unit_number"]),
                    "title": str(unit["title"]),
                    "keywords": [str(k).strip().lower() for k in (unit.get("keywords") or []) if str(k).strip()],
                    "anchor_hanzi": [str(h).strip() for h in (unit.get("anchor_hanzi") or []) if str(h).strip()],
                    "season_id": season_id,
                    "season_title": season_title,
                }
            )
    units.sort(key=lambda u: int(u["unit_number"]))
    return units


def _load_hsk1_words(conn: sqlite3.Connection) -> List[Dict]:
    rows = conn.execute(
        """
        SELECT c.id, c.text, COALESCE(c.pinyin,'') AS pinyin, COALESCE(c.meaning,'') AS meaning
        FROM concept_curriculum_map m
        JOIN concepts c ON c.id = m.concept_id
        WHERE m.standard = 'HSK3.0' AND m.band = 'core' AND m.level = 'HSK1'
        ORDER BY c.id
        """
    ).fetchall()
    return [
        {
            "id": str(r[0]),
            "text": str(r[1]),
            "pinyin": str(r[2]),
            "meaning": str(r[3]),
        }
        for r in rows
    ]


def _unit_capacities(total_words: int, unit_count: int) -> Dict[int, int]:
    base = total_words // unit_count
    rem = total_words % unit_count
    out: Dict[int, int] = {}
    for i in range(1, unit_count + 1):
        out[i] = base + (1 if i <= rem else 0)
    return out


def _choose_by_keywords(word: Dict, units: List[Dict]) -> int | None:
    meaning = _norm_key(word.get("meaning", ""))
    if not meaning:
        return None

    best_unit = None
    best_score = 0
    for unit in units:
        score = 0
        for kw in unit["keywords"]:
            if kw and kw in meaning:
                score += 1
        if score > best_score:
            best_score = score
            best_unit = int(unit["unit_number"])
    return best_unit if best_score > 0 else None


def _balance_assignments(
    assignments: Dict[str, int],
    reasons: Dict[str, str],
    words_by_id: Dict[str, Dict],
    capacities: Dict[int, int],
) -> None:
    by_unit: Dict[int, List[str]] = defaultdict(list)
    for wid, uid in assignments.items():
        by_unit[uid].append(wid)

    under = [u for u, cap in capacities.items() if len(by_unit[u]) < cap]
    over = [u for u, cap in capacities.items() if len(by_unit[u]) > cap]
    under.sort()
    over.sort()

    # Move only non-anchor first.
    for src in over:
        while len(by_unit[src]) > capacities[src] and under:
            candidates = [wid for wid in by_unit[src] if reasons.get(wid) != "anchor"]
            if not candidates:
                break
            wid = sorted(candidates)[0]
            dst = under[0]
            by_unit[src].remove(wid)
            by_unit[dst].append(wid)
            assignments[wid] = dst
            reasons[wid] = f"{reasons.get(wid,'move')}->rebalance"
            if len(by_unit[dst]) >= capacities[dst]:
                under.pop(0)

    # Hard balancing if still over/under.
    under = [u for u, cap in capacities.items() if len(by_unit[u]) < cap]
    over = [u for u, cap in capacities.items() if len(by_unit[u]) > cap]
    under.sort()
    over.sort()
    for src in over:
        while len(by_unit[src]) > capacities[src] and under:
            wid = sorted(by_unit[src])[0]
            dst = under[0]
            by_unit[src].remove(wid)
            by_unit[dst].append(wid)
            assignments[wid] = dst
            reasons[wid] = f"{reasons.get(wid,'move')}->hard_rebalance"
            if len(by_unit[dst]) >= capacities[dst]:
                under.pop(0)


def main() -> int:
    parser = argparse.ArgumentParser(description="Remap HSK1 units from season blueprint")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--blueprint", default="docs/specs/hsk1_season_blueprint_v2.json")
    parser.add_argument("--report-dir", default="docs/reports")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    root = _repo_root()
    db_path = root / args.db
    bp_path = root / args.blueprint
    report_dir = root / args.report_dir
    report_dir.mkdir(parents=True, exist_ok=True)

    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1
    if not bp_path.exists():
        print(f"Blueprint not found: {bp_path}")
        return 1

    units = _load_blueprint(bp_path)
    if len(units) != 32:
        print(f"Expected 32 units in blueprint, got {len(units)}")
        return 1

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout = 20000")

    try:
        words = _load_hsk1_words(conn)
        words_by_id = {w["id"]: w for w in words}
        capacities = _unit_capacities(len(words), len(units))

        assignments: Dict[str, int] = {}
        reasons: Dict[str, str] = {}

        # 1) Anchor assignment.
        by_hanzi: Dict[str, List[str]] = defaultdict(list)
        for w in words:
            by_hanzi[w["text"]].append(w["id"])

        for unit in units:
            uid = int(unit["unit_number"])
            for hanzi in unit["anchor_hanzi"]:
                for wid in sorted(by_hanzi.get(hanzi, [])):
                    if wid not in assignments:
                        assignments[wid] = uid
                        reasons[wid] = "anchor"

        # 2) Keyword assignment.
        for w in words:
            wid = w["id"]
            if wid in assignments:
                continue
            chosen = _choose_by_keywords(w, units)
            if chosen is not None:
                assignments[wid] = chosen
                reasons[wid] = "keyword"

        # 3) Fill remaining to least-filled units.
        by_unit_counts = defaultdict(int)
        for uid in assignments.values():
            by_unit_counts[uid] += 1

        for w in words:
            wid = w["id"]
            if wid in assignments:
                continue
            # choose least filled with remaining capacity
            candidates = []
            for u in range(1, 33):
                remaining = capacities[u] - by_unit_counts[u]
                candidates.append((remaining, by_unit_counts[u], u))
            candidates.sort(key=lambda x: (-x[0], x[1], x[2]))
            uid = candidates[0][2]
            assignments[wid] = uid
            reasons[wid] = "fill"
            by_unit_counts[uid] += 1

        # 4) Rebalance to exact capacities.
        _balance_assignments(assignments, reasons, words_by_id, capacities)

        # Build rows.
        rows_out: List[Dict] = []
        words_by_unit: Dict[int, List[str]] = defaultdict(list)
        for wid, uid in assignments.items():
            words_by_unit[uid].append(wid)

        for uid in range(1, 33):
            words_by_unit[uid] = sorted(words_by_unit[uid])
            for seq, wid in enumerate(words_by_unit[uid], start=1):
                w = words_by_id[wid]
                rows_out.append(
                    {
                        "unit_number": uid,
                        "sequence": seq,
                        "word_id": wid,
                        "text": w["text"],
                        "pinyin": w["pinyin"],
                        "meaning": w["meaning"],
                        "reason": reasons.get(wid, ""),
                    }
                )

        stamp = dt.date.today().isoformat()
        csv_path = report_dir / f"hsk1_unit_remap_plan_{stamp}.csv"
        json_path = report_dir / f"hsk1_unit_remap_plan_{stamp}.json"

        with csv_path.open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(
                f,
                fieldnames=[
                    "unit_number",
                    "sequence",
                    "word_id",
                    "text",
                    "pinyin",
                    "meaning",
                    "reason",
                ],
            )
            writer.writeheader()
            writer.writerows(rows_out)

        unit_summaries = []
        for unit in units:
            uid = int(unit["unit_number"])
            unit_summaries.append(
                {
                    "unit_number": uid,
                    "title": unit["title"],
                    "season_id": unit["season_id"],
                    "season_title": unit["season_title"],
                    "capacity": capacities[uid],
                    "assigned": len(words_by_unit[uid]),
                }
            )

        summary = {
            "date": stamp,
            "db": args.db,
            "blueprint": args.blueprint,
            "apply": bool(args.apply),
            "words_total": len(words),
            "units_total": len(units),
            "unit_summaries": unit_summaries,
            "output_csv": str(csv_path),
        }
        json_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")

        if args.apply:
            with conn:
                # Replace HSK1 unit_concepts only.
                conn.execute("DELETE FROM unit_concepts WHERE unit_id LIKE 'UNIT_HSK1_%'")

                # Update unit titles/descriptions for HSK1.
                for unit in units:
                    uid_num = int(unit["unit_number"])
                    unit_id = f"UNIT_HSK1_{uid_num:03d}"
                    title = unit["title"]
                    desc = f"{unit['season_title']} • {title}."
                    objectives = json.dumps(
                        [
                            f"Master core vocabulary for {title.lower()} contexts.",
                            "Build listening, reading and speaking confidence.",
                            "Stabilize recall via adaptive spaced review.",
                        ],
                        ensure_ascii=False,
                    )
                    conn.execute(
                        """
                        UPDATE units
                        SET title = ?, description = ?, learning_objectives = ?
                        WHERE id = ?
                        """,
                        (title, desc, objectives, unit_id),
                    )

                # Insert new mapping.
                conn.executemany(
                    """
                    INSERT INTO unit_concepts (unit_id, concept_id, sequence)
                    VALUES (?, ?, ?)
                    """,
                    [
                        (f"UNIT_HSK1_{int(r['unit_number']):03d}", r["word_id"], int(r["sequence"]))
                        for r in rows_out
                    ],
                )

            summary["applied_rows"] = len(rows_out)
            json_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")

        print(json.dumps({"ok": True, "apply": bool(args.apply), "words_total": len(words), "rows": len(rows_out)}))
        print(f"Plan CSV: {csv_path}")
        print(f"Plan JSON: {json_path}")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())

