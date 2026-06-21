import re
import uuid
import math
import mimetypes
import asyncio
from pathlib import Path
from typing import List, Optional, Tuple
from fastapi import UploadFile, HTTPException
from starlette.concurrency import run_in_threadpool

# Import shared models/services
from api.v2.schemas import APIStudySet, UsageEstimate
from services.ai_engine import run_chat_completion

# Helper for token estimation (simplified)
def estimate_tokens(text: str) -> int:
    return len(text) // 4

def stardust_from_tokens(tokens: int) -> int:
    return math.ceil(tokens / 100)

def chunk_text(text: str, chunk_size: int = 2000) -> List[str]:
    return [text[i:i+chunk_size] for i in range(0, len(text), chunk_size)]

def depth_prompt_snippet(depth: Optional[str]) -> str:
    if not depth:
        return ""
    if depth == "deep":
        return "Provide detailed, in-depth explanations suitable for advanced learners."
    if depth == "simple":
        return "Use simple language and analogies suitable for beginners."
    return ""

async def generate_condensed_notes_html(
    content: str,
    source_type: str,
    depth: Optional[str],
    ai_provider: Optional[str] = None,
    allow_fallback: bool = True,
) -> str:
    depth_style = depth_prompt_snippet(depth)
    prompt = (
        "You are a study assistant that produces concise, reader-friendly HTML notes. "
        "Return HTML with:\n"
        "- <h2>Title (1 emoji) and a <span> depth label.\n"
        "- <p> one-line summary.\n"
        "- <h3>Overview</h3><ul> 8-12 bullets; each bullet 1–2 sentences; use emojis.\n"
        "- <h3>Key Terms</h3><ul> 4-6 bullets with definitions.\n"
        "- <h3>Examples</h3><ul> 3 concise examples.\n"
        "- <h3>Takeaways</h3><ul> 3-5 bullets.\n"
        "If content includes lines like 'Image 1: ...', insert "
        "<figure data-image=\"1\"><figcaption>Image 1: ...</figcaption></figure> near the relevant bullet. "
        "Do not include <img> tags. "
        "Keep HTML minimal (no CSS), avoid markdown."
    )
    messages = [
        {"role": "system", "content": prompt},
        {
            "role": "user",
            "content": f"Source type: {source_type}\n{depth_style}\nContent:\n{content}",
        },
    ]

    try:
        return await run_in_threadpool(
            run_chat_completion,
            messages=messages,
            temperature=0.3,
            ai_provider=ai_provider,
            max_tokens=2000,
            allow_fallback=allow_fallback,
        )
    except Exception as e:
        return f"<p>Error producing notes: {e}</p>"

async def build_study_set_from_text(
    content: str,
    source_type: str,
    depth: Optional[str],
    title_hint: Optional[str] = None,
    image_paths: Optional[List[Path]] = None,
    include_image_captions: bool = False,
    ai_provider: Optional[str] = None,
    allow_fallback: bool = True,
) -> Tuple[APIStudySet, UsageEstimate]:
    
    content_with_images = content.strip()
    # (Image captioning logic omitted for brevity in this refactor step)
    
    condensed_html = await generate_condensed_notes_html(
        content_with_images,
        source_type,
        depth,
        ai_provider=ai_provider,
        allow_fallback=allow_fallback,
    )

    title_source = (title_hint or content_with_images or "Study Set").strip()
    title = title_source[:40] + "..." if len(title_source) > 40 else title_source[:40]

    tokens_in = estimate_tokens(content_with_images)
    tokens_out = estimate_tokens(condensed_html)
    tokens_total = tokens_in + tokens_out
    
    usage = UsageEstimate(
        tokens_in=tokens_in,
        tokens_out=tokens_out,
        tokens_total=tokens_total,
        stardust=stardust_from_tokens(tokens_total),
    )
    
    study_set = APIStudySet(
        id=str(uuid.uuid4()),
        title=title or "Study Set",
        condensed_notes_html=condensed_html,
        full_text_chunks=chunk_text(content_with_images),
        depth=depth,
        image_urls=[], # Image URL handling needs separate service
        image_captions=[],
    )
    
    # Note: caller is responsible for saving study_set
    return study_set, usage

async def extract_text_and_images_from_upload(
    file: UploadFile,
    source_type: str,
    max_images: int,
) -> Tuple[str, List[Path]]:
    content_type = (file.content_type or "").lower()
    filename = (file.filename or "").lower()
    raw_bytes = await file.read()
    
    # Placeholder for actual extraction logic which requires other dependencies like PyPDF2
    # For refactoring purposes, we'll return simple text
    return f"Extracted content from {filename}", []
