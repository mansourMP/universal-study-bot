"""
content.py - v2 Content API endpoints (Explore mode)

Endpoints:
- GET /api/v2/content - Content feed with filtering
- GET /api/v2/content/{content_id} - Content details
- GET /api/v2/transcript/{content_id} - Transcript with segments
"""

from fastapi import APIRouter, Query, HTTPException, Path
from typing import Optional, List
import sqlite3
import json
from pathlib import Path as PathLib

from cache_manager_v2 import CACHE

router = APIRouter(tags=["content"])

DB_PATH = PathLib(__file__).parent.parent.parent / "vocabulary_v2.db"


def get_db() -> sqlite3.Connection:
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    return conn


def _get_content_columns(conn: sqlite3.Connection) -> set[str]:
    rows = conn.execute("PRAGMA table_info(content);").fetchall()
    return {row[1] for row in rows}


from auth import verify_api_key, check_user_rate_limit
from fastapi import Depends

@router.get("/api/v2/content")
async def get_content_feed(
    type: Optional[str] = Query(None, description="Filter by type: article, video, audio"),
    lang: Optional[str] = Query(None, description="Filter by primary language"),
    level: Optional[int] = Query(None, ge=1, le=6),
    category: Optional[str] = Query(None),
    tags: Optional[str] = Query(None, description="Comma-separated tags"),
    trending: Optional[bool] = Query(None),
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0, le=10000),
    # Temporarily disabled auth for iOS app testing
    # client_id: str = Depends(verify_api_key),
    # user_id: str = Depends(check_user_rate_limit)
):
    """
    Get content feed with filtering and pagination.
    
    Returns articles, videos, and audio content for the Explore mode.
    """
    cache_key = f"feed:{type}:{lang}:{level}:{category}:{tags}:{trending}:{limit}:{offset}"
    cached = CACHE.get(cache_key)
    if cached is not None:
        return cached
    
    conn = get_db()
    try:
        columns = _get_content_columns(conn)
        def _col(name: str, default_sql: str) -> str:
            return name if name in columns else f"{default_sql} AS {name}"

        params = []
        query = """
            SELECT 
                id, type, title, description, author,
                thumbnail_url, difficulty, level, category,
                {reading_time_minutes}, {duration_seconds},
                {is_premium}, {is_trending}, {is_new}, created_at
            FROM content
            WHERE is_published = 1
        """.format(
            reading_time_minutes=_col("reading_time_minutes", "NULL"),
            duration_seconds=_col("duration_seconds", "NULL"),
            is_premium=_col("is_premium", "0"),
            is_trending=_col("is_trending", "0"),
            is_new=_col("is_new", "0"),
        )
        
        if type:
            query += " AND type = ?"
            params.append(type)
        
        if lang:
            query += " AND primary_lang = ?"
            params.append(lang)
        
        if level:
            query += " AND level = ?"
            params.append(level)
        
        if category:
            query += " AND category = ?"
            params.append(category)
        
        if tags:
            # Simple tag search (JSON array contains)
            for tag in tags.split(","):
                query += " AND tags LIKE ?"
                params.append(f'%"{tag.strip()}"%')
        
        if trending and "is_trending" in columns:
            query += " AND is_trending = 1"
        
        # Get total
        count_query = f"SELECT COUNT(*) FROM ({query})"
        total = conn.execute(count_query, params).fetchone()[0]
        
        # Add ordering and pagination
        query += " ORDER BY is_trending DESC, created_at DESC LIMIT ? OFFSET ?"
        params.extend([limit, offset])
        
        rows = conn.execute(query, params).fetchall()
        
        items = []
        for row in rows:
            items.append({
                "id": row["id"],
                "type": row["type"],
                "title": row["title"],
                "description": row["description"][:200] if row["description"] else None,
                "author": row["author"],
                "thumbnail_url": row["thumbnail_url"],
                "difficulty": row["difficulty"],
                "level": row["level"],
                "category": row["category"],
                "reading_time_minutes": row["reading_time_minutes"],
                "duration_seconds": row["duration_seconds"],
                "is_premium": bool(row["is_premium"]),
                "is_trending": bool(row["is_trending"]),
                "is_new": bool(row["is_new"]),
                "created_at": row["created_at"],
            })
        
        response = {
            "total": total,
            "limit": limit,
            "offset": offset,
            "items": items,
            "next_offset": offset + limit if offset + limit < total else None,
        }
        
        CACHE.set(cache_key, response)
        return response
        
    finally:
        conn.close()


@router.get("/api/v2/content/{content_id}")
async def get_content_details(
    content_id: str = Path(...),
    # Temporarily disabled auth for iOS app testing
    # client_id: str = Depends(verify_api_key),
    # user_id: str = Depends(check_user_rate_limit)
):
    """
    Get full content details including linked vocabulary.
    """
    cache_key = f"content:{content_id}"
    cached = CACHE.get(cache_key)
    if cached is not None:
        return cached
    
    conn = get_db()
    try:
        row = conn.execute(
            "SELECT * FROM content WHERE id = ?", (content_id,)
        ).fetchone()
        
        if not row:
            raise HTTPException(404, "Content not found")
        
        # Get linked concepts (only if v2 vocab tables exist)
        linked_concepts = []
        tables = {t[0] for t in conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()}
        if {"lexemes", "glosses", "concepts", "content_concept_links"}.issubset(tables):
            concept_rows = conn.execute("""
                SELECT c.id, l.headword, l.pronunciation, l.level, g.gloss
                FROM content_concept_links ccl
                JOIN concepts c ON ccl.concept_id = c.id
                JOIN lexemes l ON l.concept_id = c.id
                LEFT JOIN glosses g ON l.id = g.lexeme_id AND g.language = 'en'
                WHERE ccl.content_id = ?
                LIMIT 50
            """, (content_id,)).fetchall()

            for c in concept_rows:
                linked_concepts.append({
                    "concept_id": c["id"],
                    "headword": c["headword"],
                    "pronunciation": c["pronunciation"],
                    "level": c["level"],
                    "gloss": c["gloss"],
                })
        
        row_dict = dict(row)
        def _get(name: str, default=None):
            return row_dict.get(name, default)

        response = {
            "id": _get("id"),
            "type": _get("type"),
            "source_type": _get("source_type"),
            "title": _get("title"),
            "description": _get("description"),
            "author": _get("author"),
            "source_url": _get("source_url"),
            "thumbnail_url": _get("thumbnail_url"),
            "difficulty": _get("difficulty"),
            "level": _get("level"),
            "category": _get("category"),
            "tags": json.loads(_get("tags") or "[]"),
            "reading_time_minutes": _get("reading_time_minutes"),
            "word_count": _get("word_count"),
            "duration_seconds": _get("duration_seconds"),
            "is_premium": bool(_get("is_premium", 0)),
            "media_urls": json.loads(_get("media_urls") or "[]"),
            "content_path": _get("content_path"),
            "linked_concepts": linked_concepts,
            "created_at": _get("created_at"),
            "updated_at": _get("updated_at"),
        }

        # Try to read content from file
        if row["content_path"]:
            try:
                # Handle relative paths properly
                content_path = row["content_path"]
                if content_path.startswith("/"):
                    content_path = content_path.lstrip("/")
                
                # Construct absolute path relative to backend root
                # Assuming api/v2/content.py is running from backend root context
                # We need to find the backend root. Since we are in api/v2/content.py
                # content_path like 'content/explore/articles/...' should work if CWD is backend
                
                # Try to find the file
                import os
                real_path = os.path.abspath(content_path)
                
                if os.path.exists(real_path):
                    with open(real_path, 'r', encoding='utf-8') as f:
                        file_data = json.load(f)
                        # Merge file data into response
                        response.update(file_data)
                        # Ensure we don't overwrite the DB ID if it's different (shouldn't be)
                        response["id"] = row["id"]
                else:
                     print(f"Warning: Content file not found at {real_path}")
                     # Try alternative path relative to current file if CWD is wrong
                     base_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
                     alt_path = os.path.join(base_dir, content_path)
                     if os.path.exists(alt_path):
                         with open(alt_path, 'r', encoding='utf-8') as f:
                             file_data = json.load(f)
                             response.update(file_data)
                             response["id"] = row["id"]
                     else:
                         print(f"Warning: Content file not found at {alt_path}")

            except Exception as e:
                print(f"Error reading content file: {e}")
                # Don't fail request, just return what we have
                pass

        # FIX: Ensure types match iOS expectations (ExploreReading.swift)
        # 1. iOS expects 'level' to be a String
        if "level" in response and response["level"] is not None:
            response["level"] = str(response["level"])
        else:
            response["level"] = "General" # Fallback
            
        # 2. iOS expects 'reading_time' (String), DB has 'reading_time_minutes' (Int)
        if "reading_time" not in response or not response["reading_time"]:
            mins = response.get("reading_time_minutes", 5)
            response["reading_time"] = f"{mins} min read"
        
        CACHE.set(cache_key, response)
        return response
        
    finally:
        conn.close()


@router.get("/api/v2/transcript/{content_id}")
async def get_transcript(
    content_id: str = Path(...),
    lang: Optional[str] = Query(None, description="Transcript language"),
    client_id: str = Depends(verify_api_key),
    user_id: str = Depends(check_user_rate_limit)
):
    """
    Get transcript with time-coded segments for video/audio content.
    """
    cache_key = f"transcript:{content_id}:{lang}"
    cached = CACHE.get(cache_key)
    if cached is not None:
        return cached
    
    conn = get_db()
    try:
        # Get transcript
        if lang:
            transcript = conn.execute("""
                SELECT * FROM transcripts WHERE content_id = ? AND lang = ?
            """, (content_id, lang)).fetchone()
        else:
            transcript = conn.execute("""
                SELECT * FROM transcripts WHERE content_id = ? LIMIT 1
            """, (content_id,)).fetchone()
        
        if not transcript:
            raise HTTPException(404, "Transcript not found")
        
        # Get segments
        segments = conn.execute("""
            SELECT start_ms, end_ms, text, speaker
            FROM transcript_segments
            WHERE transcript_id = ?
            ORDER BY start_ms
        """, (transcript["id"],)).fetchall()
        
        response = {
            "content_id": content_id,
            "lang": transcript["lang"],
            "full_text": transcript["full_text"],
            "segments": [
                {
                    "start_ms": s["start_ms"],
                    "end_ms": s["end_ms"],
                    "text": s["text"],
                    "speaker": s["speaker"],
                }
                for s in segments
            ],
        }
        
        CACHE.set(cache_key, response)
        return response
        
    finally:
        conn.close()
