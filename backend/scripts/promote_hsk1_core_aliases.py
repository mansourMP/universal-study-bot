#!/usr/bin/env python3
"""Promote two HSK1 aliases to core and backfill minimal quality coverage.

Targets:
- W117445 爸 (dad)
- W117543 妈 (mother)

This script:
1) Promotes the two concepts from HSK1 extension -> HSK1 core.
2) Keeps unit sizes within [15,16] by moving two non-family items out of unit 17.
3) Adds sentence links (>=5 each) for the promoted words.
4) Adds 3 exercise types each (meaning_select, audio_select, character_select).
"""

from __future__ import annotations

import argparse
import json
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Tuple


@dataclass(frozen=True)
class AliasSpec:
    word_id: str
    hanzi: str
    pinyin: str
    meaning: str
    sentence_ids: Tuple[str, ...]
    meaning_options: Tuple[str, ...]
    char_choices: Tuple[str, ...]


TARGET_ALIASES: Tuple[AliasSpec, ...] = (
    AliasSpec(
        word_id="W117445",
        hanzi="爸",
        pinyin="bà",
        meaning="dad",
        sentence_ids=("S00008", "S00023", "S00510", "S00650", "S14540"),
        meaning_options=("dad", "mother", "older brother", "older sister"),
        char_choices=("爸", "妈", "哥", "姐"),
    ),
    AliasSpec(
        word_id="W117543",
        hanzi="妈",
        pinyin="mā",
        meaning="mother",
        sentence_ids=("S00018", "S00188", "S00654", "S01029", "S14623"),
        meaning_options=("mother", "dad", "older sister", "younger brother"),
        char_choices=("妈", "爸", "姐", "弟"),
    ),
)

FAMILY_UNIT = "UNIT_HSK1_017"
RELOCATIONS: Dict[str, str] = {
    # Move non-family items out of unit 17 to preserve unit size bounds.
    "W117635": "UNIT_HSK1_019",  # 有时候
    "W117654": "UNIT_HSK1_032",  # 子
}


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _q1(conn: sqlite3.Connection, sql: str, params: tuple = ()) -> int:
    return int(conn.execute(sql, params).fetchone()[0])


def _ensure_word_exists(conn: sqlite3.Connection, word_id: str, hanzi: str) -> None:
    row = conn.execute("SELECT text FROM concepts WHERE id = ?", (word_id,)).fetchone()
    if not row:
        raise RuntimeError(f"Missing concept: {word_id}")
    text = str(row[0] or "").strip()
    if text != hanzi:
        raise RuntimeError(f"Unexpected hanzi for {word_id}: {text} (expected {hanzi})")


def _primary_sense_payload(conn: sqlite3.Connection, word_id: str, fallback_gloss: str) -> Dict[str, object]:
    rows = conn.execute(
        """
        SELECT sense_id, gloss
        FROM concept_senses
        WHERE concept_id = ?
        ORDER BY is_primary DESC, ordinal ASC
        """,
        (word_id,),
    ).fetchall()
    if rows:
        primary = rows[0]
        sid = str(primary[0])
        gloss = str(primary[1] or fallback_gloss).strip() or fallback_gloss
        alts = [str(r[1]).strip() for r in rows[1:] if str(r[1] or "").strip()]
        return {"sense_id": sid, "primary_gloss": gloss, "alternatives": alts}
    return {
        "sense_id": f"{word_id}::s01",
        "primary_gloss": fallback_gloss,
        "alternatives": [],
    }


def _resequence_unit(conn: sqlite3.Connection, unit_id: str) -> None:
    rows = conn.execute(
        """
        SELECT concept_id
        FROM unit_concepts
        WHERE unit_id = ?
        ORDER BY sequence ASC, concept_id ASC
        """,
        (unit_id,),
    ).fetchall()
    concept_ids = [str(r[0]) for r in rows]
    for idx, concept_id in enumerate(concept_ids, start=1):
        conn.execute(
            """
            UPDATE unit_concepts
            SET sequence = ?
            WHERE unit_id = ? AND concept_id = ?
            """,
            (idx, unit_id, concept_id),
        )


def _insert_sentence_links(conn: sqlite3.Connection, word_id: str, sentence_ids: Tuple[str, ...]) -> int:
    inserted = 0
    for i, sid in enumerate(sentence_ids):
        before = _q1(
            conn,
            "SELECT COUNT(*) FROM word_sentences WHERE word_id = ? AND sentence_id = ?",
            (word_id, sid),
        )
        conn.execute(
            """
            INSERT OR IGNORE INTO word_sentences(word_id, sentence_id, is_primary)
            VALUES (?, ?, ?)
            """,
            (word_id, sid, 1 if i == 0 else 0),
        )
        after = _q1(
            conn,
            "SELECT COUNT(*) FROM word_sentences WHERE word_id = ? AND sentence_id = ?",
            (word_id, sid),
        )
        if after > before:
            inserted += 1
    return inserted


def _upsert_exercises(conn: sqlite3.Connection, spec: AliasSpec) -> int:
    sense = _primary_sense_payload(conn, spec.word_id, spec.meaning)
    inserted = 0

    exercise_rows = [
        (
            f"hsk1_core_alias_{spec.word_id}_meaning_select",
            "meaning_select",
            1,
            {
                "prompt": {"hanzi": spec.hanzi, "pinyin": spec.pinyin},
                "options": list(spec.meaning_options),
                "answer": spec.meaning,
                "answer_index": list(spec.meaning_options).index(spec.meaning),
                "instruction_en": "Choose the correct meaning",
                "sense": sense,
            },
        ),
        (
            f"hsk1_core_alias_{spec.word_id}_audio_select",
            "audio_select",
            1,
            {
                "choices": list(spec.char_choices),
                "answer": spec.hanzi,
                "answer_index": list(spec.char_choices).index(spec.hanzi),
                "instruction_en": "Listen and choose the characters",
                "prompt": {"meaning": spec.meaning, "pinyin": spec.pinyin},
                "sense": sense,
            },
        ),
        (
            f"hsk1_core_alias_{spec.word_id}_character_select",
            "character_select",
            2,
            {
                "prompt": {"meaning": spec.meaning, "pinyin": spec.pinyin},
                "choices": list(spec.char_choices),
                "answer": spec.hanzi,
                "answer_index": list(spec.char_choices).index(spec.hanzi),
                "instruction_en": "Choose the correct characters",
                "sense": sense,
            },
        ),
    ]

    for ex_id, ex_type, difficulty, payload in exercise_rows:
        before = _q1(conn, "SELECT COUNT(*) FROM word_exercises WHERE id = ?", (ex_id,))
        conn.execute(
            """
            INSERT OR REPLACE INTO word_exercises(
              id, word_id, exercise_type, difficulty, variant_index, payload, tags, group_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                ex_id,
                spec.word_id,
                ex_type,
                difficulty,
                0,
                json.dumps(payload, ensure_ascii=False),
                json.dumps(["hsk1", "core_alias_fix"], ensure_ascii=False),
                f"hsk1_core_alias_{spec.word_id}",
            ),
        )
        after = _q1(conn, "SELECT COUNT(*) FROM word_exercises WHERE id = ?", (ex_id,))
        if after > before:
            inserted += 1

    return inserted


def main() -> int:
    parser = argparse.ArgumentParser(description="Promote HSK1 aliases to core")
    parser.add_argument("--db", default="backend/learning_path.db")
    args = parser.parse_args()

    root = _repo_root()
    db_path = root / args.db if not Path(args.db).is_absolute() else Path(args.db)
    if not db_path.exists():
        print(json.dumps({"ok": False, "error": f"DB not found: {db_path}"}))
        return 1

    conn = sqlite3.connect(str(db_path), timeout=30)
    conn.execute("PRAGMA busy_timeout = 30000")
    try:
        for spec in TARGET_ALIASES:
            _ensure_word_exists(conn, spec.word_id, spec.hanzi)

        # 1) Promote from extension -> core in HSK1.
        promoted = 0
        for spec in TARGET_ALIASES:
            before_ext = _q1(
                conn,
                """
                SELECT COUNT(*)
                FROM concept_curriculum_map
                WHERE concept_id = ?
                  AND standard = 'HSK3.0'
                  AND level = 'HSK1'
                  AND band = 'extension'
                """,
                (spec.word_id,),
            )
            conn.execute(
                """
                UPDATE concept_curriculum_map
                SET band = 'core'
                WHERE concept_id = ?
                  AND standard = 'HSK3.0'
                  AND level = 'HSK1'
                  AND band = 'extension'
                """,
                (spec.word_id,),
            )
            after_core = _q1(
                conn,
                """
                SELECT COUNT(*)
                FROM concept_curriculum_map
                WHERE concept_id = ?
                  AND standard = 'HSK3.0'
                  AND level = 'HSK1'
                  AND band = 'core'
                """,
                (spec.word_id,),
            )
            if before_ext > 0 and after_core > 0:
                promoted += 1

        # 2) Move two non-family words out of family unit to keep size balanced.
        for concept_id, target_unit in RELOCATIONS.items():
            conn.execute(
                """
                UPDATE unit_concepts
                SET unit_id = ?
                WHERE concept_id = ? AND unit_id = ?
                """,
                (target_unit, concept_id, FAMILY_UNIT),
            )

        # 3) Ensure promoted aliases are in family unit.
        for spec in TARGET_ALIASES:
            conn.execute("DELETE FROM unit_concepts WHERE concept_id = ?", (spec.word_id,))
            seq = _q1(
                conn,
                "SELECT COALESCE(MAX(sequence), 0) FROM unit_concepts WHERE unit_id = ?",
                (FAMILY_UNIT,),
            ) + 1
            conn.execute(
                """
                INSERT INTO unit_concepts(unit_id, concept_id, sequence)
                VALUES (?, ?, ?)
                """,
                (FAMILY_UNIT, spec.word_id, seq),
            )

        # 4) Resequence affected units.
        for unit_id in {FAMILY_UNIT, *RELOCATIONS.values()}:
            _resequence_unit(conn, unit_id)

        # 5) Backfill sentence links and exercises for the two aliases.
        sentence_links_inserted = 0
        exercise_rows_inserted = 0
        for spec in TARGET_ALIASES:
            sentence_links_inserted += _insert_sentence_links(conn, spec.word_id, spec.sentence_ids)
            exercise_rows_inserted += _upsert_exercises(conn, spec)

        conn.commit()

        result = {
            "ok": True,
            "promoted_to_core": promoted,
            "sentence_links_inserted": sentence_links_inserted,
            "exercise_rows_inserted": exercise_rows_inserted,
            "hsk1_core_count": _q1(
                conn,
                """
                SELECT COUNT(DISTINCT concept_id)
                FROM concept_curriculum_map
                WHERE standard='HSK3.0' AND level='HSK1' AND band='core'
                """,
            ),
            "hsk1_unit_words": _q1(
                conn,
                """
                SELECT COUNT(DISTINCT concept_id)
                FROM unit_concepts
                WHERE unit_id LIKE 'UNIT_HSK1_%'
                """,
            ),
        }
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except Exception as exc:
        conn.rollback()
        print(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=False))
        return 1
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
