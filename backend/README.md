# 🚀 Know AI - n8n Content Integration Guide

## Quick Start

### 1. Start Backend
```bash
cd /Users/mansur/universal_study_bot\ org/backend
./start_backend.sh
```
**Keep this running!** Backend serves on port 8000.

### 2. Connect n8n
**Webhook URL**: `http://localhost:8000/webhook/content/create`

**Example POST Body**:
```json
{
  "title": "Your Article Title",
  "excerpt": "Short description",
  "content": [
    {
      "heading": "Section 1",
      "paragraphs": ["Paragraph 1", "Paragraph 2"]
    }
  ],
  "category": "Technology",
  "difficulty": "intermediate",
  "tags": ["tag1", "tag2"]
}
```

### 3. View in iOS
1. Run Know AI app
2. Tap Explore tab
3. See your content!

---

## Webhook API

### POST /webhook/content/create
Create new article from n8n.

**Required Fields**:
- `title` (string)
- `excerpt` (string)
- `content` (array of sections)

**Optional Fields**:
- `subtitle`, `category`, `difficulty`, `tags`, `language`, `thumbnail_url`

**Response**:
```json
{
  "success": true,
  "article_id": "en_technology_abc123",
  "message": "Content created successfully"
}
```

### GET /webhook/status
Check webhook is working.

### GET /webhook/test
Create test article.

---

## Alternative: AI Content Generation

If you want to generate content locally (without n8n):

```bash
source venv/bin/activate

# Generate 5 science articles
python ai_content_pipeline.py --template science --model deepseek --no-images

# Generate custom topic
python ai_content_pipeline.py --topics "Your topic" --model deepseek --no-images

# Available templates: science, business, technology, psychology, learning, history
```

---

## Testing

### Test webhook status:
```bash
curl http://localhost:8000/webhook/status
```

### Test content creation:
```bash
curl -X POST http://localhost:8000/webhook/content/create \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Test Article",
    "excerpt": "Testing webhook",
    "content": [{"heading": "Test", "paragraphs": ["Test content"]}],
    "category": "Technology"
  }'
```

### Check existing content:
```bash
curl http://localhost:8000/api/v2/content?limit=5
```

---

## Files Overview

**Essential Code**:
- `main.py` - Backend server
- `api/webhook_n8n.py` - n8n webhooks
- `ai_content_pipeline.py` - AI generation (optional)
- `content_config.py` - Configuration

**Scripts**:
- `start_backend.sh` - Start server
- `setup_ai_pipeline.sh` - Setup AI pipeline

**Data**:
- `vocabulary.db` - Content database
- `content/explore/articles/` - Article JSON files
- `content/explore/images/` - Thumbnails

---

## Content Flow

```
n8n → POST /webhook/content/create → Backend saves → iOS app displays
```

Simple and clean! 🎉

---

## Tips

1. **Remote access**: Use ngrok for testing outside localhost
   ```bash
   ngrok http 8000
   ```

2. **Generate with AI**: Use content pipeline for bulk generation
   
3. **Database check**: 
   ```bash
   sqlite3 vocabulary.db "SELECT id, title FROM content LIMIT 5;"
   ```

---

## Troubleshooting

**Backend won't start?**
```bash
source venv/bin/activate
pip install -r requirements_ai.txt
```

**Connection refused?**
Make sure backend is running: `./start_backend.sh`

**Content not showing in iOS?**
1. Check backend: `curl http://localhost:8000/webhook/status`
2. Check database: `ls content/explore/articles/`
3. Restart iOS app

---

## Summary

✅ Backend on port 8000  
✅ n8n webhook ready  
✅ iOS Explore/Feed tabs ready  
✅ 14 articles in database  

**Everything you need!** 🚀
