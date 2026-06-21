#!/usr/bin/env python3
"""Prepare apply plan for expansion draft.

Outputs:
1) Manifest preview JSON with appended units (does not overwrite source manifest)
2) SQL file with INSERTs for unit_concepts (numeric unit ids)
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _infer_target_realm(manifest: dict) -> str:
    realms = manifest.get("realms", {})
    if not isinstance(realms, dict) or not realms:
        return "5"
    # default to highest existing realm id
    return sorted(realms.keys(), key=lambda x: int(x))[-1]


def main() -> int:
    parser = argparse.ArgumentParser(description="Prepare expansion apply plan")
    parser.add_argument("--manifest", default="backend/content/paths/zh_standard.json")
    parser.add_argument("--draft", default="docs/reports/expansion_units_draft_2026-02-09.json")
    parser.add_argument("--target-realm", default="")
    parser.add_argument("--out-json", default="")
    parser.add_argument("--out-sql", default="")
    args = parser.parse_args()

    repo_root = _repo_root()
    manifest_path = repo_root / args.manifest
    draft_path = repo_root / args.draft
    if not manifest_path.exists():
        print(f"Manifest not found: {manifest_path}")
        return 1
    if not draft_path.exists():
        print(f"Draft not found: {draft_path}")
        return 1

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    draft = json.loads(draft_path.read_text(encoding="utf-8"))
    units = draft.get("units", [])
    if not units:
        print("Draft has no units.")
        return 1

    target_realm = args.target_realm.strip() or _infer_target_realm(manifest)
    if "realms" not in manifest or target_realm not in manifest["realms"]:
        print(f"Target realm not found in manifest: {target_realm}")
        return 1

    # Build manifest preview with appended units.
    preview = json.loads(json.dumps(manifest, ensure_ascii=False))
    realm_units = preview["realms"][target_realm].setdefault("units", [])

    for u in units:
        unit_number = int(u["unit_number"])
        word_ids = [int(str(w)[1:]) for w in u.get("word_ids", []) if str(w).startswith("W")]
        # Minimal lesson skeleton: 3 intro + 3 practice + 1 checkpoint = 7 circles
        lessons = []
        for i in range(1, 8):
            if i in (1, 2, 4):
                ltype = "intro"
            elif i == 7:
                ltype = "checkpoint"
            else:
                ltype = "practice"
            # split words across early lessons, keep checkpoint empty
            if ltype == "checkpoint":
                l_words = []
            else:
                start = ((i - 1) % 4) * max(1, len(word_ids) // 4)
                end = start + max(1, len(word_ids) // 4)
                l_words = word_ids[start:end]
            lessons.append(
                {
                    "lesson_number": i,
                    "title": f"Lesson {i}",
                    "type": ltype,
                    "word_ids": l_words if l_words else word_ids[:5],
                    "count": len(l_words) if l_words else min(5, len(word_ids)),
                }
            )

        realm_units.append(
            {
                "unit_number": unit_number,
                "title": f"Unit {unit_number}: {u.get('title', 'Expansion Unit')}",
                "word_ids": word_ids,
                "count": len(word_ids),
                "lessons": lessons,
            }
        )

    stamp = dt.date.today().isoformat()
    out_json = (
        Path(args.out_json)
        if args.out_json
        else repo_root / "docs" / "reports" / f"zh_standard_expansion_preview_{stamp}.json"
    )
    out_sql = (
        Path(args.out_sql)
        if args.out_sql
        else repo_root / "docs" / "reports" / f"unit_concepts_expansion_plan_{stamp}.sql"
    )
    out_json.parent.mkdir(parents=True, exist_ok=True)

    out_json.write_text(json.dumps(preview, ensure_ascii=False, indent=2), encoding="utf-8")

    sql_lines = ["BEGIN TRANSACTION;"]
    for u in units:
        uid = str(int(u["unit_number"]))
        for seq, wid in enumerate(u.get("word_ids", []), start=1):
            sql_lines.append(
                f"INSERT OR REPLACE INTO unit_concepts (unit_id, concept_id, sequence) VALUES ('{uid}', '{wid}', {seq});"
            )
    sql_lines.append("COMMIT;")
    out_sql.write_text("\n".join(sql_lines) + "\n", encoding="utf-8")

    print(f"Wrote manifest preview: {out_json}")
    print(f"Wrote SQL plan: {out_sql}")
    print(f"Units planned: {len(units)} (target realm {target_realm})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
