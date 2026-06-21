"""Image mapping utilities for Learning Path concepts."""

from __future__ import annotations

import json
import sqlite3
import re
from pathlib import Path
from typing import Dict, Optional

from media_urls import concept_image_url, normalize_image_url

IMAGE_MAP_PATH = Path(__file__).parent.parent / "content" / "image_map.json"
LP_DB_PATH = Path(__file__).parent.parent / "learning_path.db"
_PUBLIC_WORD_RE = re.compile(r"^HSK([1-9])-W-(\d{4})$")
_HSK_PUBLIC_ID_CACHE: dict[str, str] | None = None


def load_image_map() -> Dict[str, str]:
    """Load explicit concept_id -> image_url mappings (if present)."""
    if IMAGE_MAP_PATH.exists():
        try:
            data = json.loads(IMAGE_MAP_PATH.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                return {str(k): str(v) for k, v in data.items()}
        except Exception:
            return {}
    return {}


def _build_hsk_public_id_map() -> dict[str, str]:
    """Build concept_id -> public HSK word id map (first level wins)."""
    out: dict[str, str] = {}
    if not LP_DB_PATH.exists():
        return out
    conn = sqlite3.connect(str(LP_DB_PATH))
    try:
        for level_num in range(1, 8):
            level_key = f"HSK{level_num}"
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
            for idx, (concept_id,) in enumerate(rows, start=1):
                cid = str(concept_id or "").strip()
                if not cid or cid in out:
                    continue
                out[cid] = f"{level_key}-W-{idx:04d}"
    finally:
        conn.close()
    return out


def _to_public_hsk_word_id(concept_id: str) -> str:
    """Convert internal concept ids (Wxxxxx) to public HSK ids when possible."""
    cid = str(concept_id or "").strip()
    if not cid:
        return cid
    if _PUBLIC_WORD_RE.match(cid.upper()):
        return cid

    global _HSK_PUBLIC_ID_CACHE
    if _HSK_PUBLIC_ID_CACHE is None:
        _HSK_PUBLIC_ID_CACHE = _build_hsk_public_id_map()
    return _HSK_PUBLIC_ID_CACHE.get(cid, cid)


def resolve_image_url(concept_id: str, mapping: Optional[Dict[str, str]] = None) -> str:
    """Resolve image URL for a concept id.

    Default strategy: use image endpoint (/api/v2/image/{concept_id}).
    If image_map.json provides a mapping, it overrides the default.
    """
    cid = str(concept_id).strip()
    public_cid = _to_public_hsk_word_id(cid)
    if mapping is None:
        mapping = load_image_map()
    # Support overrides keyed by either raw concept id or public hsk id.
    mapped = mapping.get(cid) or mapping.get(public_cid)
    if mapped:
        return normalize_image_url(mapped) or ""
    return concept_image_url(public_cid) or f"/api/v2/image/{public_cid}"
