"""
vocabulary.py - v2 Vocabulary API endpoints
Uses the optimized DatabaseV2 (vocabulary_v2.db)
"""

from fastapi import APIRouter, Query, HTTPException, Depends
from typing import Optional, Any
from pathlib import Path
import sqlite3

from db_v2 import DatabaseV2
import db_v2
print(f"--- DEBUG: db_v2 path in vocabulary.py: {db_v2.__file__} ---")
from auth import verify_api_key, check_user_rate_limit
from cache_manager_v2 import CACHE
from learning_path.sense_store import get_primary_gloss
from media_urls import concept_image_url, normalize_image_url

router = APIRouter(prefix="/api/v2/vocabulary", tags=["vocabulary"])

# Initialize DB connection
DB_PATH = Path(__file__).parent.parent.parent / "vocabulary_v2.db"
DB = DatabaseV2(str(DB_PATH))
LP_DB_PATH = Path(__file__).parent.parent.parent / "learning_path.db"
STATIC_IMAGES_PATH = Path(__file__).parent.parent.parent / "static" / "images"
ASSETS_IMAGES_PATH = Path(__file__).parent.parent.parent.parent / "assets" / "images"
MIN_IMAGE_BYTES = 128
_HSK_PUBLIC_ID_MAP_CACHE: dict[str, dict[str, str]] = {}


def _normalize_hsk_level(level: Optional[int]) -> Optional[int]:
    if level is None:
        return None
    if level >= 7:
        # HSK3.0 advanced band is currently stored as combined HSK7-9.
        return 7
    return level


def _hsk_level_key(level: Optional[int]) -> str:
    normalized = _normalize_hsk_level(level) or 1
    return f"HSK{normalized}"


def _get_hsk_public_id_map(level_key: str) -> dict[str, str]:
    cached = _HSK_PUBLIC_ID_MAP_CACHE.get(level_key)
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

    id_map: dict[str, str] = {}
    for idx, (concept_id,) in enumerate(rows, start=1):
        cid = str(concept_id or "").strip()
        if not cid:
            continue
        id_map[cid] = f"{level_key}-W-{idx:04d}"
    _HSK_PUBLIC_ID_MAP_CACHE[level_key] = id_map
    return id_map


def _image_candidates_for_concept(concept_id: str) -> list[Path]:
    cid = str(concept_id or "").strip()
    if not cid:
        return []
    candidates = [
        STATIC_IMAGES_PATH / f"word_{cid}.webp",
        ASSETS_IMAGES_PATH / f"word_{cid}.webp",
    ]
    if cid.startswith("W") and cid[1:].isdigit():
        numeric = str(int(cid[1:]))
        candidates.extend(
            [
                STATIC_IMAGES_PATH / f"word_{numeric}.webp",
                ASSETS_IMAGES_PATH / f"word_{numeric}.webp",
            ]
        )
    return candidates


def _has_usable_concept_image(concept_id: str) -> bool:
    for path in _image_candidates_for_concept(concept_id):
        try:
            if path.is_file() and path.stat().st_size > MIN_IMAGE_BYTES:
                return True
        except OSError:
            continue
    return False


def _attach_hsk_image_urls(rows: list[dict[str, Any]], level_key: str) -> None:
    public_id_map = _get_hsk_public_id_map(level_key)
    for row in rows:
        concept_id = str(row.get("id") or "").strip()
        public_id = public_id_map.get(concept_id, concept_id)
        # Keep raw concept id for backend joins/debugging, expose stable public ids to clients.
        row["concept_id"] = concept_id
        row["public_id"] = public_id
        row["id"] = public_id
        row["image_url"] = (
            concept_image_url(public_id)
            if concept_id and _has_usable_concept_image(concept_id)
            else None
        )


def _normalize_rows_image_urls(rows: list[dict[str, Any]]) -> None:
    for row in rows:
        row["image_url"] = normalize_image_url(row.get("image_url"))


def _refresh_cached_hsk_image_urls(rows: list[dict[str, Any]]) -> bool:
    """Refresh stale cached rows after new files are ingested.

    Cache may contain older rows with image_url=None before files were generated.
    This keeps cache behavior but upgrades rows in-place when images now exist.
    """
    changed = False
    for row in rows:
        if row.get("image_url"):
            row["image_url"] = normalize_image_url(row.get("image_url"))
            continue
        concept_id = str(row.get("concept_id") or "").strip()
        if not concept_id:
            continue
        if not _has_usable_concept_image(concept_id):
            continue
        public_id = str(row.get("public_id") or row.get("id") or concept_id).strip()
        row["image_url"] = concept_image_url(public_id)
        changed = True
    return changed


def _fetch_hsk_level_from_learning_path(
    level: int,
    source_lang: str,
    limit: int,
    offset: int,
) -> tuple[list[dict[str, Any]], int]:
    level_key = _hsk_level_key(level)
    conn = sqlite3.connect(str(LP_DB_PATH))
    conn.row_factory = sqlite3.Row
    try:
        total = conn.execute(
            """
            SELECT COUNT(DISTINCT concept_id)
            FROM concept_curriculum_map
            WHERE standard='HSK3.0' AND level=? AND band='core'
            """
        , (level_key,)).fetchone()[0]

        rows = conn.execute(
            """
            WITH ids AS (
                SELECT concept_id
                FROM concept_curriculum_map
                WHERE standard='HSK3.0' AND level=? AND band='core'
                ORDER BY concept_id
                LIMIT ? OFFSET ?
            )
            SELECT
                c.id,
                c.id AS semantic_key,
                c.text AS word,
                COALESCE(c.pinyin, '') AS pronunciation,
                '' AS pos,
                (
                    SELECT s.text
                    FROM word_sentences ws
                    JOIN sentences s ON s.id = ws.sentence_id
                    WHERE ws.word_id = c.id
                      AND ws.is_primary = 1
                    ORDER BY ws.rowid ASC, ws.sentence_id ASC
                    LIMIT 1
                ) AS context_sentence,
                ? AS level,
                NULL AS image_url,
                COALESCE(
                    (
                        SELECT cl.meaning
                        FROM concept_localizations cl
                        WHERE cl.concept_id = c.id
                          AND cl.language_code = ?
                        ORDER BY cl.rowid DESC
                        LIMIT 1
                    ),
                    c.meaning,
                    ''
                ) AS translation,
                NULL AS context_translation
            FROM ids i
            JOIN concepts c ON c.id = i.concept_id
            ORDER BY c.id
            """,
            (level_key, limit, offset, _normalize_hsk_level(level), source_lang),
        ).fetchall()

        words = [dict(r) for r in rows]
        _attach_hsk_image_urls(words, level_key=level_key)
        for row in words:
            fallback = str(row.get("translation") or "")
            # Keep localized translation for non-English source languages.
            # English can still use the canonical primary sense gloss.
            if source_lang == "en" or not fallback:
                row["translation"] = (
                    get_primary_gloss(
                        conn,
                        str(row.get("concept_id") or row.get("id") or ""),
                        fallback=fallback,
                    )
                    or fallback
                )
            else:
                row["translation"] = fallback
        return words, int(total or 0)
    finally:
        conn.close()


def _fetch_random_hsk_level_from_learning_path(
    level: int,
    source_lang: str,
    limit: int,
) -> list[dict[str, Any]]:
    level_key = _hsk_level_key(level)
    conn = sqlite3.connect(str(LP_DB_PATH))
    conn.row_factory = sqlite3.Row
    try:
        rows = conn.execute(
            """
            WITH ids AS (
                SELECT concept_id
                FROM concept_curriculum_map
                WHERE standard='HSK3.0' AND level=? AND band='core'
                ORDER BY RANDOM()
                LIMIT ?
            )
            SELECT
                c.id,
                c.id AS semantic_key,
                c.text AS word,
                COALESCE(c.pinyin, '') AS pronunciation,
                '' AS pos,
                (
                    SELECT s.text
                    FROM word_sentences ws
                    JOIN sentences s ON s.id = ws.sentence_id
                    WHERE ws.word_id = c.id
                      AND ws.is_primary = 1
                    ORDER BY ws.rowid ASC, ws.sentence_id ASC
                    LIMIT 1
                ) AS context_sentence,
                ? AS level,
                NULL AS image_url,
                COALESCE(
                    (
                        SELECT cl.meaning
                        FROM concept_localizations cl
                        WHERE cl.concept_id = c.id
                          AND cl.language_code = ?
                        ORDER BY cl.rowid DESC
                        LIMIT 1
                    ),
                    c.meaning,
                    ''
                ) AS translation,
                NULL AS context_translation
            FROM ids i
            JOIN concepts c ON c.id = i.concept_id
            ORDER BY c.id
            """,
            (level_key, limit, _normalize_hsk_level(level), source_lang),
        ).fetchall()
        words = [dict(r) for r in rows]
        _attach_hsk_image_urls(words, level_key=level_key)
        for row in words:
            fallback = str(row.get("translation") or "")
            # Keep localized translation for non-English source languages.
            # English can still use the canonical primary sense gloss.
            if source_lang == "en" or not fallback:
                row["translation"] = (
                    get_primary_gloss(
                        conn,
                        str(row.get("concept_id") or row.get("id") or ""),
                        fallback=fallback,
                    )
                    or fallback
                )
            else:
                row["translation"] = fallback
        return words
    finally:
        conn.close()

@router.get("")
async def get_vocabulary(
    target_lang: str = Query(..., description="Target language code (e.g., 'zh', 'en')"),
    source_lang: str = Query("en", description="Source/native language for glosses"),
    level: Optional[int] = Query(None, ge=1, le=9, description="Level filter (1-9)"),
    limit: int = Query(50, ge=1, le=100, description="Items per page"),
    offset: int = Query(0, ge=0, description="Pagination offset"),
    client_id: str = Depends(verify_api_key),
    user_id: str = Depends(check_user_rate_limit)
):
    """
    Get vocabulary list with translations.
    """
    normalized_level = _normalize_hsk_level(level)
    # Try cache first
    cache_key = (
        f"vocab_v4_public_ids:{target_lang}:{source_lang}:{normalized_level}:{limit}:{offset}"
    )
    cached = CACHE.get(cache_key)
    if cached is not None:
        if target_lang == "zh":
            words = cached.get("vocabulary")
            if isinstance(words, list):
                _refresh_cached_hsk_image_urls(words)
        return cached
    
    try:
        if target_lang == "zh":
            words, total = _fetch_hsk_level_from_learning_path(
                level=normalized_level or 1,
                source_lang=source_lang,
                limit=limit,
                offset=offset,
            )
        else:
            words, total = DB.get_vocabulary(
                target_lang,
                source_lang,
                normalized_level,
                limit,
                offset,
            )
            _normalize_rows_image_urls(words)
        
        response = {
            "target_lang": target_lang,
            "source_lang": source_lang,
            "level": normalized_level,
            "total": total,
            "limit": limit,
            "offset": offset,
            "vocabulary": words,
            "next_offset": offset + limit if offset + limit < total else None,
        }
        
        CACHE.set(cache_key, response)
        return response
        
    except Exception as e:
        print(f"Error in get_vocabulary: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/random")
async def get_random_vocabulary(
    target_lang: str = Query(..., description="Target language code"),
    source_lang: str = Query("en", description="Source/native language"),
    level: int = Query(..., ge=1, le=9, description="Level (1-9)"),
    limit: int = Query(20, ge=5, le=50, description="Number of words"),
    client_id: str = Depends(verify_api_key),
    user_id: str = Depends(check_user_rate_limit)
):
    """
    Get a RANDOM set of vocabulary words for a study session (Flashcards/Quiz).
    """
    normalized_level = _normalize_hsk_level(level)
    # No caching for random endpoint (or short TTL)
    try:
        if target_lang == "zh":
            words = _fetch_random_hsk_level_from_learning_path(
                level=normalized_level,
                source_lang=source_lang,
                limit=limit,
            )
            lp_conn = sqlite3.connect(str(LP_DB_PATH))
            total = lp_conn.execute(
                """
                SELECT COUNT(DISTINCT concept_id)
                FROM concept_curriculum_map
                WHERE standard='HSK3.0' AND level=? AND band='core'
                """
                , (_hsk_level_key(normalized_level),)
            ).fetchone()[0]
            lp_conn.close()
        else:
            # Get random words
            words = DB.get_random_vocabulary(
                target_lang,
                source_lang,
                normalized_level,
                limit,
            )
            _normalize_rows_image_urls(words)
            # Get total count for the level (so the client has context)
            # We need to manually query the total since get_random doesn't return it
            conn = DB._get_conn()
            total = conn.execute(
                "SELECT COUNT(*) FROM concepts WHERE target_lang = ? AND level = ?",
                (target_lang, normalized_level),
            ).fetchone()[0]
            conn.close()

        return {
            "target_lang": target_lang,
            "source_lang": source_lang,
            "level": normalized_level,
            "total": total,      # Added: Real total count
            "limit": limit,
            "offset": 0,         # Added: Dummy offset
            "vocabulary": words,
            "next_offset": None  # Added: Explicit null to satisfy decoder
        }
    except Exception as e:
        print(f"Error in get_random_vocabulary: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/unit")
async def get_unit_chunk(
    target_lang: str = Query(..., description="Target language code"),
    source_lang: str = Query("en", description="Source/native language"),
    level: int = Query(..., ge=1, le=9, description="Level (1-9)"),
    unit_index: int = Query(..., ge=0, description="Unit index (0-based)"),
    unit_size: int = Query(20, ge=5, le=100, description="Words per unit"),
    client_id: str = Depends(verify_api_key),
    user_id: str = Depends(check_user_rate_limit)
):
    """
    Get a specific 'Unit' (chunk) of vocabulary.
    This acts as a 'Virtual Unit' filter, slicing the master list on-demand.
    Example: unit_index=0 gets words 0-19; unit_index=1 gets words 20-39.
    """
    normalized_level = _normalize_hsk_level(level)
    limit = unit_size
    offset = unit_index * unit_size
    
    cache_key = (
        f"vocab_unit_v4_public_ids:{target_lang}:{source_lang}:{normalized_level}:{unit_index}:{unit_size}"
    )
    cached = CACHE.get(cache_key)
    if cached is not None:
        if target_lang == "zh":
            words = cached.get("vocabulary")
            if isinstance(words, list):
                _refresh_cached_hsk_image_urls(words)
        return cached

    try:
        # Re-use the existing efficient get_vocabulary function
        if target_lang == "zh":
            words, total = _fetch_hsk_level_from_learning_path(
                level=normalized_level,
                source_lang=source_lang,
                limit=limit,
                offset=offset,
            )
        else:
            words, total = DB.get_vocabulary(
                target_lang,
                source_lang,
                normalized_level,
                limit,
                offset,
            )
            _normalize_rows_image_urls(words)
        
        response = {
            "target_lang": target_lang,
            "source_lang": source_lang,
            "level": normalized_level,
            "unit_index": unit_index,
            "total": total,
            "limit": limit,
            "offset": offset,
            "vocabulary": words,
            "next_offset": offset + limit if offset + limit < total else None,
        }
        
        CACHE.set(cache_key, response)
        return response
        
    except Exception as e:
        print(f"Error in get_unit_chunk: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/stats")
async def get_vocabulary_stats(
    target_lang: str = Query(..., description="Target language code"),
    client_id: str = Depends(verify_api_key),
    user_id: str = Depends(check_user_rate_limit)
):
    """
    Get statistics for vocabulary levels (e.g., word counts per level).
    Used to populate the Skills/Vocabulary Dashboard.
    """
    cache_key = f"vocab_stats_v3:{target_lang}"
    cached = CACHE.get(cache_key)
    if cached is not None:
        return cached

    try:
        groups: list[dict[str, Any]] = []
        if target_lang == "zh":
            lp_conn = sqlite3.connect(str(LP_DB_PATH))
            rows = lp_conn.execute(
                """
                SELECT level, COUNT(DISTINCT concept_id) AS cnt
                FROM concept_curriculum_map
                WHERE standard='HSK3.0' AND band='core'
                GROUP BY level
                ORDER BY level
                """
            ).fetchall()
            lp_conn.close()
            for level_key, count in rows:
                level_str = str(level_key or "").strip().upper()
                if not level_str.startswith("HSK"):
                    continue
                try:
                    level_num = int(level_str.replace("HSK", ""))
                except ValueError:
                    continue
                label = "HSK 7-9" if level_num == 7 else f"HSK {level_num}"
                groups.append(
                    {
                        "level": level_num,
                        "count": int(count or 0),
                        "label": label,
                        "description": f"{int(count or 0)} words",
                    }
                )
        else:
            conn = DB._get_conn()
            rows = conn.execute(
                """
                SELECT level, COUNT(*) AS cnt
                FROM concepts
                WHERE target_lang = ?
                GROUP BY level
                ORDER BY level
                """,
                (target_lang,),
            ).fetchall()
            conn.close()
            for level_num, count in rows:
                groups.append(
                    {
                        "level": int(level_num),
                        "count": int(count or 0),
                        "label": f"L{int(level_num)}",
                        "description": f"{int(count or 0)} words",
                    }
                )
        
        response = {"groups": groups}
        CACHE.set(cache_key, response)
        return response
        
    except Exception as e:
        print(f"Error in get_vocabulary_stats: {e}")
        # Return fallback if error
        return {"groups": []}


@router.get("/with-images")
async def get_vocabulary_with_images(
    target_lang: str = Query(..., description="Target language code"),
    source_lang: str = Query("en", description="Source/native language"),
    level: Optional[int] = Query(None, ge=1, le=9, description="Level (1-9)"),
    limit: int = Query(20, ge=5, le=50, description="Number of words"),
    client_id: str = Depends(verify_api_key),
    user_id: str = Depends(check_user_rate_limit)
):
    """
    Get vocabulary words that specifically have images.
    """
    try:
        normalized_level = _normalize_hsk_level(level)
        conn = DB._get_conn()
        
        query = """
            SELECT 
                c.id, c.semantic_key, c.word, c.pronunciation, c.pos, c.context_sentence, c.level, c.image_url,
                t.translation, t.context_translation
            FROM concepts c
            LEFT JOIN translations t ON c.id = t.concept_id AND t.native_lang = ?
            WHERE c.target_lang = ? AND c.image_url IS NOT NULL AND c.image_url != ''
        """
        params = [source_lang, target_lang]
        
        if normalized_level and normalized_level <= 6:
            query += " AND c.level = ?"
            params.append(normalized_level)
            
        query += " ORDER BY RANDOM() LIMIT ?"
        params.append(limit)
        
        cursor = conn.execute(query, params)
        words = [dict(row) for row in cursor.fetchall()]
        conn.close()
        _normalize_rows_image_urls(words)

        return {
            "target_lang": target_lang,
            "source_lang": source_lang,
            "level": normalized_level,
            "vocabulary": words
        }
    except Exception as e:
        print(f"Error in get_vocabulary_with_images: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/{concept_id}")
async def get_concept_details(concept_id: int):
    """
    Get full details for a specific concept.
    """
    cache_key = f"concept_v2:{concept_id}"
    cached = CACHE.get(cache_key)
    if cached is not None:
        return cached
    
    try:
        concept = DB.get_concept_details(concept_id)
        if not concept:
            raise HTTPException(status_code=404, detail="Concept not found")
            
        CACHE.set(cache_key, concept)
        return concept
        
    except Exception as e:
        print(f"Error in get_concept_details: {e}")
        raise HTTPException(status_code=500, detail=str(e))
