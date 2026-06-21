"""
n8n Webhook Integration for Know AI
====================================

Simple webhook endpoints that accept content from n8n workflows.

Your n8n workflow can POST content here, and it will automatically:
1. Save to database
2. Create JSON file
3. Appear in iOS Explore/Feed tabs

Endpoints:
- POST /webhook/content/create - Create new article
- POST /webhook/content/publish - Publish existing draft
- POST /webhook/content/update - Update article
- GET /webhook/status - Check webhook is working
"""

from fastapi import APIRouter, HTTPException, BackgroundTasks
from pydantic import BaseModel
from typing import Optional, List
import sqlite3
import json
import uuid
from datetime import datetime
from pathlib import Path

router = APIRouter(prefix="/webhook", tags=["n8n-webhooks"])

# Paths
BASE_DIR = Path(__file__).parent.parent
CONTENT_DIR = BASE_DIR / "content" / "explore"
ARTICLES_DIR = CONTENT_DIR / "articles"
DB_PATH = BASE_DIR / "vocabulary_v2.db"

# Ensure directories
ARTICLES_DIR.mkdir(parents=True, exist_ok=True)


class ContentCreate(BaseModel):
    """Model for creating content from n8n"""
    title: str
    type: str = "article"  # article, video, feed_post
    subtitle: Optional[str] = ""
    excerpt: str
    content: List[dict]  # Array of {heading, paragraphs}
    category: str = "Education"
    difficulty: str = "intermediate"
    tags: Optional[List[str]] = []
    language: str = "en"
    thumbnail_url: Optional[str] = None
    media_urls: Optional[List[str]] = [] # For video URLs or slide images
    is_trending: bool = False
    is_featured: bool = False


@router.post("/content/create")
async def create_content_from_n8n(data: ContentCreate, background_tasks: BackgroundTasks):
    """
    Create content from n8n workflow
    """
    
    try:
        # Normalize type
        content_type = data.type.lower()
        if content_type == "feed": content_type = "feed_post"
        
        # Generate ID
        article_id = f"{data.language}_{content_type}_{data.category.lower()}_{uuid.uuid4().hex[:8]}"
        
        # Calculate reading time
        reading_time = 5 # Default
        if data.content:
            total_words = sum(len(" ".join(section.get("paragraphs", [])).split()) 
                            for section in data.content)
            reading_time = max(1, total_words // 200)
        
        # Create full structure
        article = {
            "id": article_id,
            "type": content_type,
            "title": data.title,
            "subtitle": data.subtitle,
            "excerpt": data.excerpt,
            "reading_time": f"{reading_time} min read",
            "tags": data.tags,
            "sections": data.content,
            "primary_lang": data.language,
            "category": data.category,
            "difficulty": data.difficulty,
            "level": {"beginner": 2, "intermediate": 3, "advanced": 5}.get(data.difficulty, 3),
            "thumbnail_url": data.thumbnail_url,
            "media_urls": data.media_urls,
            "created_at": datetime.now().isoformat()
        }
        
        # Save to file
        file_path = ARTICLES_DIR / f"{article_id}.json"
        with open(file_path, "w", encoding="utf-8") as f:
            json.dump(article, f, indent=2, ensure_ascii=False)
        
        # Save to database
        conn = sqlite3.connect(DB_PATH)
        conn.execute("""
            INSERT INTO content (
                id, type, primary_lang, title, description, category,
                difficulty, level, tags, thumbnail_url, media_urls, content_path,
                is_published, is_trending, is_new, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            article_id, content_type, data.language, data.title, data.excerpt,
            data.category, data.difficulty, article["level"],
            json.dumps(data.tags), data.thumbnail_url, json.dumps(data.media_urls),
            f"/content/explore/articles/{article_id}.json",
            True, data.is_trending, True, datetime.now().isoformat()
        ))
        conn.commit()
        conn.close()
        
        return {
            "success": True,
            "article_id": article_id,
            "message": "Content created successfully",
            "file_path": str(file_path),
            "view_url": f"/content/explore/articles/{article_id}.json"
        }
        
    except Exception as e:
        raise HTTPException(500, f"Error creating content: {str(e)}")


@router.post("/content/update/{article_id}")
async def update_content_from_n8n(article_id: str, data: ContentCreate):
    """
    Update existing article from n8n
    
    Example n8n usage:
    URL: http://your-backend:8000/webhook/content/update/en_tech_abc123
    Method: POST
    Body: (same as create)
    """
    
    try:
        # Update file
        file_path = ARTICLES_DIR / f"{article_id}.json"
        
        if not file_path.exists():
            raise HTTPException(404, "Article not found")
        
        # Read existing
        with open(file_path, "r") as f:
            article = json.load(f)
        
        # Update fields
        article.update({
            "title": data.title,
            "subtitle": data.subtitle,
            "excerpt": data.excerpt,
            "sections": data.content,
            "category": data.category,
            "tags": data.tags,
            "thumbnail_url": data.thumbnail_url,
            "updated_at": datetime.now().isoformat()
        })
        
        # Save
        with open(file_path, "w", encoding="utf-8") as f:
            json.dump(article, f, indent=2, ensure_ascii=False)
        
        # Update database
        conn = sqlite3.connect(DB_PATH)
        conn.execute("""
            UPDATE content SET
                title = ?, description = ?, category = ?,
                tags = ?, thumbnail_url = ?, updated_at = ?
            WHERE id = ?
        """, (
            data.title, data.excerpt, data.category,
            json.dumps(data.tags), data.thumbnail_url,
            datetime.now().isoformat(), article_id
        ))
        conn.commit()
        conn.close()
        
        return {
            "success": True,
            "article_id": article_id,
            "message": "Content updated successfully"
        }
        
    except Exception as e:
        raise HTTPException(500, f"Error updating content: {str(e)}")


@router.get("/status")
async def webhook_status():
    """Check if webhook is working"""
    return {
        "status": "online",
        "webhook_url": "/webhook/content/create",
        "message": "n8n webhook integration is ready",
        "timestamp": datetime.now().isoformat()
    }


@router.get("/test")
async def test_webhook():
    """
    Test endpoint - create sample content
    Call this from n8n to test the connection
    """
    sample_data = ContentCreate(
        title="Test Article from n8n",
        excerpt="This is a test article created via webhook",
        content=[
            {
                "heading": "Test Section",
                "paragraphs": [
                    "This article was created by calling the webhook endpoint.",
                    "If you see this in your iOS app, the integration is working!"
                ]
            }
        ],
        category="Technology",
        tags=["test", "webhook", "n8n"]
    )
    
    result = await create_content_from_n8n(sample_data, BackgroundTasks())
    return result
