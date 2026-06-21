#!/usr/bin/env python3
"""Generate a deterministic JSON pack of usage sentences from a todo list."""

from __future__ import annotations

import argparse
import json
from datetime import date
from pathlib import Path
from typing import Dict, List


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _latest_todo(reports_dir: Path) -> Path | None:
    candidates = sorted(reports_dir.glob("usage_sentence_todo_*.json"))
    return candidates[-1] if candidates else None


def _classify(meaning: str) -> str:
    m = meaning.lower().strip()
    if m.startswith("to "):
        return "verb"
    if m.startswith("a ") or m.startswith("an ") or m.startswith("the "):
        return "noun"
    if "person" in m or "people" in m:
        return "noun"
    if "ing" in m and m.startswith("to "):
        return "verb"
    return "other"


def _sentence_for(item: Dict[str, str]) -> Dict[str, str]:
    hanzi = item["hanzi"]
    meaning = item["meaning"]
    kind = _classify(meaning)

    if kind == "verb":
        zh = f"我每天{hanzi}。"
        en = f"I {meaning.replace('to ', '')} every day."
    elif kind == "noun":
        zh = f"这是{hanzi}。"
        en = f"This is {meaning}."
    else:
        zh = f"我很喜欢{hanzi}。"
        en = f"I really like {meaning}."

    return {"sentence_zh": zh, "sentence_en": en}


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate usage sentence pack")
    parser.add_argument("--todo", help="Path to usage_sentence_todo_*.json")
    parser.add_argument("--out-dir", default="docs/reports")
    args = parser.parse_args()

    repo_root = _repo_root()
    out_dir = repo_root / args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    todo_path = Path(args.todo) if args.todo else _latest_todo(out_dir)
    if not todo_path or not todo_path.exists():
        print("No todo JSON found. Provide --todo.")
        return 1

    todo = json.loads(todo_path.read_text(encoding="utf-8"))
    items = todo.get("items", [])
    pack = {
        "date": date.today().isoformat(),
        "source": str(todo_path),
        "count": len(items),
        "items": [],
    }

    for item in items:
        sentence = _sentence_for(item)
        pack["items"].append(
            {
                "concept_id": item["concept_id"],
                "hanzi": item["hanzi"],
                "pinyin": item["pinyin"],
                "meaning": item["meaning"],
                **sentence,
            }
        )

    date_str = pack["date"]
    out_path = out_dir / f"usage_sentence_pack_{date_str}.json"
    out_path.write_text(json.dumps(pack, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"Wrote {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
