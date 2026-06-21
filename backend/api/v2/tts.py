"""
tts.py - On-Demand Text-to-Speech API
Generates high-quality audio for vocabulary words using OpenAI.
"""

from fastapi import APIRouter, HTTPException, Depends
from fastapi.responses import FileResponse
from pathlib import Path
import os
import sqlite3
from openai import OpenAI
from dotenv import load_dotenv
import json
from typing import Optional

# Load env
load_dotenv(Path(__file__).parent.parent.parent / ".env")

# Initialize Router
router = APIRouter(prefix="/api/v2/audio", tags=["audio"])

# Configuration
STATIC_DIR = Path(__file__).parent.parent.parent / "static" / "audio"
DB_PATH = Path(__file__).parent.parent.parent / "vocabulary_v2.db"
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
MAP_PATH = Path(__file__).parent.parent.parent / "content" / "audio_map.json"

def _load_audio_map():
    if MAP_PATH.exists():
        try:
            data = json.loads(MAP_PATH.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                return {str(k): str(v) for k, v in data.items()}
        except Exception:
            return {}
    return {}

# Initialize OpenAI
client = None
if OPENAI_API_KEY:
    client = OpenAI(api_key=OPENAI_API_KEY)

def get_db():
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    return conn


def _normalize_concept_id(raw_id: str) -> tuple[str, Optional[int]]:
    """Normalize concept ids like `123` and `W00123`."""
    cid = str(raw_id).strip()
    if not cid:
        return "", None
    if cid.isdigit():
        return cid, int(cid)
    if cid.startswith("W") and cid[1:].isdigit():
        return cid, int(cid[1:])
    return cid, None

@router.get("/{concept_id}")
async def get_word_audio(concept_id: str):
    """
    Get or generate audio for a specific concept.
    """
    # 0) Serve explicit mapping override if present
    normalized_id, numeric_id = _normalize_concept_id(concept_id)
    if not normalized_id:
        raise HTTPException(status_code=400, detail="Invalid concept_id")

    audio_map = _load_audio_map()
    mapped = audio_map.get(normalized_id)
    if not mapped and numeric_id is not None:
        mapped = audio_map.get(str(numeric_id))
    if mapped:
        file_path = Path(mapped)
        if not file_path.is_absolute():
            file_path = Path(__file__).parent.parent.parent / mapped.lstrip("/")
        if file_path.exists():
            return FileResponse(file_path, media_type="audio/mpeg")

    # 1) Serve local static pack if present
    static_candidates = [STATIC_DIR / f"word_{normalized_id}.mp3"]
    if numeric_id is not None:
        static_candidates.append(STATIC_DIR / f"word_{numeric_id}.mp3")
    for static_path in static_candidates:
        if static_path.exists():
            return FileResponse(static_path, media_type="audio/mpeg")

    conn = get_db()
    try:
        # 1. Check DB for existing audio
        row = None
        if numeric_id is not None:
            row = conn.execute(
                "SELECT word, audio_url FROM concepts WHERE id = ?",
                (numeric_id,),
            ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Word not found")
        
        word = row["word"]
        existing_url = row["audio_url"]

        # 2. Return existing file if valid
        if existing_url:
            # existing_url might be "static/audio/word_123.mp3"
            file_path = Path(existing_url)
            # If path is relative to backend root, resolve it
            if not file_path.exists():
                # Try finding it in the static dir directly
                filename = Path(existing_url).name
                file_path = STATIC_DIR / filename
            
            if file_path.exists():
                return FileResponse(file_path, media_type="audio/mpeg")

        # 3. Generate New Audio (if not found)
        if not client:
            raise HTTPException(status_code=404, detail="Audio not available locally (no API key)")

        print(f"🎤 Generating audio for: {word}")
        
        filename = f"word_{numeric_id if numeric_id is not None else normalized_id}.mp3"
        save_path = STATIC_DIR / filename
        
        # Call OpenAI TTS
        response = client.audio.speech.create(
            model="tts-1",
            voice="alloy",
            input=word
        )
        
        # Save to disk
        response.stream_to_file(save_path)
        
        # Update Database
        # We store the relative path or URL path
        web_path = f"static/audio/{filename}"
        if numeric_id is not None:
            conn.execute("UPDATE concepts SET audio_url = ? WHERE id = ?", (web_path, numeric_id))
            conn.commit()
        
        return FileResponse(save_path, media_type="audio/mpeg")

    except Exception as e:
        print(f"TTS Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        conn.close()
