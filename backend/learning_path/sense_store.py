"""Sense-level helpers for concept semantics.

This module introduces a light abstraction over `concept_senses` so the
learning engine can resolve primary/alternative glosses per concept.
"""

from __future__ import annotations

import re
import sqlite3
from typing import Any, Dict, List, Optional


_SENSE_SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS concept_senses (
    sense_id TEXT PRIMARY KEY,             -- e.g. W00001::s01
    concept_id TEXT NOT NULL,              -- concepts.id
    ordinal INTEGER NOT NULL DEFAULT 1,    -- 1-based order
    gloss TEXT NOT NULL,                   -- short EN gloss for this sense
    pos TEXT,                              -- optional part-of-speech
    register TEXT,                         -- optional register ("formal", "casual")
    example_zh TEXT,                       -- optional canonical example
    example_en TEXT,                       -- optional translation for example
    is_primary INTEGER NOT NULL DEFAULT 0 CHECK(is_primary IN (0, 1)),
    source TEXT DEFAULT 'bootstrap',
    created_at TEXT DEFAULT (datetime('now')),
    UNIQUE(concept_id, ordinal),
    UNIQUE(concept_id, gloss)
);

CREATE INDEX IF NOT EXISTS idx_cs_concept ON concept_senses(concept_id);
CREATE INDEX IF NOT EXISTS idx_cs_primary ON concept_senses(concept_id, is_primary);
"""


def ensure_sense_schema(conn: sqlite3.Connection) -> None:
    """Create sense table/indexes if missing."""
    conn.executescript(_SENSE_SCHEMA_SQL)


def _normalize_gloss(raw: str) -> str:
    return re.sub(r"\s+", " ", raw.strip())


def split_glosses(raw_meaning: Optional[str]) -> List[str]:
    """Split a legacy `concepts.meaning` string into primary + alternatives.

    Notes:
    - We split on `;` and `,` only.
    - We intentionally do not split on `/` to avoid spelling variants like
      adviser/advisor being treated as separate senses.
    """
    if not raw_meaning:
        return []
    text = str(raw_meaning).replace("；", ";").replace("，", ",").strip()
    if not text:
        return []

    pieces: List[str] = []
    for semi in text.split(";"):
        semi = semi.strip()
        if not semi:
            continue
        comma_parts = [p.strip() for p in semi.split(",") if p.strip()]
        if comma_parts:
            pieces.extend(comma_parts)
        else:
            pieces.append(semi)

    deduped: List[str] = []
    seen = set()
    for p in pieces:
        gloss = _normalize_gloss(p)
        if not gloss:
            continue
        key = gloss.lower()
        if key in seen:
            continue
        seen.add(key)
        deduped.append(gloss)
    return deduped


def bootstrap_concept_senses(conn: sqlite3.Connection, max_senses_per_concept: int = 4) -> int:
    """Seed `concept_senses` from `concepts.meaning` for concepts without senses.

    Returns the number of inserted sense rows.
    """
    ensure_sense_schema(conn)

    rows = conn.execute(
        """
        SELECT c.id, c.meaning
        FROM concepts c
        LEFT JOIN concept_senses cs ON cs.concept_id = c.id
        WHERE cs.concept_id IS NULL
        ORDER BY c.id ASC
        """
    ).fetchall()

    inserts: List[tuple] = []
    for row in rows:
        concept_id = str(row[0])
        meanings = split_glosses(row[1])
        if not meanings:
            continue
        for idx, gloss in enumerate(meanings[:max_senses_per_concept], start=1):
            sense_id = f"{concept_id}::s{idx:02d}"
            inserts.append(
                (
                    sense_id,
                    concept_id,
                    idx,
                    gloss,
                    1 if idx == 1 else 0,
                    "bootstrap_from_concepts",
                )
            )

    if not inserts:
        return 0

    conn.executemany(
        """
        INSERT OR IGNORE INTO concept_senses
            (sense_id, concept_id, ordinal, gloss, is_primary, source)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        inserts,
    )
    conn.commit()
    return conn.total_changes


def _query_senses(conn: sqlite3.Connection, concept_id: str) -> List[Dict[str, Any]]:
    rows = conn.execute(
        """
        SELECT sense_id, gloss, pos, register, example_zh, example_en, is_primary, ordinal
        FROM concept_senses
        WHERE concept_id = ?
        ORDER BY is_primary DESC, ordinal ASC, sense_id ASC
        """,
        (concept_id,),
    ).fetchall()
    return [
        {
            "sense_id": str(r[0]),
            "gloss": str(r[1]),
            "pos": r[2],
            "register": r[3],
            "example_zh": r[4],
            "example_en": r[5],
            "is_primary": bool(r[6]),
            "ordinal": int(r[7]),
        }
        for r in rows
    ]


def _fallback_gloss_from_localizations(
    conn: sqlite3.Connection,
    concept_id: str,
    lang_code: str = "en",
) -> str:
    """Try localization table as gloss fallback when concepts.meaning is empty."""
    try:
        row = conn.execute(
            """
            SELECT meaning
            FROM concept_localizations
            WHERE concept_id = ? AND language_code = ?
            LIMIT 1
            """,
            (concept_id, lang_code),
        ).fetchone()
    except sqlite3.OperationalError:
        return ""
    if row is None:
        return ""
    value = str(row[0] or "").strip()
    return value


def get_senses(conn: sqlite3.Connection, concept_id: str, fallback: Optional[str] = None) -> List[Dict[str, Any]]:
    """Return sense records, with legacy fallback when table/data is missing."""
    try:
        senses = _query_senses(conn, concept_id)
    except sqlite3.OperationalError:
        senses = []
    if senses:
        return senses

    fallback_glosses = split_glosses(fallback)
    if not fallback_glosses:
        localized = _fallback_gloss_from_localizations(conn, concept_id, "en")
        fallback_glosses = split_glosses(localized)
    if not fallback_glosses:
        return []
    return [
        {
            "sense_id": f"{concept_id}::legacy_s{idx:02d}",
            "gloss": gloss,
            "pos": None,
            "register": None,
            "example_zh": None,
            "example_en": None,
            "is_primary": idx == 1,
            "ordinal": idx,
        }
        for idx, gloss in enumerate(fallback_glosses, start=1)
    ]


def get_primary_gloss(conn: sqlite3.Connection, concept_id: str, fallback: Optional[str] = None) -> str:
    """Resolve the primary gloss for a concept."""
    senses = get_senses(conn, concept_id, fallback=fallback)
    if senses:
        return str(senses[0]["gloss"])
    localized = _fallback_gloss_from_localizations(conn, concept_id, "en")
    if localized:
        return localized
    if fallback and str(fallback).strip():
        return str(fallback).strip()
    return ""


def get_sense_payload(conn: sqlite3.Connection, concept_id: str, fallback: Optional[str] = None) -> Dict[str, Any]:
    """Compact payload for exercise JSON.

    Example:
    {
      "sense_id": "W00001::s01",
      "primary_gloss": "to love",
      "alternatives": ["love", "to like"]
    }
    """
    senses = get_senses(conn, concept_id, fallback=fallback)
    if not senses:
        return {}
    primary = senses[0]
    alternatives = [str(s["gloss"]) for s in senses[1:]]
    payload: Dict[str, Any] = {
        "sense_id": str(primary["sense_id"]),
        "primary_gloss": str(primary["gloss"]),
    }
    if alternatives:
        payload["alternatives"] = alternatives
    return payload
