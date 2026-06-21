#!/usr/bin/env python3
"""Apply sentence-generation worker outputs into `sentences` and `word_sentences`.

Expected worker file format (JSON):
{
  "items": [
    {
      "concept_id": "W123456",
      "sentences": [
        {"text_zh":"...", "pinyin":"...", "translation_en":"..."},
        {"text_zh":"...", "pinyin":"...", "translation_en":"..."}
      ]
    }
  ]
}
"""

from __future__ import annotations

import argparse
import datetime as dt
import glob
import hashlib
import json
import re
import sqlite3
from pathlib import Path
from typing import Any, Dict, Iterable, List, Sequence, Set, Tuple


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _resolve_path(root: Path, raw: str) -> Path:
    p = Path(raw)
    return p if p.is_absolute() else root / p


def _norm_space(v: str) -> str:
    return re.sub(r"\s+", " ", str(v or "").strip())


def _split_csv(raw: str, fallback: Sequence[str]) -> List[str]:
    values = [v.strip() for v in str(raw or "").split(",") if v.strip()]
    if not values:
        return list(fallback)
    out: List[str] = []
    seen = set()
    for value in values:
        key = value.lower()
        if key in seen:
            continue
        seen.add(key)
        out.append(value)
    return out


_LEVEL_RANK = {"HSK1": 1, "HSK2": 2, "HSK3": 3, "HSK4": 4, "HSK5": 5, "HSK6": 6, "HSK7": 7}
_LENGTH_RULES = {
    "HSK1": (2, 40),
    "HSK2": (3, 50),
    "HSK3": (4, 70),
    "HSK4": (4, 75),
    "HSK5": (5, 85),
    "HSK6": (5, 90),
    "HSK7": (5, 100),
}
_DEFAULT_LEVELS = ["HSK1", "HSK2", "HSK3", "HSK4", "HSK5", "HSK6", "HSK7"]


def _iter_items(path: Path) -> Iterable[dict]:
    suffix = path.suffix.lower()
    if suffix == ".jsonl":
        for line in path.read_text(encoding="utf-8").splitlines():
            raw = line.strip()
            if not raw:
                continue
            try:
                payload = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if isinstance(payload, dict):
                yield payload
        return

    if suffix == ".json":
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            return
        if isinstance(data, dict):
            if isinstance(data.get("items"), list):
                for item in data["items"]:
                    if isinstance(item, dict):
                        yield item
                return
            if isinstance(data.get("results"), list):
                for item in data["results"]:
                    if isinstance(item, dict):
                        yield item
                return
            if "concept_id" in data and "sentences" in data:
                yield data
                return
        elif isinstance(data, list):
            for item in data:
                if isinstance(item, dict):
                    yield item


def _sentence_id(text_zh: str, pinyin: str) -> str:
    key = f"{_norm_space(text_zh)}|{_norm_space(pinyin)}"
    digest = hashlib.sha1(key.encode("utf-8")).hexdigest()[:16].upper()
    return f"S_AUTO_{digest}"


def _in_clause(values: Sequence[str]) -> Tuple[str, List[str]]:
    placeholders = ",".join("?" for _ in values)
    return f"({placeholders})", list(values)


def _fetch_level_map(
    conn: sqlite3.Connection,
    standard: str,
    levels: Sequence[str],
) -> Dict[str, str]:
    level_clause, level_params = _in_clause(levels)
    sql = f"""
        SELECT concept_id, level
        FROM concept_curriculum_map
        WHERE standard = ?
          AND level IN {level_clause}
    """
    rows = conn.execute(sql, [standard, *level_params]).fetchall()
    out: Dict[str, str] = {}
    for row in rows:
        concept_id = str(row[0])
        level = str(row[1])
        prev = out.get(concept_id)
        if prev is None or _LEVEL_RANK.get(level, 99) < _LEVEL_RANK.get(prev, 99):
            out[concept_id] = level
    return out


def _within_level_length(level: str, text_zh: str) -> bool:
    lo, hi = _LENGTH_RULES.get(level, _LENGTH_RULES["HSK7"])
    n = len(text_zh)
    return lo <= n <= hi


def _tags_for_style(sentence_item: dict, existing_count: int) -> str:
    explicit_tags = _norm_space(sentence_item.get("tags") or "")
    if explicit_tags:
        return explicit_tags
    style = _norm_space(sentence_item.get("style") or "").lower()
    if not style:
        # Keep old corpus shape: alternate context + dialogue/spoken.
        style = "context" if existing_count % 2 == 0 else "dialogue"
    if style == "dialogue":
        return "imported|dialogue|spoken"
    if style == "standard":
        return "imported|hsk_core|standard"
    return "imported|context"


def _load_contract(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _fetch_hsk1_scope_word_ids(conn: sqlite3.Connection) -> Set[str]:
    rows = conn.execute(
        """
        SELECT DISTINCT concept_id
        FROM unit_concepts
        WHERE unit_id LIKE 'UNIT_HSK1_%'
        """
    ).fetchall()
    return {str(r[0]) for r in rows if r and r[0]}


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply sentence results from worker files")
    parser.add_argument("--contract", default="", help="Canonical contract JSON for hard-gate checks (optional)")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--input-glob", required=True)
    parser.add_argument("--source-tag", default="external_sentence_import")
    parser.add_argument("--standard", default="HSK3.0")
    parser.add_argument("--levels", default=",".join(_DEFAULT_LEVELS))
    parser.add_argument("--max-per-word", type=int, default=3)
    parser.add_argument("--no-level-length-guard", action="store_true")
    parser.add_argument("--report-dir", default="docs/reports")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    if args.max_per_word < 1:
        raise SystemExit("--max-per-word must be >= 1")

    root = _repo_root()
    contract: Dict[str, Any] = {}
    contract_path = _resolve_path(root, args.contract) if str(args.contract).strip() else None
    if contract_path is not None:
        if not contract_path.exists():
            print(f"Contract not found: {contract_path}")
            return 1
        contract = _load_contract(contract_path)
        if str(contract.get("standard", "")).strip() not in {"", "HSK3.0"}:
            print("Contract standard must be HSK3.0")
            return 1
        if str(contract.get("level", "")).strip() not in {"", "HSK1"}:
            print("Contract level must be HSK1")
            return 1

    db_path = _resolve_path(root, args.db)
    report_dir = _resolve_path(root, args.report_dir)
    report_dir.mkdir(parents=True, exist_ok=True)
    files = sorted(Path(p) for p in glob.glob(str(_resolve_path(root, args.input_glob))))

    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1
    if not files:
        print(f"No input files for glob: {args.input_glob}")
        return 1

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout=5000")
    levels = _split_csv(args.levels, _DEFAULT_LEVELS)
    level_map = _fetch_level_map(conn, args.standard, levels)

    stats = {
        "files": len(files),
        "items_seen": 0,
        "concept_missing": 0,
        "concept_level_missing": 0,
        "sentence_candidates_seen": 0,
        "sentences_inserted": 0,
        "sentences_reused": 0,
        "word_links_inserted": 0,
        "skipped_empty": 0,
        "skipped_length_guard": 0,
        "skipped_limit": 0,
        "skipped_contract_scope": 0,
        "skipped_missing_target_hanzi": 0,
    }

    known_concepts = {str(r[0]): str(r[1] or "").strip() for r in conn.execute("SELECT id, text FROM concepts").fetchall()}
    hsk1_scope_word_ids: Set[str] = set()
    if contract_path is not None:
        hsk1_scope_word_ids = _fetch_hsk1_scope_word_ids(conn)

    try:
        for file_path in files:
            for item in _iter_items(file_path):
                stats["items_seen"] += 1
                concept_id = str(item.get("concept_id") or "").strip()
                if not concept_id or concept_id not in known_concepts:
                    stats["concept_missing"] += 1
                    continue
                if contract_path is not None and concept_id not in hsk1_scope_word_ids:
                    stats["skipped_contract_scope"] += 1
                    continue
                concept_level = level_map.get(concept_id)
                if not concept_level:
                    stats["concept_level_missing"] += 1
                    concept_level = "HSK7"

                existing_count = conn.execute(
                    "SELECT COUNT(*) FROM word_sentences WHERE word_id = ?",
                    (concept_id,),
                ).fetchone()[0]
                if existing_count >= args.max_per_word:
                    stats["skipped_limit"] += 1
                    continue

                sent_list = item.get("sentences")
                if not isinstance(sent_list, list):
                    continue

                for sentence_item in sent_list:
                    if existing_count >= args.max_per_word:
                        break
                    if not isinstance(sentence_item, dict):
                        continue
                    stats["sentence_candidates_seen"] += 1

                    text_zh = _norm_space(sentence_item.get("text_zh") or sentence_item.get("sentence_zh") or "")
                    pinyin = _norm_space(sentence_item.get("pinyin") or "")
                    translation_en = _norm_space(
                        sentence_item.get("translation_en")
                        or sentence_item.get("sentence_en")
                        or sentence_item.get("translation")
                        or ""
                    )
                    if not text_zh or not pinyin or not translation_en:
                        stats["skipped_empty"] += 1
                        continue
                    concept_text = known_concepts.get(concept_id, "")
                    if contract_path is not None and concept_text and concept_text not in text_zh:
                        stats["skipped_missing_target_hanzi"] += 1
                        continue
                    if not args.no_level_length_guard and not _within_level_length(concept_level, text_zh):
                        stats["skipped_length_guard"] += 1
                        continue

                    # Try reuse by exact zh text first.
                    row = conn.execute(
                        "SELECT id FROM sentences WHERE text = ? LIMIT 1",
                        (text_zh,),
                    ).fetchone()
                    if row:
                        sentence_id = str(row[0])
                        stats["sentences_reused"] += 1
                    else:
                        sentence_id = _sentence_id(text_zh, pinyin)
                        conn.execute(
                            """
                            INSERT OR IGNORE INTO sentences
                                (id, text, pinyin, translation, tags, difficulty, created_at)
                            VALUES (?, ?, ?, ?, ?, ?, datetime('now'))
                            """,
                            (
                                sentence_id,
                                text_zh,
                                pinyin,
                                translation_en,
                                _tags_for_style(sentence_item, existing_count),
                                1,
                            ),
                        )
                        inserted_row = conn.execute(
                            "SELECT 1 FROM sentences WHERE id = ? LIMIT 1",
                            (sentence_id,),
                        ).fetchone()
                        if inserted_row:
                            stats["sentences_inserted"] += 1

                    # Link sentence to concept.
                    has_link = conn.execute(
                        """
                        SELECT 1 FROM word_sentences
                        WHERE word_id = ? AND sentence_id = ?
                        LIMIT 1
                        """,
                        (concept_id, sentence_id),
                    ).fetchone()
                    if not has_link:
                        is_primary = 1 if existing_count == 0 else 0
                        conn.execute(
                            """
                            INSERT OR IGNORE INTO word_sentences
                                (word_id, sentence_id, is_primary)
                            VALUES (?, ?, ?)
                            """,
                            (concept_id, sentence_id, is_primary),
                        )
                        stats["word_links_inserted"] += 1
                        existing_count += 1

        if args.apply:
            conn.commit()
        else:
            conn.rollback()
    finally:
        conn.close()

    report = {
        "date": dt.date.today().isoformat(),
        "db": str(db_path),
        "contract_file": str(contract_path) if contract_path is not None else "",
        "contract_id": contract.get("id") if contract else "",
        "contract_version": contract.get("version") if contract else None,
        "input_glob": args.input_glob,
        "apply": args.apply,
        "max_per_word": args.max_per_word,
        **stats,
    }
    report_path = report_dir / f"apply_sentence_results_{dt.date.today().isoformat()}.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    print(json.dumps(report, ensure_ascii=False))
    print(f"Report: {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
