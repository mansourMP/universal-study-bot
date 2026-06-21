#!/usr/bin/env python3
"""Apply HSK1 exercise gap jobs into word_exercises.

Input: docs/hsk1_exercise_gap_shards_200/exercise_shard_*.json
Output: inserts missing exercise types per word (deterministic payloads).
"""

from __future__ import annotations

import argparse
import glob
import hashlib
import json
import sqlite3
from pathlib import Path
from typing import Any, Dict, List, Sequence, Set, Tuple


DIFFICULTY_MAP = {
    "meaning_select": 1,
    "audio_select": 1,
    "character_select": 2,
    "order_sentence": 3,
    "reading_micro": 3,
}


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _resolve_path(root: Path, raw: str) -> Path:
    p = Path(raw)
    return p if p.is_absolute() else root / p


def _stable_hash(*parts: Any) -> int:
    raw = "::".join(str(p) for p in parts)
    return int(hashlib.md5(raw.encode("utf-8")).hexdigest()[:8], 16)


def _sense_payload(sense_id: str, gloss: str) -> Dict[str, Any]:
    return {
        "sense": {
            "sense_id": sense_id,
            "primary_gloss": gloss,
            "alternatives": [],
        }
    }


def _word_row(conn: sqlite3.Connection, word_id: str) -> sqlite3.Row | None:
    return conn.execute(
        "SELECT id, text, COALESCE(pinyin,''), COALESCE(meaning,'') FROM concepts WHERE id = ? LIMIT 1",
        (word_id,),
    ).fetchone()


def _word_unit_id(conn: sqlite3.Connection, word_id: str, fallback_unit: str = "") -> str:
    row = conn.execute(
        """
        SELECT unit_id
        FROM unit_concepts
        WHERE concept_id = ?
          AND unit_id LIKE 'UNIT_HSK1_%'
        ORDER BY unit_id ASC
        LIMIT 1
        """,
        (word_id,),
    ).fetchone()
    if row and row[0]:
        return str(row[0])
    return fallback_unit


def _unit_word_ids(conn: sqlite3.Connection, unit_id: str) -> List[str]:
    if not unit_id:
        return []
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


def _sample_hanzi_distractors(
    conn: sqlite3.Connection,
    word_id: str,
    unit_id: str,
    needed: int,
) -> List[str]:
    candidates: List[str] = []
    for wid in _unit_word_ids(conn, unit_id):
        if wid == word_id:
            continue
        row = _word_row(conn, wid)
        if row and row[1]:
            text = str(row[1]).strip()
            if text and text not in candidates:
                candidates.append(text)
    if len(candidates) < needed:
        rows = conn.execute(
            """
            SELECT text
            FROM concepts
            WHERE id != ?
            ORDER BY id ASC
            LIMIT 200
            """,
            (word_id,),
        ).fetchall()
        for r in rows:
            text = str(r[0] or "").strip()
            if text and text not in candidates:
                candidates.append(text)
            if len(candidates) >= needed:
                break
    seed = _stable_hash(word_id, "hanzi_distractors")
    candidates.sort(key=lambda x: _stable_hash(seed, x))
    return candidates[:needed]


def _sample_meaning_distractors(
    conn: sqlite3.Connection,
    word_id: str,
    unit_id: str,
    needed: int,
) -> List[str]:
    candidates: List[str] = []
    for wid in _unit_word_ids(conn, unit_id):
        if wid == word_id:
            continue
        row = _word_row(conn, wid)
        if row and row[3]:
            meaning = str(row[3]).strip()
            if meaning and meaning not in candidates:
                candidates.append(meaning)
    if len(candidates) < needed:
        rows = conn.execute(
            """
            SELECT meaning
            FROM concepts
            WHERE id != ?
            ORDER BY id ASC
            LIMIT 300
            """,
            (word_id,),
        ).fetchall()
        for r in rows:
            meaning = str(r[0] or "").strip()
            if meaning and meaning not in candidates:
                candidates.append(meaning)
            if len(candidates) >= needed:
                break
    seed = _stable_hash(word_id, "meaning_distractors")
    candidates.sort(key=lambda x: _stable_hash(seed, x))
    return candidates[:needed]


def _default_order_sentence(
    conn: sqlite3.Connection,
    word_id: str,
    hanzi: str,
    gloss: str,
    sense_id: str,
) -> Dict[str, Any]:
    row = conn.execute(
        """
        SELECT s.text, s.translation, s.pinyin, s.segmentation
        FROM word_sentences ws
        JOIN sentences s ON s.id = ws.sentence_id
        WHERE ws.word_id = ?
          AND TRIM(COALESCE(s.text,'')) != ''
        ORDER BY ws.is_primary DESC, ws.sentence_id ASC
        LIMIT 1
        """,
        (word_id,),
    ).fetchone()
    if row:
        sent_zh = str(row[0] or "").strip()
        sent_en = str(row[1] or "").strip()
        sent_py = str(row[2] or "").strip()
        seg_raw = row[3]
        chunks: List[str] = []
        if seg_raw:
            try:
                parsed = json.loads(seg_raw)
                if isinstance(parsed, list):
                    chunks = [str(x).strip() for x in parsed if str(x).strip()]
            except Exception:
                chunks = []
        if not chunks and sent_zh:
            chunks = [sent_zh]
        payload = {
            "sentence": sent_zh or f"我喜欢{hanzi}。",
            "translation": sent_en or f"I like {gloss}.",
            "pinyin": sent_py,
            "segments": chunks,
            "answer": "".join(chunks) if chunks else (sent_zh or f"我喜欢{hanzi}。"),
            "instruction_en": "Arrange the sentence",
        }
        payload.update(_sense_payload(sense_id, gloss))
        return payload

    fallback_sentence = f"我喜欢{hanzi}。"
    payload = {
        "sentence": fallback_sentence,
        "translation": f"I like {gloss}.",
        "segments": [f"我喜欢{hanzi}。"],
        "answer": fallback_sentence,
        "instruction_en": "Arrange the sentence",
    }
    payload.update(_sense_payload(sense_id, gloss))
    return payload


def _build_payload(
    conn: sqlite3.Connection,
    word_id: str,
    unit_id: str,
    sense_id: str,
    ex_type: str,
    hanzi: str,
    pinyin: str,
    meaning: str,
) -> Dict[str, Any]:
    if ex_type == "meaning_select":
        d = _sample_meaning_distractors(conn, word_id, unit_id, 3)
        options = [meaning] + d
        seed = _stable_hash(word_id, ex_type, "options")
        options.sort(key=lambda x: _stable_hash(seed, x))
        payload = {
            "prompt": {"hanzi": hanzi, "pinyin": pinyin},
            "options": options,
            "answer": meaning,
            "answer_index": options.index(meaning),
            "instruction_en": "Choose the correct meaning",
        }
        payload.update(_sense_payload(sense_id, meaning))
        return payload

    if ex_type == "audio_select":
        d = _sample_hanzi_distractors(conn, word_id, unit_id, 3)
        choices = [hanzi] + d
        seed = _stable_hash(word_id, ex_type, "choices")
        choices.sort(key=lambda x: _stable_hash(seed, x))
        payload = {
            "choices": choices,
            "answer": hanzi,
            "answer_index": choices.index(hanzi),
            "instruction_en": "Listen and choose the characters",
            "prompt": {"meaning": meaning, "pinyin": pinyin},
        }
        payload.update(_sense_payload(sense_id, meaning))
        return payload

    if ex_type == "character_select":
        d = _sample_hanzi_distractors(conn, word_id, unit_id, 3)
        choices = [hanzi] + d
        seed = _stable_hash(word_id, ex_type, "choices")
        choices.sort(key=lambda x: _stable_hash(seed, x))
        payload = {
            "prompt": {"meaning": meaning, "pinyin": pinyin},
            "choices": choices,
            "answer": hanzi,
            "answer_index": choices.index(hanzi),
            "instruction_en": "Choose the correct characters",
        }
        payload.update(_sense_payload(sense_id, meaning))
        return payload

    if ex_type == "order_sentence":
        return _default_order_sentence(conn, word_id, hanzi, meaning, sense_id)

    # Fallback payload
    payload = {
        "prompt": {"hanzi": hanzi, "pinyin": pinyin},
        "options": [meaning],
        "answer": meaning,
        "answer_index": 0,
        "instruction_en": "Choose the correct meaning",
    }
    payload.update(_sense_payload(sense_id, meaning))
    return payload


def _next_variant_index(conn: sqlite3.Connection, word_id: str, ex_type: str) -> int:
    row = conn.execute(
        "SELECT COALESCE(MAX(variant_index), -1) FROM word_exercises WHERE word_id = ? AND exercise_type = ?",
        (word_id, ex_type),
    ).fetchone()
    return int((row[0] if row else -1) or -1) + 1


def _exercise_exists(conn: sqlite3.Connection, word_id: str, ex_type: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM word_exercises WHERE word_id = ? AND exercise_type = ? LIMIT 1",
        (word_id, ex_type),
    ).fetchone()
    return row is not None


def _load_jobs(paths: Sequence[str]) -> List[Dict[str, Any]]:
    jobs: List[Dict[str, Any]] = []
    for p in paths:
        data = json.loads(Path(p).read_text(encoding="utf-8"))
        for job in data.get("jobs", []):
            jobs.append(job)
    return jobs


def _load_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _hsk1_scope_word_ids(conn: sqlite3.Connection) -> Set[str]:
    rows = conn.execute(
        """
        SELECT DISTINCT concept_id
        FROM unit_concepts
        WHERE unit_id LIKE 'UNIT_HSK1_%'
        """
    ).fetchall()
    return {str(r[0]) for r in rows if r and r[0]}


def _primary_sense_map(conn: sqlite3.Connection, word_ids: Sequence[str]) -> Dict[str, str]:
    if not word_ids:
        return {}
    placeholders = ",".join("?" for _ in word_ids)
    rows = conn.execute(
        f"""
        SELECT concept_id, sense_id
        FROM concept_senses
        WHERE is_primary = 1
          AND concept_id IN ({placeholders})
        """,
        tuple(word_ids),
    ).fetchall()
    return {str(r[0]): str(r[1]) for r in rows}


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply HSK1 exercise gap shards")
    parser.add_argument("--contract", default="", help="Canonical contract JSON for hard-gate checks (optional)")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--input-glob", default="docs/hsk1_exercise_gap_shards_200/exercise_shard_*.json")
    parser.add_argument("--source-tag", default="hsk1_gap_bootstrap_v1")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    root = _repo_root()
    contract: Dict[str, Any] = {}
    contract_path = _resolve_path(root, args.contract) if str(args.contract).strip() else None
    if contract_path is not None:
        if not contract_path.exists():
            print(json.dumps({"ok": False, "error": f"Contract not found: {contract_path}"}))
            return 1
        contract = _load_json(contract_path)
        if str(contract.get("standard", "")).strip() not in {"", "HSK3.0"}:
            print(json.dumps({"ok": False, "error": "contract standard must be HSK3.0"}))
            return 1
        if str(contract.get("level", "")).strip() not in {"", "HSK1"}:
            print(json.dumps({"ok": False, "error": "contract level must be HSK1"}))
            return 1

    db_path = _resolve_path(root, args.db)
    glob_pattern = str(_resolve_path(root, args.input_glob))
    files = sorted(glob.glob(glob_pattern))

    if not db_path.exists():
        print(json.dumps({"ok": False, "error": f"DB not found: {db_path}"}))
        return 1
    if not files:
        print(json.dumps({"ok": False, "error": f"No shard files matched: {glob_pattern}"}))
        return 1

    jobs = _load_jobs(files)
    conn = sqlite3.connect(str(db_path), timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout = 30000")

    inserted = 0
    skipped_existing = 0
    skipped_missing_word = 0
    skipped_contract_scope = 0
    skipped_disallowed_type = 0
    skipped_sense_mismatch = 0
    planned = 0

    try:
        allowed_types: Set[str] = set()
        hsk1_scope: Set[str] = set()
        primary_sense: Dict[str, str] = {}
        if contract_path is not None:
            sources = contract.get("sources", {}) if isinstance(contract, dict) else {}
            template_file = str(sources.get("circle_template") or "").strip()
            if template_file:
                template_path = _resolve_path(root, template_file)
                if not template_path.exists():
                    print(json.dumps({"ok": False, "error": f"Template not found from contract: {template_path}"}))
                    return 1
                template = _load_json(template_path)
                for circle in template.get("circle_sequence", []):
                    mix = circle.get("exercise_mix", {}) if isinstance(circle, dict) else {}
                    for ex_type in mix.keys():
                        if str(ex_type).strip():
                            allowed_types.add(str(ex_type).strip())
            hsk1_scope = _hsk1_scope_word_ids(conn)
            primary_sense = _primary_sense_map(conn, sorted(hsk1_scope))

        for job in jobs:
            wid = str(job.get("concept_id") or "").strip()
            if not wid:
                continue
            if contract_path is not None and wid not in hsk1_scope:
                skipped_contract_scope += 1
                continue
            row = _word_row(conn, wid)
            if not row:
                skipped_missing_word += 1
                continue
            hanzi = str(row[1] or "").strip()
            pinyin = str(row[2] or "").strip()
            meaning = str(row[3] or "").strip()
            sense_id = str(job.get("sense_id") or f"{wid}::s01")
            if contract_path is not None:
                ps = primary_sense.get(wid)
                if ps and sense_id != ps:
                    skipped_sense_mismatch += 1
                    continue
            unit_id = _word_unit_id(conn, wid, str(job.get("unit_id") or ""))
            suggested = [str(x).strip() for x in (job.get("suggested_new_types") or []) if str(x).strip()]

            for ex_type in suggested:
                if contract_path is not None and allowed_types and ex_type not in allowed_types:
                    skipped_disallowed_type += 1
                    continue
                planned += 1
                if _exercise_exists(conn, wid, ex_type):
                    skipped_existing += 1
                    continue

                variant_index = _next_variant_index(conn, wid, ex_type)
                ex_id = f"gap_{ex_type}_{wid}_{variant_index:02d}"
                payload = _build_payload(
                    conn=conn,
                    word_id=wid,
                    unit_id=unit_id,
                    sense_id=sense_id,
                    ex_type=ex_type,
                    hanzi=hanzi,
                    pinyin=pinyin,
                    meaning=meaning,
                )
                difficulty = int(DIFFICULTY_MAP.get(ex_type, 2))
                tags = json.dumps(
                    {
                        "source_tag": args.source_tag,
                        "mode": "hsk1_gap_exercise_fill",
                        "sense_id": sense_id,
                    },
                    ensure_ascii=False,
                )
                if args.apply:
                    conn.execute(
                        """
                        INSERT INTO word_exercises
                          (id, word_id, exercise_type, difficulty, variant_index, payload, tags, group_id)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            ex_id,
                            wid,
                            ex_type,
                            difficulty,
                            variant_index,
                            json.dumps(payload, ensure_ascii=False),
                            tags,
                            f"{wid}:{ex_type}",
                        ),
                    )
                inserted += 1

        if args.apply:
            conn.commit()

        print(
            json.dumps(
                {
                    "ok": True,
                    "db": str(db_path),
                    "files": len(files),
                    "jobs": len(jobs),
                    "planned": planned,
                    "inserted": inserted,
                    "skipped_existing": skipped_existing,
                    "skipped_missing_word": skipped_missing_word,
                    "skipped_contract_scope": skipped_contract_scope,
                    "skipped_disallowed_type": skipped_disallowed_type,
                    "skipped_sense_mismatch": skipped_sense_mismatch,
                    "apply": bool(args.apply),
                    "source_tag": args.source_tag,
                    "contract_file": str(contract_path) if contract_path is not None else "",
                    "contract_id": contract.get("id") if contract else "",
                    "contract_version": contract.get("version") if contract else None,
                }
            )
        )
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
