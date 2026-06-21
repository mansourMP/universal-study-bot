#!/usr/bin/env python3
"""Normalize hsk30.csv rows into a canonical merge-friendly CSV.

Output schema:
  hanzi,pinyin,meaning_en,source_level,source_name
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import re
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _norm(v: str | None) -> str:
    return str(v or "").strip()


def _first_part(value: str, sep: str) -> str:
    return value.split(sep, 1)[0].strip() if sep in value else value


def _normalize_hanzi(value: str) -> str:
    s = _norm(value)
    s = _first_part(s, "|")
    s = re.sub(r"[（(].*?[）)]", "", s)
    s = s.replace("…", "")
    s = re.sub(r"\d+$", "", s)
    s = s.replace("（一）", "一").replace("(一)", "一")
    s = "".join(ch for ch in s if ("\u4e00" <= ch <= "\u9fff") or ch in {"·"})
    return s.strip()


def _normalize_pinyin(value: str) -> str:
    s = _norm(value).lower()
    s = _first_part(s, "|")
    s = re.sub(r"[（(].*?[）)]", "", s)
    s = s.replace("…", "")
    s = _first_part(s, "/")
    s = re.sub(r"[^a-zāáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜü\s-]", "", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def main() -> int:
    parser = argparse.ArgumentParser(description="Normalize hsk30 CSV")
    parser.add_argument("--source", default="hsk30.csv")
    parser.add_argument(
        "--out",
        default="docs/specs/hsk30_canonical_lexical.csv",
        help="Output CSV path",
    )
    parser.add_argument("--source-name", default="hsk30_canonical")
    args = parser.parse_args()

    root = _repo_root()
    src = root / args.source if not Path(args.source).is_absolute() else Path(args.source)
    out = root / args.out if not Path(args.out).is_absolute() else Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)

    if not src.exists():
        print(f"Source not found: {src}")
        return 1

    total = 0
    kept = 0
    empty = 0
    with src.open("r", encoding="utf-8-sig", newline="") as f, out.open(
        "w", encoding="utf-8", newline=""
    ) as g:
        reader = csv.DictReader(f)
        writer = csv.DictWriter(
            g,
            fieldnames=["hanzi", "pinyin", "meaning_en", "source_level", "source_name"],
        )
        writer.writeheader()
        for row in reader:
            total += 1
            hanzi = _normalize_hanzi(_norm(row.get("Simplified")))
            pinyin = _normalize_pinyin(_norm(row.get("Pinyin")))
            level = _norm(row.get("Level"))
            if not hanzi:
                empty += 1
                continue
            writer.writerow(
                {
                    "hanzi": hanzi,
                    "pinyin": pinyin,
                    "meaning_en": "",
                    "source_level": level,
                    "source_name": args.source_name,
                }
            )
            kept += 1

    stamp = dt.datetime.now().isoformat(timespec="seconds")
    print(
        f"normalized_at={stamp} total={total} kept={kept} dropped_empty={empty} out={out}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

