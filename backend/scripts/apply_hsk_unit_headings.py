#!/usr/bin/env python3
"""Apply themed headings/descriptions to UNIT_HSK* units.

This script upgrades generic unit names (e.g. "HSK3 Core Unit 014")
to learner-facing thematic headings suitable for Path UI.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sqlite3
from pathlib import Path


THEME_BANKS: dict[str, dict[str, object]] = {
    "HSK1": {
        "section_title": "Survival Foundations",
        "focus": "daily essentials",
        "themes": [
            "Greetings & First Contact",
            "Self-Introduction",
            "Family & Friends",
            "Numbers, Time & Date",
            "Food & Ordering",
            "Shopping & Payment",
            "Home & Routine",
            "City Directions",
            "Transport Basics",
            "Health & Help",
            "Daily Actions",
            "Simple Social Chat",
        ],
    },
    "HSK2": {
        "section_title": "Everyday Communication",
        "focus": "routine conversations",
        "themes": [
            "Appointments & Plans",
            "Travel & Tickets",
            "School & Study",
            "Workplace Basics",
            "Weather & Plans",
            "Restaurant Situations",
            "Shopping Problems",
            "Neighborhood Life",
            "Online Services",
            "Polite Requests",
            "Phone & Messaging",
            "Weekend Activities",
        ],
    },
    "HSK3": {
        "section_title": "Social Navigation",
        "focus": "functional interaction",
        "themes": [
            "Clarification & Follow-up",
            "Past Events & Stories",
            "Future Plans & Intention",
            "Problem Reporting",
            "Work & Collaboration",
            "Campus & Learning Tasks",
            "Service Encounters",
            "Travel Incidents",
            "Health Situations",
            "Invitations & Activities",
            "Opinions & Preferences",
            "Public Services",
        ],
    },
    "HSK4": {
        "section_title": "Complex Contexts",
        "focus": "precision and nuance",
        "themes": [
            "Explaining Reasons",
            "Comparing Options",
            "Negotiation & Requests",
            "Conflict & Resolution",
            "Feedback & Correction",
            "Rules & Procedures",
            "Studying Abroad",
            "Media & Discussion",
            "Community Issues",
            "Culture & Etiquette",
            "Formal vs Casual",
            "Decision Trade-offs",
        ],
    },
    "HSK5": {
        "section_title": "Professional Fluency",
        "focus": "advanced practical communication",
        "themes": [
            "Meetings & Coordination",
            "Project Updates",
            "Stakeholder Communication",
            "Problem Diagnosis",
            "Risk & Safety",
            "Customer Communication",
            "Policy & Regulation",
            "Learning Strategy",
            "Media Interpretation",
            "Cross-cultural Scenarios",
            "Presentation Skills",
            "Evidence & Argument",
        ],
    },
    "HSK6": {
        "section_title": "Advanced Expression",
        "focus": "abstraction and rhetoric",
        "themes": [
            "Abstract Emotions",
            "Narrative Framing",
            "Argumentation & Rebuttal",
            "Academic Discussion",
            "Business Strategy",
            "Policy Debate",
            "Social Commentary",
            "Leadership Language",
            "Negotiation Tactics",
            "Nuance & Pragmatics",
            "Formal Critique",
            "High-register Writing",
        ],
    },
    "HSK7": {
        "section_title": "Expert Band (7-9)",
        "focus": "specialized and high-register mastery",
        "themes": [
            "Public Affairs",
            "Economics & Markets",
            "Technology & Innovation",
            "Law & Governance",
            "Education & Research",
            "Culture & Society",
            "Media & Narrative",
            "Global Affairs",
            "Professional Practice",
            "Policy & Ethics",
        ],
    },
}


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply thematic unit headings")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--report-dir", default="docs/reports")
    args = parser.parse_args()

    repo_root = _repo_root()
    db_path = repo_root / args.db
    report_dir = repo_root / args.report_dir
    report_dir.mkdir(parents=True, exist_ok=True)
    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1

    conn = sqlite3.connect(str(db_path), timeout=20)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout = 20000")
    try:
        rows = conn.execute(
            """
            SELECT id, level, unit_number
            FROM units
            WHERE id LIKE 'UNIT_HSK%_%'
            ORDER BY level ASC, unit_number ASC
            """
        ).fetchall()

        by_level: dict[str, list[sqlite3.Row]] = {}
        for row in rows:
            by_level.setdefault(str(row["level"]), []).append(row)

        updates: list[tuple[str, str, str, str]] = []
        summary: dict[str, dict[str, int]] = {}
        samples: list[dict[str, str]] = []

        for level, level_rows in by_level.items():
            config = THEME_BANKS.get(level)
            if not config:
                continue
            themes = list(config["themes"])  # type: ignore[index]
            section_title = str(config["section_title"])
            focus = str(config["focus"])
            summary[level] = {"units": len(level_rows), "themes": len(themes)}

            for idx, row in enumerate(level_rows):
                theme = themes[idx % len(themes)]
                cycle = idx // len(themes) + 1
                title = f"{theme} • Part {cycle}"
                description = (
                    f"{section_title} ({level}) • Focus: {focus}. "
                    f"Theme track: {theme}."
                )
                objectives = json.dumps(
                    [
                        f"Build durable vocabulary for {theme.lower()} contexts.",
                        "Practice listening, reading, and production in mixed patterns.",
                        "Stabilize weak words with adaptive review before checkpoint.",
                    ],
                    ensure_ascii=False,
                )
                updates.append((title, description, objectives, str(row["id"])))
                if len(samples) < 20:
                    samples.append(
                        {
                            "id": str(row["id"]),
                            "level": level,
                            "title": title,
                        }
                    )

        report = {
            "date": dt.date.today().isoformat(),
            "db": str(args.db),
            "apply": bool(args.apply),
            "levels": summary,
            "updates_planned": len(updates),
            "samples": samples,
        }

        if args.apply and updates:
            with conn:
                conn.executemany(
                    """
                    UPDATE units
                    SET title = ?,
                        description = ?,
                        learning_objectives = ?
                    WHERE id = ?
                    """,
                    updates,
                )
            report["updates_applied"] = len(updates)

        out = report_dir / f"hsk_unit_headings_{dt.date.today().isoformat()}.json"
        out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(
            json.dumps(
                {
                    "apply": bool(args.apply),
                    "updates_planned": len(updates),
                    "updates_applied": int(report.get("updates_applied", 0)),
                },
                ensure_ascii=False,
            )
        )
        print(f"Report: {out}")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())

