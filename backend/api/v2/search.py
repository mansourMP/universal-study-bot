"""
search.py - v2 Unified Search API

Endpoints:
- GET /api/v2/search - Search across vocabulary and content
"""

from fastapi import APIRouter, Query, HTTPException, Depends
from typing import Optional, List
import sqlite3
import re
from pathlib import Path

from cache_manager_v2 import CACHE

router = APIRouter(prefix="/api/v2/search", tags=["search"])

DB_PATH = Path(__file__).parent.parent.parent / "vocabulary_v2.db"


def get_db() -> sqlite3.Connection:
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    return conn


def validate_query(q: str) -> str:
    """Validate and sanitize search query"""
    # Remove dangerous regex patterns
    if re.search(r'[.*+?^${}()|[\]\\]', q):
        raise HTTPException(400, "Invalid query: special characters not allowed")
    
    # Trim and limit length
    q = q.strip()[:100]
    
    if len(q) < 1:
        raise HTTPException(400, "Query too short")
    
    return q


from auth import verify_api_key, check_user_rate_limit

@router.get("")
async def search(
    q: str = Query(..., min_length=1, max_length=100, description="Search query"),
    target_lang: Optional[str] = Query(None, description="Filter by target language"),
    types: Optional[str] = Query(None, description="Comma-separated: vocab,article,video"),
    level: Optional[int] = Query(None, ge=1, le=6),
    limit: int = Query(20, ge=1, le=50),
    client_id: str = Depends(verify_api_key),
    user_id: str = Depends(check_user_rate_limit)
):
    """
    Unified search across vocabulary and content.
    
    Returns matching vocabulary items and content items.
    """
    q = validate_query(q)
    
    # Parse types
    search_types = set(types.split(",")) if types else {"vocab", "article", "video"}
    
    # Cache key
    cache_key = f"search:{q}:{target_lang}:{types}:{level}:{limit}"
    cached = CACHE.get(cache_key)
    if cached is not None:
        return cached
    
    conn = get_db()
    results = {"query": q, "vocabulary": [], "content": []}
    
    try:
        # Search vocabulary
        if "vocab" in search_types:
            vocab_params = [f"%{q}%", f"%{q}%"]
            vocab_query = """
                SELECT DISTINCT
                    c.id as concept_id,
                    l.headword,
                    l.pronunciation,
                    l.level,
                    l.language,
                    g.gloss,
                    CASE 
                        WHEN l.headword = ? THEN 'exact'
                        WHEN l.headword LIKE ? THEN 'prefix'
                        ELSE 'contains'
                    END as match_type
                FROM lexemes l
                JOIN concepts c ON l.concept_id = c.id
                LEFT JOIN glosses g ON l.id = g.lexeme_id AND g.language = 'en'
                WHERE (l.headword LIKE ? OR g.gloss LIKE ?)
            """
            vocab_params = [q, f"{q}%", f"%{q}%", f"%{q}%"]
            
            if target_lang:
                vocab_query += " AND l.language = ?"
                vocab_params.append(target_lang)
            
            if level:
                vocab_query += " AND l.level = ?"
                vocab_params.append(level)
            
            vocab_query += """
                ORDER BY 
                    CASE WHEN l.headword = ? THEN 0 ELSE 1 END,
                    l.level,
                    l.headword
                LIMIT ?
            """
            vocab_params.extend([q, limit])
            
            vocab_rows = conn.execute(vocab_query, vocab_params).fetchall()
            
            for row in vocab_rows:
                results["vocabulary"].append({
                    "concept_id": row["concept_id"],
                    "headword": row["headword"],
                    "pronunciation": row["pronunciation"],
                    "gloss": row["gloss"],
                    "level": row["level"],
                    "language": row["language"],
                    "match_type": row["match_type"],
                })
        
        # Search content
        content_types = search_types - {"vocab"}
        if content_types:
            type_placeholders = ",".join("?" * len(content_types))
            content_query = f"""
                SELECT id, type, title, description, difficulty, 
                       primary_lang, thumbnail_url
                FROM content
                WHERE is_published = 1
                AND (title LIKE ? OR description LIKE ?)
                AND type IN ({type_placeholders})
            """
            content_params = [f"%{q}%", f"%{q}%"] + list(content_types)
            
            if target_lang:
                content_query += " AND primary_lang = ?"
                content_params.append(target_lang)
            
            if level:
                content_query += " AND level = ?"
                content_params.append(level)
            
            content_query += " ORDER BY created_at DESC LIMIT ?"
            content_params.append(limit)
            
            content_rows = conn.execute(content_query, content_params).fetchall()
            
            for row in content_rows:
                results["content"].append({
                    "id": row["id"],
                    "type": row["type"],
                    "title": row["title"],
                    "description": row["description"][:100] if row["description"] else None,
                    "difficulty": row["difficulty"],
                    "primary_lang": row["primary_lang"],
                    "thumbnail_url": row["thumbnail_url"],
                })
        
        # Cache results
        CACHE.set(cache_key, results)
        
        return results
        
    finally:
        conn.close()
