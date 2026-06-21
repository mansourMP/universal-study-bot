#!/usr/bin/env python3
"""Apply usage sentence pack into sentences/word_sentences/word_exercises.

This backfills `sentence_fill` for concepts that still miss usage exercise types.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sqlite3
from pathlib import Path
from typing import Dict, List


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _norm(v: str) -> str:
    return " ".join(str(v or "").split()).strip()


def _load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _latest_pack(path: Path) -> Path | None:
    files = sorted(path.glob("usage_sentence_pack_*.json"))
    return files[-1] if files else None


def _sentence_id(text_zh: str, pinyin: str) -> str:
    key = f"{_norm(text_zh)}|{_norm(pinyin)}"
    digest = hashlib.sha1(key.encode("utf-8")).hexdigest()[:16].upper()
    return f"S_AUTO_{digest}"


def _has_usage_ex(conn: sqlite3.Connection, wid: str) -> bool:
    row = conn.execute(
        """
        SELECT 1
        FROM word_exercises
        WHERE word_id = ?
          AND exercise_type IN ('sentence_fill', 'collocation_pick')
        LIMIT 1
        """,
        (wid,),
    ).fetchone()
    return row is not None


def _unit_words(conn: sqlite3.Connection, wid: str) -> List[str]:
    unit_row = conn.execute(
        "SELECT unit_id FROM unit_concepts WHERE concept_id = ? AND unit_id LIKE 'UNIT_HSK1_%' LIMIT 1",
        (wid,),
    ).fetchone()
    if not unit_row:
        return []
    unit_id = str(unit_row[0])
    rows = conn.execute(
        "SELECT concept_id FROM unit_concepts WHERE unit_id = ? ORDER BY sequence ASC, concept_id ASC",
        (unit_id,),
    ).fetchall()
    return [str(r[0]) for r in rows]


def _pick_distractors(conn: sqlite3.Connection, wid: str, needed: int = 3) -> List[str]:
    out: List[str] = []
    for cid in _unit_words(conn, wid):
        if cid == wid:
            continue
        row = conn.execute("SELECT text FROM concepts WHERE id = ? LIMIT 1", (cid,)).fetchone()
        if row and row[0]:
            t = str(row[0]).strip()
            if t and t not in out:
                out.append(t)
            if len(out) >= needed:
                return out
    rows = conn.execute("SELECT text FROM concepts WHERE id != ? ORDER BY id ASC LIMIT 200", (wid,)).fetchall()
    for r in rows:
        t = str(r[0] or "").strip()
        if t and t not in out:
            out.append(t)
        if len(out) >= needed:
            break
    return out[:needed]


def _next_variant(conn: sqlite3.Connection, wid: str, ex_type: str) -> int:
    row = conn.execute(
        "SELECT COALESCE(MAX(variant_index), -1) FROM word_exercises WHERE word_id = ? AND exercise_type = ?",
        (wid, ex_type),
    ).fetchone()
    return int((row[0] if row else -1) or -1) + 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply usage sentence pack")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--pack", default="", help="Path to usage_sentence_pack_*.json (optional)")
    parser.add_argument("--reports-dir", default="docs/reports")
    parser.add_argument("--source-tag", default="usage_sentence_backfill_v1")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    root = _repo_root()
    db_path = root / args.db if not Path(args.db).is_absolute() else Path(args.db)
    reports_dir = root / args.reports_dir if not Path(args.reports_dir).is_absolute() else Path(args.reports_dir)
    pack_path = Path(args.pack) if args.pack else _latest_pack(reports_dir)
    if pack_path and not pack_path.is_absolute():
        pack_path = root / pack_path

    if not db_path.exists():
        print(json.dumps({"ok": False, "error": f"DB not found: {db_path}"}))
        return 1
    if not pack_path or not pack_path.exists():
        print(json.dumps({"ok": False, "error": "No usage pack found"}))
        return 1

    pack = _load_json(pack_path)
    items = pack.get("items", [])
    conn = sqlite3.connect(str(db_path), timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout = 30000")

    stats: Dict[str, int] = {
        "items_seen": 0,
        "concept_missing": 0,
        "skipped_has_usage": 0,
        "sentences_inserted": 0,
        "sentence_links_inserted": 0,
        "usage_ex_inserted": 0,
    }

    try:
        known = {str(r[0]) for r in conn.execute("SELECT id FROM concepts").fetchall()}
        for item in items:
            stats["items_seen"] += 1
            wid = str(item.get("concept_id") or "").strip()
            if not wid or wid not in known:
                stats["concept_missing"] += 1
                continue
            if _has_usage_ex(conn, wid):
                stats["skipped_has_usage"] += 1
                continue

            hanzi = _norm(item.get("hanzi") or "")
            pinyin = _norm(item.get("pinyin") or "")
            sentence_zh = _norm(item.get("sentence_zh") or "")
            sentence_en = _norm(item.get("sentence_en") or "")
            if not sentence_zh or not hanzi:
                continue

            sid = _sentence_id(sentence_zh, pinyin)
            if args.apply:
                conn.execute(
                    """
                    INSERT OR IGNORE INTO sentences
                      (id, text, pinyin, translation, tags, difficulty, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, datetime('now'))
                    """,
                    (sid, sentence_zh, pinyin, sentence_en or "", "imported|usage_fill", 2),
                )
            exists = conn.execute("SELECT 1 FROM sentences WHERE id = ? LIMIT 1", (sid,)).fetchone()
            if exists:
                stats["sentences_inserted"] += 1

            link = conn.execute(
                "SELECT 1 FROM word_sentences WHERE word_id = ? AND sentence_id = ? LIMIT 1",
                (wid, sid),
            ).fetchone()
            if not link and args.apply:
                conn.execute(
                    "INSERT OR IGNORE INTO word_sentences (word_id, sentence_id, is_primary) VALUES (?, ?, 0)",
                    (wid, sid),
                )
                stats["sentence_links_inserted"] += 1

            fill_sentence = sentence_zh.replace(hanzi, "___", 1) if hanzi in sentence_zh else f"___"
            distractors = _pick_distractors(conn, wid, needed=3)
            options = [hanzi] + distractors
            payload = {
                "sentence": fill_sentence,
                "options": options,
                "correct": hanzi,
                "translation": sentence_en,
                "instruction_en": "Fill in the blank",
            }

            if args.apply:
                variant = _next_variant(conn, wid, "sentence_fill")
                ex_id = f"usage_sentence_fill_{wid}_{variant:02d}"
                conn.execute(
                    """
                    INSERT OR IGNORE INTO word_exercises
                      (id, word_id, exercise_type, difficulty, variant_index, payload, tags, group_id)
                    VALUES (?, ?, 'sentence_fill', 3, ?, ?, ?, ?)
                    """,
                    (
                        ex_id,
                        wid,
                        variant,
                        json.dumps(payload, ensure_ascii=False),
                        json.dumps({"source_tag": args.source_tag, "mode": "usage_backfill"}, ensure_ascii=False),
                        f"{wid}:sentence_fill",
                    ),
                )
                stats["usage_ex_inserted"] += 1

        if args.apply:
            conn.commit()
        else:
            conn.rollback()
    finally:
        conn.close()

    out = {
        "ok": True,
        "date": dt.date.today().isoformat(),
        "db": str(db_path),
        "pack": str(pack_path),
        "apply": bool(args.apply),
        **stats,
    }
    print(json.dumps(out, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

