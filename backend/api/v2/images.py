"""Serve concept images with optional override mapping."""

from __future__ import annotations

import json
import sqlite3
import re
from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse


router = APIRouter(prefix="/api/v2/image", tags=["image"])

STATIC_DIR = Path(__file__).parent.parent.parent / "static" / "images"
ASSETS_DIR = Path(__file__).parent.parent.parent.parent / "assets" / "images"
MAP_PATH = Path(__file__).parent.parent.parent / "content" / "image_map.json"
LP_DB_PATH = Path(__file__).parent.parent.parent / "learning_path.db"
MIN_IMAGE_BYTES = 128
_PUBLIC_HSK_WORD_RE = re.compile(r"^HSK([1-9])-W-(\d{4})$")
_HSK_LEVEL_ID_CACHE: dict[str, list[str]] = {}


def _load_image_map() -> dict:
    if MAP_PATH.exists():
        try:
            data = json.loads(MAP_PATH.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                return {str(k): str(v) for k, v in data.items()}
        except Exception:
            return {}
    return {}


def _resolve_local_path(mapped: str) -> Path | None:
    mapped_path = Path(mapped)
    if mapped_path.is_absolute():
        return mapped_path
    if mapped.startswith("/static/"):
        return Path(__file__).parent.parent.parent / mapped.lstrip("/")
    if mapped.startswith("static/"):
        return Path(__file__).parent.parent.parent / mapped
    return None


def _normalize_concept_id(raw_id: str) -> tuple[str, int | None]:
    cid = str(raw_id).strip()
    if not cid:
        return "", None
    if cid.isdigit():
        return cid, int(cid)
    if cid.startswith("W") and cid[1:].isdigit():
        return cid, int(cid[1:])
    return cid, None


def _is_usable_image(path: Path) -> bool:
    try:
        return path.is_file() and path.stat().st_size > MIN_IMAGE_BYTES
    except OSError:
        return False


def _get_hsk_level_ids(level_key: str) -> list[str]:
    cached = _HSK_LEVEL_ID_CACHE.get(level_key)
    if cached is not None:
        return cached

    conn = sqlite3.connect(str(LP_DB_PATH))
    try:
        rows = conn.execute(
            """
            SELECT concept_id
            FROM concept_curriculum_map
            WHERE standard='HSK3.0' AND level=? AND band='core'
            GROUP BY concept_id
            ORDER BY concept_id
            """,
            (level_key,),
        ).fetchall()
    finally:
        conn.close()

    ids = [str(row[0] or "").strip() for row in rows if str(row[0] or "").strip()]
    _HSK_LEVEL_ID_CACHE[level_key] = ids
    return ids


def _resolve_public_hsk_word_id(raw_id: str) -> str | None:
    match = _PUBLIC_HSK_WORD_RE.match(str(raw_id or "").strip().upper())
    if not match:
        return None
    level_num = int(match.group(1))
    ordinal = int(match.group(2))
    if ordinal < 1:
        return None
    level_key = f"HSK{level_num}"
    ids = _get_hsk_level_ids(level_key)
    index = ordinal - 1
    if index >= len(ids):
        return None
    return ids[index]


@router.get("/{concept_id}")
async def get_word_image(concept_id: str):
    requested_id = str(concept_id or "").strip()
    resolved_id = _resolve_public_hsk_word_id(requested_id) or requested_id

    normalized_id, numeric_id = _normalize_concept_id(resolved_id)
    if not normalized_id:
        raise HTTPException(status_code=400, detail="Invalid concept_id")

    image_map = _load_image_map()
    mapped = image_map.get(requested_id) or image_map.get(normalized_id)
    if not mapped and numeric_id is not None:
        mapped = image_map.get(str(numeric_id))
    if mapped:
        local_path = _resolve_local_path(mapped)
        if local_path and _is_usable_image(local_path):
            return FileResponse(local_path, media_type="image/webp")

    static_candidates = [
        STATIC_DIR / f"word_{normalized_id}.webp",
        ASSETS_DIR / f"word_{normalized_id}.webp",
    ]
    if numeric_id is not None:
        static_candidates.extend(
            [
                STATIC_DIR / f"word_{numeric_id}.webp",
                ASSETS_DIR / f"word_{numeric_id}.webp",
            ]
        )
    for static_path in static_candidates:
        if _is_usable_image(static_path):
            return FileResponse(static_path, media_type="image/webp")

    raise HTTPException(status_code=404, detail="Image not found")
