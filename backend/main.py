import json
import re
import os
import math
import uuid
import asyncio
import sqlite3
from datetime import datetime, timedelta, timezone
import inspect
from functools import lru_cache
from typing import List, Optional, Any, Dict, Union, Iterator, Type, Tuple
import pathlib
import subprocess
import base64
import tempfile
from pathlib import Path
import time
import io
import mimetypes
import zipfile
import xml.etree.ElementTree as ET
import hashlib
import shutil

from enum import Enum
from PIL import Image

from dotenv import load_dotenv

# Load environment variables BEFORE importing other modules that might rely on them
load_dotenv(dotenv_path=Path(__file__).with_name(".env"))

from fastapi import BackgroundTasks, Depends, FastAPI, File, Form, HTTPException, UploadFile, Request, Response, Query, Body
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from openai import OpenAI, OpenAIError
from pydantic import BaseModel, Field
from starlette.concurrency import run_in_threadpool
from fastapi.staticfiles import StaticFiles
from youtube_transcript_api import NoTranscriptFound, YouTubeTranscriptApi
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from PyPDF2 import PdfReader
from ai_guard import (
    ai_guard_dependency,
    init_ai_guard,
    init_ai_guard_ledger,
    read_quota,
    record_ai_usage,
)

from fastapi.middleware.gzip import GZipMiddleware
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from auth import verify_api_key, get_user_id

from cache_manager import SmartCache



from db_v2 import DatabaseV2

# --- Configuration ---
limiter = Limiter(key_func=get_remote_address)
DB_V2 = DatabaseV2(str(Path(__file__).with_name("vocabulary_v2.db")))
GLOBAL_CACHE = SmartCache(ttl=300, max_size=2000)











OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")


OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
ENABLE_WHISPER_FALLBACK = os.getenv("ENABLE_WHISPER_FALLBACK", "false").lower() == "true"

try:
    openai_client = OpenAI(api_key=OPENAI_API_KEY) if OPENAI_API_KEY else None
    if openai_client:
        print(f"OpenAI client initialized: {OPENAI_API_KEY[:7]}...")
    else:
        print("OpenAI client NOT initialized (API key missing).")
except Exception as e:
    openai_client = None
    print(f"OpenAI client initialization failed: {e}")
OPENAI_ENABLED = openai_client is not None

DEEPSEEK_MODEL = os.getenv("DEEPSEEK_MODEL", "deepseek-reasoner")
DEEPSEEK_API_KEY = os.getenv("DEEPSEEK_API_KEY")
DEEPSEEK_BASE_URL = os.getenv("DEEPSEEK_API_BASE", "https://api.deepseek.com/v1")
try:
    deepseek_client = OpenAI(api_key=DEEPSEEK_API_KEY, base_url=DEEPSEEK_BASE_URL) if DEEPSEEK_API_KEY else None
    if deepseek_client:
        print(f"DeepSeek client initialized: {DEEPSEEK_API_KEY[:7]}...")
    else:
        print("DeepSeek client NOT initialized (API key missing).")
except Exception as e:
    deepseek_client = None
    print(f"DeepSeek client initialization failed: {e}")
DEEPSEEK_ENABLED = deepseek_client is not None


ENABLE_YT_SCREENSHOTS = os.getenv("ENABLE_YT_SCREENSHOTS", "false").lower() == "true"
YOUTUBE_TRANSCRIPT_ONLY = os.getenv("YOUTUBE_TRANSCRIPT_ONLY", "false").lower() == "true"
MAX_TOKENS_CHAT = int(os.getenv("AI_MAX_TOKENS_CHAT", "120"))
MAX_TOKENS_QUIZ = int(os.getenv("AI_MAX_TOKENS_QUIZ", "450"))
MAX_TOKENS_FLASHCARDS = int(os.getenv("AI_MAX_TOKENS_FLASHCARDS", "300"))
MAX_TOKENS_INGEST = int(os.getenv("AI_MAX_TOKENS_INGEST", "800"))
MAX_CONTEXT_CHARS = int(os.getenv("AI_MAX_CONTEXT_CHARS", "6000"))
MAX_CHAT_HISTORY = int(os.getenv("AI_MAX_CHAT_HISTORY", "4"))
ENABLE_IMAGE_CAPTIONS = os.getenv("ENABLE_IMAGE_CAPTIONS", "true").lower() == "true"
OPENAI_VISION_MODEL = os.getenv("OPENAI_VISION_MODEL", "gpt-4o-mini")
MAX_IMAGE_CAPTIONS = int(os.getenv("MAX_IMAGE_CAPTIONS", "10"))
MAX_IMAGES_PER_FILE = int(os.getenv("MAX_IMAGES_PER_FILE", "10"))
MAX_IMAGE_CAPTION_BYTES = int(os.getenv("MAX_IMAGE_CAPTION_BYTES", "1500000"))
CONTRIBUTIONS_DB_PATH = os.getenv("CONTRIBUTIONS_DB_PATH", str(Path(__file__).with_name("contributions.db")))

CONTRIBUTIONS_DB: Optional[sqlite3.Connection] = None
CONTRIBUTIONS_DB_LOCK = asyncio.Lock()

# --- Data models (kept close to iOS expectations) ----------------------------------------------

class APIStudySet(BaseModel):
    id: Optional[str] = Field(default_factory=lambda: str(uuid.uuid4()))
    title: str
    condensed_notes_html: Optional[str] = None
    full_text_chunks: List[str] = Field(default_factory=list)
    depth: Optional[str] = None
    image_urls: List[str] = Field(default_factory=list)
    image_captions: List[str] = Field(default_factory=list)

    class Config:
        populate_by_name = True
        json_encoders = {datetime: lambda v: v.isoformat()}


class IngestRequest(BaseModel):
    content: str
    source_type: str
    depth: Optional[str] = "overview"
    include_screenshots: Optional[bool] = None


class UsageEstimate(BaseModel):
    tokens_in: int
    tokens_out: int
    tokens_total: int
    stardust: int


class IngestResponse(BaseModel):
    success: bool
    study_set: Optional[APIStudySet] = None
    error: Optional[str] = None
    usage: Optional[UsageEstimate] = None


class ChatMessage(BaseModel):
    message: str
    sender: str
    timestamp: datetime = Field(default_factory=datetime.now)


class ChatRequest(BaseModel):
    study_set_id: str
    user_message: str
    chat_history: List[ChatMessage]
    condensed_notes: Optional[str] = None
    depth: Optional[str] = None
    ai_provider: Optional[str] = None
    system_instruction: Optional[str] = None


class ChatCorrection(BaseModel):
    original: str
    correction: str
    explanation: str

class ChatResponse(BaseModel):
    ai_message: str
    corrections: List[ChatCorrection] = Field(default_factory=list)


class QuizOption(BaseModel):
    text: str
    pinyin: Optional[str] = None
    is_correct: bool


class QuizQuestion(BaseModel):
    text: str
    pinyin: Optional[str] = None
    options: List[QuizOption]
    explanation: str
    explanation_pinyin: Optional[str] = None


class GenerateQuizRequest(BaseModel):
    context: Optional[str] = None
    study_set_id: Optional[str] = None
    chat_history: List[ChatMessage] = []
    depth: Optional[str] = None
    ai_provider: Optional[str] = None


class GenerateQuizResponse(BaseModel):
    quiz_questions: List[QuizQuestion]


class Flashcard(BaseModel):
    front: str
    back: str


class GenerateFlashcardsRequest(BaseModel):
    context: Optional[str] = None
    study_set_id: Optional[str] = None
    chat_history: List[ChatMessage] = []
    count: int = 5
    depth: Optional[str] = None
    ai_provider: Optional[str] = None


class GenerateFlashcardsResponse(BaseModel):
    flashcards: List[Flashcard]


# MARK: - Scene Plan Models


class ScenePlanRequest(BaseModel):
    study_set_id: str


class SceneSegment(BaseModel):
    text: str
    gesture: str
    duration: int


class ScenePlanResponse(BaseModel):
    title: str
    segments: List[SceneSegment]


class AsyncIngestResponse(BaseModel):
    task_id: str

class ContributionStatus(str, Enum):
    STAGED = "staged"
    VALIDATED = "validated"
    VALIDATION_FAILED = "validation_failed"
    APPROVED = "approved"
    REJECTED = "rejected"


class ContributionCreateRequest(BaseModel):
    user_id: str
    title: str
    summary: Optional[str] = None
    payload: Dict[str, Any] = Field(default_factory=dict)


class ContributionReviewRequest(BaseModel):
    status: ContributionStatus
    notes: Optional[str] = None


class ContributionRecord(BaseModel):
    id: str
    user_id: str
    title: str
    summary: Optional[str] = None
    payload: Dict[str, Any]
    status: ContributionStatus
    validation_errors: List[str] = Field(default_factory=list)
    review_notes: Optional[str] = None
    created_at: datetime
    updated_at: datetime


class ContributionListResponse(BaseModel):
    contributions: List[ContributionRecord]

# --- In-memory storage ------------------------------------------------------------------------

STUDY_SETS: dict[str, APIStudySet] = {}
INGEST_TASKS: dict[str, "IngestTask"] = {}

# --- Contribution pipeline -------------------------------------------------------------------

def init_contributions_db() -> sqlite3.Connection:
    conn = sqlite3.connect(CONTRIBUTIONS_DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS contributions (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            title TEXT NOT NULL,
            summary TEXT,
            payload_json TEXT NOT NULL,
            status TEXT NOT NULL,
            validation_errors TEXT,
            review_notes TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """
    )
    conn.execute("CREATE INDEX IF NOT EXISTS idx_contributions_status ON contributions(status)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_contributions_user ON contributions(user_id)")
    conn.commit()
    return conn


def contributions_db() -> sqlite3.Connection:
    global CONTRIBUTIONS_DB
    if CONTRIBUTIONS_DB is None:
        CONTRIBUTIONS_DB = init_contributions_db()
    return CONTRIBUTIONS_DB


def parse_contribution_row(row: sqlite3.Row) -> ContributionRecord:
    payload = json.loads(row["payload_json"]) if row["payload_json"] else {}
    errors = json.loads(row["validation_errors"]) if row["validation_errors"] else []
    return ContributionRecord(
        id=row["id"],
        user_id=row["user_id"],
        title=row["title"],
        summary=row["summary"],
        payload=payload,
        status=ContributionStatus(row["status"]),
        validation_errors=errors,
        review_notes=row["review_notes"],
        created_at=datetime.fromisoformat(row["created_at"]),
        updated_at=datetime.fromisoformat(row["updated_at"]),
    )


def validate_contribution_payload(payload: Any) -> List[str]:
    if payload is None:
        return ["payload_missing"]
    if isinstance(payload, dict):
        if not payload:
            return ["payload_empty"]
        entries = payload.get("entries")
        if entries is not None:
            if not isinstance(entries, list):
                return ["entries_not_list"]
            if len(entries) == 0:
                return ["entries_empty"]
        return []
    if isinstance(payload, list):
        return [] if payload else ["payload_empty"]
    return ["payload_invalid_type"]


def create_contribution_sync(request: ContributionCreateRequest) -> ContributionRecord:
    conn = contributions_db()
    now = datetime.now(timezone.utc).replace(microsecond=0)
    contribution_id = str(uuid.uuid4())
    payload_json = json.dumps(request.payload or {}, ensure_ascii=True)
    conn.execute(
        """
        INSERT INTO contributions (id, user_id, title, summary, payload_json, status, validation_errors, review_notes, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            contribution_id,
            request.user_id,
            request.title,
            request.summary,
            payload_json,
            ContributionStatus.STAGED.value,
            json.dumps([], ensure_ascii=True),
            None,
            now.isoformat(),
            now.isoformat(),
        ),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM contributions WHERE id = ?", (contribution_id,)).fetchone()
    return parse_contribution_row(row)


def validate_contribution_sync(contribution_id: str) -> ContributionRecord:
    conn = contributions_db()
    row = conn.execute("SELECT * FROM contributions WHERE id = ?", (contribution_id,)).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Contribution not found.")
    payload = json.loads(row["payload_json"]) if row["payload_json"] else {}
    errors = validate_contribution_payload(payload)
    now = datetime.now(timezone.utc).replace(microsecond=0)
    status = ContributionStatus.VALIDATED if not errors else ContributionStatus.VALIDATION_FAILED
    conn.execute(
        """
        UPDATE contributions
        SET status = ?, validation_errors = ?, updated_at = ?
        WHERE id = ?
        """,
        (status.value, json.dumps(errors, ensure_ascii=True), now.isoformat(), contribution_id),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM contributions WHERE id = ?", (contribution_id,)).fetchone()
    return parse_contribution_row(row)


def review_contribution_sync(contribution_id: str, request: ContributionReviewRequest) -> ContributionRecord:
    if request.status not in {ContributionStatus.APPROVED, ContributionStatus.REJECTED}:
        raise HTTPException(status_code=400, detail="Review status must be approved or rejected.")
    conn = contributions_db()
    row = conn.execute("SELECT * FROM contributions WHERE id = ?", (contribution_id,)).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Contribution not found.")
    now = datetime.now(timezone.utc).replace(microsecond=0)
    conn.execute(
        """
        UPDATE contributions
        SET status = ?, review_notes = ?, updated_at = ?
        WHERE id = ?
        """,
        (request.status.value, request.notes, now.isoformat(), contribution_id),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM contributions WHERE id = ?", (contribution_id,)).fetchone()
    return parse_contribution_row(row)


def list_contributions_sync(
    status: Optional[str],
    user_id: Optional[str],
    limit: int,
) -> List[ContributionRecord]:
    conn = contributions_db()
    clauses = []
    params: List[Any] = []
    if status:
        clauses.append("status = ?")
        params.append(status)
    if user_id:
        clauses.append("user_id = ?")
        params.append(user_id)
    where = f"WHERE {' AND '.join(clauses)}" if clauses else ""
    query = f"SELECT * FROM contributions {where} ORDER BY created_at DESC LIMIT ?"
    params.append(limit)
    rows = conn.execute(query, params).fetchall()
    return [parse_contribution_row(row) for row in rows]


def get_contribution_sync(contribution_id: str) -> ContributionRecord:
    conn = contributions_db()
    row = conn.execute("SELECT * FROM contributions WHERE id = ?", (contribution_id,)).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Contribution not found.")
    return parse_contribution_row(row)

# --- Utility helpers --------------------------------------------------------------------------


def chunk_text(text: str, chunk_size: int = 800) -> List[str]:
    words = text.split()
    if not words:
        return []
    return [" ".join(words[i : i + chunk_size]) for i in range(0, len(words), chunk_size)]

def estimate_tokens(text: str) -> int:
    if not text:
        return 0
    return max(1, math.ceil(len(text) / 4))

def stardust_from_tokens(tokens: int) -> int:
    return max(1, math.ceil(tokens / 100))

STATIC_DIR = Path(__file__).parent / "static"
CONTENT_DIR = Path(__file__).with_name("content")


def normalize_extension(ext: str) -> str:
    ext = (ext or "").lower().strip(".")
    if not ext or len(ext) > 8:
        return "png"
    return ext

def save_image_bytes(data: bytes, ext: str, prefix: str) -> Path:
    STATIC_DIR.mkdir(exist_ok=True)
    safe_ext = normalize_extension(ext)
    filename = f"{prefix}-{uuid.uuid4().hex}.{safe_ext}"
    out_path = STATIC_DIR / filename
    out_path.write_bytes(data)
    return out_path

def to_static_urls(paths: List[Path]) -> List[str]:
    return [f"/static/{path.name}" for path in paths]

def decode_text_bytes(raw_bytes: bytes) -> str:
    try:
        return raw_bytes.decode("utf-8")
    except Exception:
        try:
            return raw_bytes.decode("latin-1")
        except Exception:
            return ""

def extract_text_from_docx_bytes(raw_bytes: bytes) -> str:
    texts: List[str] = []
    try:
        with zipfile.ZipFile(io.BytesIO(raw_bytes)) as archive:
            for name in archive.namelist():
                if not name.startswith("word/") or not name.endswith(".xml"):
                    continue
                xml_content = archive.read(name)
                root = ET.fromstring(xml_content)
                for node in root.iter():
                    if node.tag.endswith("}t") and node.text:
                        texts.append(node.text)
    except Exception:
        return ""
    return " ".join(texts)

def extract_text_from_pptx_bytes(raw_bytes: bytes) -> str:
    texts: List[str] = []
    try:
        with zipfile.ZipFile(io.BytesIO(raw_bytes)) as archive:
            for name in archive.namelist():
                if not name.startswith("ppt/media/"):
                    continue
                if len(texts) >= MAX_IMAGES_PER_FILE:
                    break
                ext = Path(name).suffix.lstrip(".")
                if not ext:
                    continue
                data = archive.read(name)
                texts.append(extract_text_from_docx_bytes(data)) # Reusing DOCX logic for simplicity here
    except Exception:
        return ""
    return " ".join(texts)

def extract_images_from_office_zip(raw_bytes: bytes, folder_prefix: str, prefix: str) -> List[Path]:
    images: List[Path] = []
    try:
        with zipfile.ZipFile(io.BytesIO(raw_bytes)) as archive:
            for name in archive.namelist():
                if not name.startswith(folder_prefix):
                    continue
                if len(images) >= MAX_IMAGES_PER_FILE:
                    break
                ext = Path(name).suffix.lstrip(".")
                if not ext:
                    continue
                data = archive.read(name)
                images.append(save_image_bytes(data, ext, prefix))
    except Exception:
        return []
    return images

def extract_images_from_pdf_bytes(raw_bytes: bytes) -> List[Path]:
    images: List[Path] = []
    try:
        reader = PdfReader(io.BytesIO(raw_bytes))
    except Exception:
        return images

    for page in reader.pages:
        if len(images) >= MAX_IMAGES_PER_FILE:
            break
        page_images = getattr(page, "images", None)
        if page_images:
            for img in page_images:
                if len(images) >= MAX_IMAGES_PER_FILE:
                    break
                ext = normalize_extension(getattr(img, "extension", "jpg"))
                images.append(save_image_bytes(img.data, ext, "pdf"))
            continue

        resources = page.get("/Resources") or {}
        x_object = resources.get("/XObject")
        if not x_object:
            continue
        x_object = x_object.get_object()
        for obj in x_object:
            if len(images) >= MAX_IMAGES_PER_FILE:
                break
            item = x_object[obj]
            try:
                item = item.get_object()
            except Exception:
                pass
            if item.get("/Subtype") != "/Image":
                continue
            data = item.get_data()
            filter_type = item.get("/Filter")
            if isinstance(filter_type, list):
                filter_type = filter_type[0]
            if filter_type == "/DCTDecode":
                images.append(save_image_bytes(data, "jpg", "pdf"))
            elif filter_type == "/JPXDecode":
                images.append(save_image_bytes(data, "jp2", "pdf"))
    return images

def extract_text_from_pdf_bytes(raw_bytes: bytes) -> str:
    try:
        reader = PdfReader(io.BytesIO(raw_bytes))
    except Exception:
        return ""
    texts = []
    for page in reader.pages:
        try:
            texts.append(page.extract_text() or "")
        except Exception:
            continue
    return "\n".join([t for t in texts if t.strip()])


async def describe_images_with_openai(image_paths: List[Path], max_images: int = MAX_IMAGE_CAPTIONS) -> List[str]:
    if not OPENAI_ENABLED or not ENABLE_IMAGE_CAPTIONS:
        return []
    captions: List[str] = []
    prompt = (
        "Describe the image in 1-2 sentences. If it contains text, quote the text briefly. "
        "Focus on study-relevant information only."
    )

    def _describe(path: Path) -> str:
        data = path.read_bytes()
        if len(data) > MAX_IMAGE_CAPTION_BYTES:
            return ""
        ext = normalize_extension(path.suffix)
        mime = mimetypes.types_map.get(f".{ext}", "image/png")
        b64 = base64.b64encode(data).decode("utf-8")
        content = [
            {"type": "text", "text": prompt},
            {"type": "image_url", "image_url": {"url": f"data:{mime};base64,{b64}"}},
        ]
        response = openai_client.chat.completions.create(
            model=OPENAI_VISION_MODEL,
            messages=[{"role": "user", "content": content}],
            max_tokens=160,
        )
        return response.choices[0].message.content.strip()

    for path in image_paths[:max_images]:
        try:
            caption = await run_in_threadpool(_describe, path)
        except Exception:
            caption = ""
        if caption:
            captions.append(caption)
    return captions


async def transcribe_audio_bytes(raw_bytes: bytes, filename: str) -> str:
    if not OPENAI_ENABLED:
        raise HTTPException(status_code=400, detail="Audio transcription requires OpenAI.")
    suffix = Path(filename or "").suffix or ".m4a"
    with tempfile.NamedTemporaryFile(suffix=suffix) as tmp:
        tmp.write(raw_bytes)
        tmp.flush()
        return await run_in_threadpool(transcribe_audio_with_openai, tmp.name)

def transcribe_audio_with_openai(file_path: str) -> str:
    if openai_client is None:
        raise RuntimeError("OpenAI client not configured.")
    with open(file_path, "rb") as audio_file:
        response = openai_client.audio.transcriptions.create(model="whisper-1", file=audio_file)
        return response.text.strip()


async def extract_text_and_images_from_upload(
    file: UploadFile,
    source_type: str,
    max_images: int,
) -> tuple[str, List[Path]]:
    content_type = (file.content_type or "").lower()
    filename = (file.filename or "").lower()
    raw_bytes = await file.read()
    ext = Path(filename).suffix.lower()

    if content_type.startswith("audio/") or source_type.lower() in {"recording", "audio"}:
        text = await transcribe_audio_bytes(raw_bytes, filename)
        return text, []

    if content_type.startswith("image/") or source_type.lower() in {"photo", "image", "picture"}:
        mime_ext = mimetypes.guess_extension(content_type or "") or ext or ".png"
        image_path = save_image_bytes(raw_bytes, mime_ext.lstrip("."), "upload")
        return "", [image_path]

    if content_type in {
        "application/pdf",
        "application/x-pdf",
        "application/acrobat",
        "applications/vnd.pdf",
    } or ext == ".pdf" or source_type.lower() == "pdf":
        text = extract_text_from_pdf_bytes(raw_bytes)
        images = extract_images_from_pdf_bytes(raw_bytes)
        return text, images[:max_images]

    if ext in {".docx", ".doc"} or source_type.lower() in {"docx", "doc"}:
        text = extract_text_from_docx_bytes(raw_bytes)
        images = extract_images_from_office_zip(raw_bytes, "word/media/", "docx")
        return text, images[:max_images]

    if ext in {".pptx", ".ppt"} or source_type.lower() in {"pptx", "ppt"}:
        text = extract_text_from_pptx_bytes(raw_bytes)
        images = extract_images_from_office_zip(raw_bytes, "ppt/media/", "pptx")
        return text, images[:max_images]

    return decode_text_bytes(raw_bytes), []


async def build_study_set_from_text(
    content: str,
    source_type: str,
    depth: Optional[str],
    title_hint: Optional[str] = None,
    image_paths: Optional[List[Path]] = None,
    include_image_captions: bool = False,
    ai_provider: Optional[str] = None,
    allow_fallback: bool = True,
) -> tuple[APIStudySet, UsageEstimate]:
    captions: List[str] = []
    if image_paths and include_image_captions:
        captions = await describe_images_with_openai(image_paths)
    content_with_images = content.strip()
    if captions:
        notes = "\n".join(f"Image {idx + 1}: {caption}" for idx, caption in enumerate(captions))
        content_with_images = f"{content_with_images}\n\nImage notes:\n{notes}"
    
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
        image_urls=to_static_urls(image_paths or []),
        image_captions=captions,
    )
    save_study_set(study_set)
    return study_set, usage


def fallback_condensed_html(content: str) -> str:
    sentences = content.replace("\n", " ").split(".")
    bullets = [s.strip() for s in sentences if s.strip()]
    bullets = bullets[:5] if bullets else ["No content provided."]
    lis = "".join(f"<li>{b}.</li>" for b in bullets)
    return f"<ul>{lis}</ul>"

def depth_prompt_snippet(depth: Optional[str]) -> str:
    depth = (depth or "").lower()
    if depth.startswith("easy"):
        return "Style: Easy. Use simple sentences, 3-5 bullets, 1 emoji in header."
    if depth.startswith("overview"):
        return "Style: Overview. Keep it concise, 4-6 bullets, 1 emoji in each section title."
    if depth.startswith("intermediate"):
        return "Style: Intermediate. Add brief context + examples, 5-7 bullets, 1-2 emojis."
    if depth.startswith("detailed"):
        return "Style: Detailed. Include nuance, examples, and short notes, 6-9 bullets, 2 emojis max."
    if depth.startswith("adv"):
        return "Style: Advanced. Include nuance and edge cases, 7-10 bullets, restrained emojis."
    return "Style: Overview. Keep it concise, 4-6 bullets, 1 emoji per section title."

def extract_json_blob(text: str) -> str:
    start = text.find("{")
    arr_start = text.find("[")
    if start == -1 and arr_start != -1:
        start = arr_start
    if start == -1:
        raise ValueError("No JSON found in model output.")
    end = text.rfind("}")
    arr_end = text.rfind("]")
    if end == -1 and arr_end != -1:
        end = arr_end
    if end == -1:
        raise ValueError("No JSON closing brace/bracket found in model output.")
    return text[start : end + 1]

def detect_source_type(content: str, requested_source: str) -> str:
    text = (content or "").lower()
    if "youtube.com/watch" in text or "youtu.be/" in text:
        return "youtube"
    return requested_source

def save_study_set(study_set: APIStudySet) -> None:
    if study_set.id:
        STUDY_SETS[study_set.id] = study_set

def get_study_set(study_set_id: str) -> Optional[APIStudySet]:
    return STUDY_SETS.get(study_set_id)

def truncate_text(text: str, max_chars: int) -> str:
    if not text or max_chars <= 0:
        return text
    if len(text) <= max_chars:
        return text
    return text[:max_chars]

def resolve_context_and_depth(
    context: Optional[str], study_set_id: Optional[str], depth: Optional[str]
) -> tuple[str, Optional[str]]:
    if study_set_id:
        study_set = get_study_set(study_set_id)
        if study_set:
            joined = "\n\n".join(study_set.full_text_chunks)
            return truncate_text(joined, MAX_CONTEXT_CHARS), depth or study_set.depth
    if context:
        return truncate_text(context, MAX_CONTEXT_CHARS), depth
    raise HTTPException(status_code=400, detail="Context or study_set_id is required.")

def strip_html(raw_html: str) -> str:
    cleaned = re.sub(r"<[^>]+>", " ", raw_html)
    cleaned = re.sub(r"\s+", " ", cleaned)
    return cleaned.strip()

def build_scene_segments(text: str, title: str) -> List[SceneSegment]:
    if not text:
        return [
            SceneSegment(
                text=f"Let’s explore {title} with a short explanation and a real-world example.",
                gesture="speaking",
                duration=8,
            )
        ]

    sentences = [s.strip() for s in re.split(r"(?<=[.!?])\s+", text) if len(s.strip()) > 20]
    if not sentences:
        sentences = [text[:240]]

    max_segments = min(6, max(3, len(sentences) // 2))
    segments: List[SceneSegment] = []
    for index in range(max_segments):
        sentence = sentences[index % len(sentences)]
        gesture = "speaking"
        if index == 1:
            gesture = "point"
        elif index == 2:
            gesture = "emphasize"
        elif index == max_segments - 1:
            gesture = "happy"
        segments.append(SceneSegment(text=sentence, gesture=gesture, duration=8))

    segments.insert(
        0,
        SceneSegment(
            text=f"Here is a clear overview of {title}.",
            gesture="speaking",
            duration=6,
        ),
    )
    segments.append(
        SceneSegment(
            text=f"To recap, {title} is easier when you connect the ideas to real-world examples.",
            gesture="happy",
            duration=6,
        )
    )
    return segments

def build_chat_messages(system_prompt: str, history: List[ChatMessage], user_message: str):
    messages = [{"role": "system", "content": system_prompt}]
    trimmed_history = history[-MAX_CHAT_HISTORY:] if MAX_CHAT_HISTORY > 0 else []
    for msg in trimmed_history:
        sender = (msg.sender or "").strip().lower()
        if not msg.message or not msg.message.strip():
            continue
        if sender == "system":
            role = "system"
        elif sender.startswith("ai") or sender in {"assistant", "bot"}:
            role = "assistant"
        else:
            role = "user"
        messages.append({"role": role, "content": msg.message})
    messages.append({"role": "user", "content": user_message})
    return messages

def resolve_ai_provider_settings(request: Request) -> tuple[str, bool]:
    meta = getattr(request.state, "ai_guard_meta", None)
    if isinstance(meta, dict):
        provider = meta.get("provider") or "deepseek"
        plan_tier = (meta.get("plan_tier") or "free").lower()
    else:
        provider = request.headers.get("x-ai-provider", "deepseek")
        plan_tier = (request.headers.get("x-plan-tier") or "free").lower()
    allow_fallback = plan_tier == "creator"
    return provider, allow_fallback

def fallback_quiz(context: str) -> List["QuizQuestion"]:
    return [
        QuizQuestion(
            text="Placeholder question: What is the main topic?",
            options=[
                QuizOption(text="Context provided", is_correct=True),
                QuizOption(text="No context", is_correct=False),
            ],
            explanation="This is a fallback quiz item due to an error or empty response from AI.",
        )
    ]

def fallback_flashcards(context: str, count: int) -> List["Flashcard"]:
    return [Flashcard(front=f"Fallback Flashcard {i+1}", back="Fallback Answer") for i in range(max(1, count))]

# --- Ingest task models -----------------------------------------------------------------------


class IngestStatus(str, Enum):
    PENDING = "pending"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"


class IngestTask(BaseModel):
    task_id: str
    status: IngestStatus = IngestStatus.PENDING
    study_set: Optional[APIStudySet] = None
    error: Optional[str] = None
# --- FastAPI app ------------------------------------------------------------------------------

from vocab_engine import HSK1Tokenizer

# Constants
CONTENT_DIR = Path("content")
STATIC_DIR = Path("static")
VOCAB_PATH = CONTENT_DIR / "packs" / "zh_hsk1_vocab.json"

# Initialize Tokenizer
tokenizer_hsk1 = HSK1Tokenizer(str(VOCAB_PATH))

app = FastAPI(title="Know AI Backend")
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
scheduler = AsyncIOScheduler()
STATIC_DIR.mkdir(exist_ok=True)
CONTENT_DIR.mkdir(exist_ok=True)
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")
app.mount("/content", StaticFiles(directory=str(CONTENT_DIR)), name="content")

# --- v2 API Routers (normalized vocabulary model) ---
from api.v2.vocabulary import router as vocabulary_v2_router
from api.v2.search import router as search_v2_router
from api.v2.content import router as content_v2_router
from api.v2.tts import router as tts_v2_router
from api.v2.images import router as images_v2_router
from api.v2.placement import router as placement_v2_router
from api.v2.gym import router as gym_v2_router
from api.v2.path import router as path_v2_router
from api.v2.listening import router as listening_v2_router
from api.v2.tutor import router as tutor_v2_router
from api.v2.voice import router as voice_v2_router
from api.webhook_n8n import router as webhook_n8n_router

from api.v2 import ingest
from api.v2 import session as session_router_v2 # NEW: Session router
from learning_path import router_brain

app.include_router(vocabulary_v2_router)
app.include_router(search_v2_router)
app.include_router(content_v2_router)
app.include_router(tts_v2_router)
app.include_router(images_v2_router)
app.include_router(placement_v2_router)
app.include_router(gym_v2_router)
app.include_router(path_v2_router)
app.include_router(listening_v2_router)
app.include_router(tutor_v2_router)
app.include_router(voice_v2_router)
app.include_router(session_router_v2.router, prefix="/api/v2/learning")  # NEW: Quick Study sessions
app.include_router(webhook_n8n_router)  # n8n integration

app.include_router(router_brain.router) # NEW: The Brain
app.include_router(ingest.router)       # NEW: content ingestion

import random

@app.post("/api/v2/profile/setup")
async def setup_profile(
    goal: str = Body(..., embed=True),
    api_key: str = Depends(verify_api_key),
    user_id: str = Depends(get_user_id)
):
    """
    Sets the user's primary mission goal.
    """
    try:
        DB_V2.update_profile_goal(user_id, goal)
        return {"status": "success", "user_id": user_id, "goal": goal}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/v2/skills/stats")
async def get_skill_stats(
    user_id: str = Depends(get_user_id),
    api_key: str = Depends(verify_api_key)
):
    """
    Calculates overall mastery percentage for each skill based on V2 tracking.
    """
    try:
        # Use learning_path.db instead of legacy DBs
        db_path = Path(__file__).parent / "learning_path.db"
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        # Calculate averages for all tracked skills in user_word_mastery
        query = """
            SELECT 
                AVG(recognition) as reading,
                AVG(listening) as listening,
                AVG(production) as writing,
                AVG(usage) as speaking,
                COUNT(*) as total_words
            FROM user_word_mastery
            WHERE user_id = ?
        """
        row = cursor.execute(query, (user_id,)).fetchone()
        conn.close()
        
        if not row or row['total_words'] == 0:
            return {
                "reading": 0.0,
                "writing": 0.0,
                "listening": 0.0,
                "speaking": 0.0,
                "vocabulary": 0,
                "total_words": 0
            }
            
        # Database stores values as 0-100 integers, but Flutter expects 0.0-1.0 floats
        # So we divide by 100 to convert the scale
        return {
            "reading": round((float(row['reading']) if row['reading'] is not None else 0.0) / 100.0, 2),
            "writing": round((float(row['writing']) if row['writing'] is not None else 0.0) / 100.0, 2),
            "listening": round((float(row['listening']) if row['listening'] is not None else 0.0) / 100.0, 2),
            "speaking": round((float(row['speaking']) if row['speaking'] is not None else 0.0) / 100.0, 2),
            "total_words": row['total_words']
        }
    except Exception as e:
        print(f"Error fetching skill stats: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/drills/picture-match")
async def get_picture_match_drill(level: int = 1, unit: int = 1):
    try:
        with open("content/core_visuals.json", "r", encoding="utf-8") as f:
            all_visuals = json.load(f)
        
        # Determine default mode (optional, client can now switch)
        mode = "matching" 
        
        # Logic to select 10 visuals for this specific unit
        start_idx = (unit - 1) * 3 % len(all_visuals)
        selected = []
        for i in range(10):
            selected.append(all_visuals[(start_idx + i) % len(all_visuals)])
        
        images = []
        items = []
        colors = ["#6366F1", "#EC4899", "#8B5CF6", "#10B981", "#F59E0B", "#EF4444", "#06B6D4", "#8B5CF6", "#EC4899", "#10B981"]
        
        # Connect to DB to fetch real sentences
        try:
            conn = DB_V2._get_conn()
            db_cursor = conn.cursor()
        except:
            conn = None

        # Generate unified data structure for both modes
        for i, visual in enumerate(selected):
            img_id = str(i + 1)
            
            # Default values
            sentence = f"这是{visual['text']}。"
            translation = visual.get("meaning", "Example sentence.")
            
            # Fetch from DB if available
            if conn:
                try:
                    row = db_cursor.execute("""
                        SELECT c.context_sentence, t.context_translation 
                        FROM concepts c 
                        LEFT JOIN translations t ON c.id = t.concept_id AND t.native_lang = 'en'
                        WHERE c.word = ?
                    """, (visual["text"],)).fetchone()
                    
                    if row:
                        if row[0]: sentence = row[0]
                        if row[1]: translation = row[1]
                except Exception as e:
                    print(f"DB Fetch Error for {visual['text']}: {e}")

            # 1. Prepare Images (for Matching Mode)
            images.append({
                "id": img_id,
                "visual_id": visual["id"],
                "imageUrl": f"/static/images/core/{visual['id']}.png",
                "color": colors[i % len(colors)],
                "sentence": sentence,
                "translation": translation
            })
            
            # 2. Prepare Options (for Quiz/Identification Mode)
            options = []
            
            # Fetch Pinyin for correct answer
            correct_pinyin = ""
            if conn:
                p_row = db_cursor.execute("SELECT pronunciation FROM concepts WHERE word = ?", (visual["text"],)).fetchone()
                if p_row: correct_pinyin = p_row[0]

            options.append({"text": visual["text"], "pinyin": correct_pinyin, "isCorrect": True})
            
            wrong_candidates = [v for v in all_visuals if v["id"] != visual["id"]]
            if len(wrong_candidates) < 3:
                wrong_choices = [{"text": "Wrong", "id": "w1"}, {"text": "Error", "id": "w2"}, {"text": "False", "id": "w3"}]
            else:
                wrong_choices = random.sample(wrong_candidates, 3)

            for wc in wrong_choices:
                w_pinyin = ""
                if conn:
                    wp_row = db_cursor.execute("SELECT pronunciation FROM concepts WHERE word = ?", (wc["text"],)).fetchone()
                    if wp_row: w_pinyin = wp_row[0]
                options.append({"text": wc["text"], "pinyin": w_pinyin, "isCorrect": False})
            
            random.shuffle(options)
            
            # 3. Create Unified Item
            items.append({
                "id": str(uuid.uuid4())[:8],
                "text": visual["text"], # For Matching (Left side text)
                "imageUrl": f"/static/images/core/{visual['id']}.png", # For Quiz (Big image)
                "sentence": sentence,
                "translation": translation,
                "answer": img_id, # For Matching (links to image.id)
                "options": options # For Quiz (multiple choice)
            })
        
        if conn:
            conn.close()

        return {
            "unit": unit,
            "mode": mode,
            "images": images,
            "items": items
        }
    except Exception as e:
        print(f"Error generating drill: {e}")
        return {"images": [], "items": [], "mode": "matching"}


@app.get("/api/scenarios/{scenario_id}")
async def get_scenario(scenario_id: str):
    """
    Serves interactive roleplay scenarios.
    """
    # Security: basic path traversal prevention
    if ".." in scenario_id or "/" in scenario_id:
        raise HTTPException(status_code=400, detail="Invalid scenario ID")
        
    # Attempt to find the file in known directories (starting with HSK1)
    # In a real app, this might be looked up in a DB or index
    file_path = CONTENT_DIR / "scenarios" / "hsk1" / f"{scenario_id}.json"
    
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="Scenario not found")
        
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data
    except Exception as e:
        print(f"Error loading scenario: {e}")
        raise HTTPException(status_code=500, detail="Error loading scenario data")

@app.get("/api/passages/stats")
async def get_passage_stats(
    target_lang: str = Query("zh")
):
    """
    Returns the total count of passages for every HSK level in one single call.
    Reduces server pressure and improves app performance.
    """
    stats = {}
    try:
        for level in range(1, 7):
            prefix = "exam_hsk" if target_lang == "zh" else f"exam_{target_lang}_cefr"
            file_path = CONTENT_DIR / f"{prefix}{level}_v1.json"
            
            if file_path.exists():
                with open(file_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    stats[str(level)] = len(data.get("reading", []))
            else:
                stats[str(level)] = 0
        return stats
    except Exception as e:
        print(f"Error calculating passage stats: {e}")
        return {str(i): 0 for i in range(1, 7)}

@app.get("/api/passages")
async def get_passages(
    request: Request,
    level: int = Query(1),
    native: str = Query("en"),
    target_lang: str = Query("zh"),
    limit: int = 1,
    offset: int = 0
):
    """
    Serves 'Gold Standard' pre-generated reading passages.
    Supports pagination/on-demand slicing for efficiency.
    """
    try:
        # Determine file prefix based on language
        prefix = "exam_hsk" if target_lang == "zh" else f"exam_{target_lang}_cefr"
        file_path = CONTENT_DIR / f"{prefix}{level}_v1.json"
        
        if not file_path.exists():
            # Fallback to hsk if target specifically requested isn't there
            file_path = CONTENT_DIR / f"exam_hsk{level}_v1.json"
            if not file_path.exists():
                return {"total": 0, "passages": []}
            
        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)
            
        reading_items = data.get("reading", [])
        total = len(reading_items)
        
        # Apply slice (on-demand)
        start = offset
        end = min(offset + limit, total)
        slice_items = reading_items[start:end]
        
        passages = []
        for p_idx, item in enumerate(slice_items):
            actual_p_idx = offset + p_idx
            raw_text = item.get("text", "")
            raw_pinyin = item.get("pinyin", "")
            
            # Fetch the translation for the specific native language requested
            translations_map = item.get("translations", {})
            raw_translation = translations_map.get(native, translations_map.get("en", ""))

            # Split dialogue-based content by lines
            if "\n" in raw_text:
                sentence_texts = [l.strip() for l in raw_text.split("\n") if l.strip()]
                reading_texts = [l.strip() for l in raw_pinyin.split("\n") if l.strip()]
                meaning_texts = [l.strip() for l in raw_translation.split("\n") if l.strip()]
            else:
                sentence_texts = [s.strip() + "。" for s in raw_text.split("。") if s.strip()]
                reading_texts = [s.strip() for s in raw_pinyin.split(" ") if s.strip()] # Simplification
                meaning_texts = [raw_translation] # Fallback

            sentences = []
            for s_idx, txt in enumerate(sentence_texts):
                # Target Language determines the audio folder
                audio_lang_folder = "hsk1" if target_lang == "zh" else "en_cefr1"
                audio_rel_path = f"audio/{audio_lang_folder}/p{actual_p_idx}_s{s_idx}.mp3"
                audio_full_path = STATIC_DIR / audio_rel_path
                audio_url = f"/static/{audio_rel_path}" if audio_full_path.exists() else None
                
                # Fetch reading and meaning for this specific line
                current_reading = reading_texts[s_idx] if s_idx < len(reading_texts) else ""
                current_meaning = meaning_texts[s_idx] if s_idx < len(meaning_texts) else ""

                # Tokenize the text (strip character name if present for cleaner tokens)
                name_prefix = ""
                clean_txt = txt
                if "：" in txt:
                    parts = txt.split("：", 1)
                    clean_txt = parts[1]
                elif ":" in txt:
                    parts = txt.split(":", 1)
                    clean_txt = parts[1]

                tokens = tokenizer_hsk1.tokenize_line(clean_txt)
                serialized_tokens = []
                for t in tokens:
                    token_dict = t.to_dict()
                    if t.type == "VOCAB" and t.vocab_id:
                        v_info = tokenizer_hsk1.vocab_map.get(t.vocab_id, {})
                        token_dict["reading"] = v_info.get("pinyin", "")
                        # Resolve word meaning based on requested native language
                        meaning_obj = v_info.get("meaning", {})
                        if isinstance(meaning_obj, dict):
                            token_dict["meaning"] = meaning_obj.get(native, meaning_obj.get("en", ""))
                        else:
                            token_dict["meaning"] = str(meaning_obj)
                    serialized_tokens.append(token_dict)

                sentences.append({
                    "id": str(uuid.uuid4()),
                    "text": txt,
                    "reading": current_reading, 
                    "meaning": current_meaning,
                    "audio_url": audio_url,
                    "tokens": serialized_tokens,
                    "target_words": []
                })
                
            # Transform questions to the format expected by the iOS app (QuizQuestionRecord)
            raw_questions = item.get("questions", [])
            mapped_questions = []
            for q in raw_questions:
                options = []
                # Support both old format (correct index) and new format (is_correct flag)
                correct_idx = q.get("correct", -1)
                
                for i, opt in enumerate(q.get("options", [])):
                    if isinstance(opt, dict):
                        # Use the dictionary directly if it's in the right format
                        options.append({
                            "text": opt.get("text", ""),
                            "is_correct": opt.get("is_correct", i == correct_idx)
                        })
                    else:
                        # Convert simple string to the required dictionary format
                        options.append({
                            "text": str(opt),
                            "is_correct": i == correct_idx
                        })
                
                mapped_questions.append({
                    "text": q.get("question", ""),
                    "options": options,
                    "explanation": q.get("explanation", "")
                })
                
            # Resolve target words definitions for the native language
            raw_target_words = item.get("target_words", [])
            resolved_target_words = []
            for tw in raw_target_words:
                text = tw.get("text", "")
                v_info = tokenizer_hsk1.vocab_map.get(text, {})
                meaning_obj = v_info.get("meaning", {})
                
                # Resolve meaning
                resolved_meaning = ""
                if isinstance(meaning_obj, dict):
                    resolved_meaning = meaning_obj.get(native, meaning_obj.get("en", ""))
                else:
                    resolved_meaning = str(meaning_obj) or tw.get("meaning", "")
                
                resolved_target_words.append({
                    "text": text,
                    "pinyin": v_info.get("pinyin", tw.get("pinyin", "")),
                    "meaning": resolved_meaning
                })

            passages.append({
                "id": str(uuid.uuid4()),
                "title": item.get("title", "Untitled"),
                "sentences": sentences,
                "target_words": resolved_target_words,
                "questions": mapped_questions
            })
            
        return {
            "total": total,
            "limit": limit,
            "offset": offset,
            "passages": passages
        }
    except Exception as e:
        print(f"Error serving passages: {e}")
        return {"total": 0, "passages": []}

@app.post("/api/admin/clear_cache")
async def clear_cache(api_key: str = Depends(verify_api_key)):
    """Clear all API caches"""
    GLOBAL_CACHE.clear()
    from cache_manager_v2 import CACHE as V2_CACHE
    V2_CACHE.clear()
    return {"status": "success", "message": "All caches cleared"}

@app.get("/health")
def health_check():
    db_ok = False
    try:
        # Check DB_V2 connection
        conn = DB_V2._get_conn()
        conn.execute("SELECT 1")
        conn.close()
        db_ok = True
    except:
        pass

    return {
        "status": "ok" if db_ok else "degraded",
        "database": "connected" if db_ok else "disconnected",
        "cache": GLOBAL_CACHE.stats(),
        "openai_configured": openai_client is not None,
        "deepseek_configured": deepseek_client is not None,
        "timestamp": datetime.now(timezone.utc).isoformat()
    }


@app.get("/health/v2")
def health_check_v2():
    """Detailed health check for v2 normalized schema"""
    import time as _time
    checks = {}
    
    conn = None
    try:
        conn = DB_V2._get_conn()
        
        # Table existence and row counts
        v2_tables = ["concepts", "lexemes", "glosses", "content", "transcripts"]
        for table in v2_tables:
            try:
                count = conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
                checks[table] = count
            except Exception as e:
                checks[table] = f"ERROR: {e}"
        
        # Index verification
        indexes = conn.execute("""
            SELECT name FROM sqlite_master 
            WHERE type='index' AND name LIKE 'idx_%'
        """).fetchall()
        checks["indexes"] = [i[0] for i in indexes]
        
        # Sample query performance test
        start = _time.perf_counter()
        conn.execute("""
            SELECT l.*, g.gloss 
            FROM lexemes l 
            LEFT JOIN glosses g ON l.id = g.lexeme_id 
            WHERE l.language = 'zh' AND g.language = 'en'
            LIMIT 50
        """).fetchall()
        checks["sample_query_ms"] = round((_time.perf_counter() - start) * 1000, 2)
        
        # Language coverage
        lang_counts = conn.execute("""
            SELECT language, COUNT(*) as cnt FROM lexemes GROUP BY language
        """).fetchall()
        checks["languages"] = {row[0]: row[1] for row in lang_counts}
        
        # Cache stats from v2 cache
        from cache_manager_v2 import get_cache_stats
        checks["cache_v2"] = get_cache_stats()
        
        checks["status"] = "ok"
        
    except Exception as e:
        checks["status"] = "error"
        checks["error"] = str(e)
    finally:
        if conn:
            conn.close()
    
    checks["timestamp"] = datetime.now(timezone.utc).isoformat()
    return checks

@app.middleware("http")
async def add_process_time_header(request: Request, call_next):
    start_time = time.time()
    response = await call_next(request)
    process_time = time.time() - start_time
    
    # Log slow requests
    if process_time > 1.0:
        print(f"⚠️ Slow Request: {request.method} {request.url.path} took {process_time:.4f}s")
    
    response.headers["X-Process-Time"] = f"{process_time:.4f}s"
    return response


@app.middleware("http")
async def ai_usage_ledger_middleware(request: Request, call_next):
    response = await call_next(request)
    if 200 <= response.status_code < 300:
        meta = getattr(request.state, "ai_guard_meta", None)
        if meta:
            await record_ai_usage(request.app, meta, response.status_code)
    return response

@app.on_event("startup")
async def startup_event():
    scheduler.start()
    try:
        await init_ai_guard(app)
        init_ai_guard_ledger(app)
    except Exception as e:
        print(f"AI Guard Initialization Warning: {e}. Running without AI Guard.")
        setattr(app.state, "ai_guard", None) # Ensure ai_guard is None if init fails
    init_contributions_db()

    # Cache pre-warming removed (was using legacy VOCAB_DB)
    print("✅ Startup complete.")

@app.post("/api/analytics/batch")
async def log_analytics(request: Request):
    """Log analytics events from iOS app"""
    try:
        data = await request.json()
        # In production, save to analytics.db. For now, we log it.
        device_id = data.get("device_id", "unknown")
        events = data.get("events", [])
        print(f"📊 Analytics: {len(events)} events from {device_id}")
        return {"status": "ok", "received": len(events)}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.get("/api/listening")
async def get_listening(level: int = Query(1), native: str = Query("en")):
    file_path = CONTENT_DIR / f"exam_hsk{level}_v1.json"
    if not file_path.exists(): return {"items": []}
    with open(file_path, "r") as f:
        data = json.load(f)
    items = data.get("listening", [])
    for item in items:
        trans = item.get("translations", {})
        item["translation"] = trans.get(native, trans.get("en", ""))
    return {"items": items}

@app.get("/api/speaking")
async def get_speaking(level: int = Query(1), native: str = Query("en")):
    file_path = CONTENT_DIR / f"exam_hsk{level}_v1.json"
    if not file_path.exists(): return {"items": []}
    with open(file_path, "r") as f:
        data = json.load(f)
    items = data.get("speaking", [])
    for item in items:
        trans = item.get("translations", {})
        item["description_en"] = trans.get(native, trans.get("en", ""))
    return {"items": items}

@app.get("/api/writing")
async def get_writing(level: int = Query(1), native: str = Query("en")):
    file_path = CONTENT_DIR / f"exam_hsk{level}_v1.json"
    if not file_path.exists(): return {"items": []}
    with open(file_path, "r") as f:
        data = json.load(f)
    items = data.get("writing", [])
    for item in items:
        trans = item.get("translations", {})
        item["prompt"] = trans.get(native, trans.get("en", ""))
    return {"items": items}

@app.on_event("shutdown")
async def shutdown_event():
    scheduler.shutdown()

app.add_middleware(GZipMiddleware, minimum_size=1000)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://knowai.app",
        "https://www.knowai.app",
        "capacitor://localhost",
        "ionic://localhost",
    ],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Content-Type", "Authorization", "X-API-Key"],
)


@app.get("/api/quota")
async def quota(request: Request):
    guard = getattr(request.app.state, "ai_guard", None)
    if guard is None or getattr(guard, "redis", None) is None:
        raise HTTPException(status_code=503, detail="Quota service unavailable.")

    user_id = request.headers.get("x-user-id")
    if not user_id:
        raise HTTPException(status_code=400, detail="X-User-Id required")

    org_id = request.headers.get("x-org-id") or request.headers.get("x-classroom-id")
    plan_tier = (request.headers.get("x-plan-tier") or "free").lower()
    screen_time_opt_in = request.headers.get("x-screen-time-opt-in", "false")
    notifications_opt_in = request.headers.get("x-notifications-opt-in", "false")

    try:
        return await read_quota(
            guard.redis,
            user_id=user_id,
            org_id=org_id,
            plan_tier=plan_tier,
            screen_time_opt_in=screen_time_opt_in.lower() in {"1", "true", "yes", "y", "on"},
            notifications_opt_in=notifications_opt_in.lower() in {"1", "true", "yes", "y", "on"},
        )
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Quota service unavailable.") from exc


@app.post("/api/contributions", response_model=ContributionRecord)
async def create_contribution(request: ContributionCreateRequest):
    if not request.user_id.strip() or not request.title.strip():
        raise HTTPException(status_code=400, detail="user_id and title required")
    async with CONTRIBUTIONS_DB_LOCK:
        return await run_in_threadpool(create_contribution_sync, request)


@app.get("/api/contributions", response_model=ContributionListResponse)
async def list_contributions(
    status: Optional[str] = None,
    user_id: Optional[str] = None,
    limit: int = 50,
):
    safe_limit = max(1, min(200, limit))
    async with CONTRIBUTIONS_DB_LOCK:
        contributions = await run_in_threadpool(list_contributions_sync, status, user_id, safe_limit)
    return ContributionListResponse(contributions=contributions)


@app.get("/api/contributions/{contribution_id}", response_model=ContributionRecord)
async def get_contribution(contribution_id: str):
    async with CONTRIBUTIONS_DB_LOCK:
        return await run_in_threadpool(get_contribution_sync, contribution_id)


@app.post("/api/contributions/{contribution_id}/validate", response_model=ContributionRecord)
async def validate_contribution(contribution_id: str):
    async with CONTRIBUTIONS_DB_LOCK:
        return await run_in_threadpool(validate_contribution_sync, contribution_id)


@app.post("/api/contributions/{contribution_id}/review", response_model=ContributionRecord)
async def review_contribution(contribution_id: str, request: ContributionReviewRequest):
    async with CONTRIBUTIONS_DB_LOCK:
        return await run_in_threadpool(review_contribution_sync, contribution_id, request)

@app.post("/api/ingest_file", response_model=IngestResponse)
async def ingest_file(
    http_request: Request,
    file: UploadFile = File(...),
    source_type: str = Form(...),
    depth: Optional[str] = Form(None),
    include_images: Optional[bool] = Form(False),
    max_images: Optional[int] = Form(None),
    _: None = Depends(ai_guard_dependency),
):
    if not MULTIPART_AVAILABLE:
        return IngestResponse(success=False, error="python-multipart is required for file uploads.")

    try:
        max_images_value = max(1, min(MAX_IMAGES_PER_FILE, max_images or MAX_IMAGES_PER_FILE))
        extracted_text, image_paths = await extract_text_and_images_from_upload(
            file,
            source_type,
            max_images=max_images_value,
        )
        provider, allow_fallback = resolve_ai_provider_settings(http_request)
        study_set, usage = await build_study_set_from_text(
            extracted_text,
            source_type,
            depth,
            title_hint=file.filename,
            image_paths=image_paths,
            include_image_captions=bool(include_images),
            ai_provider=provider,
            allow_fallback=allow_fallback,
        )
        return IngestResponse(success=True, study_set=study_set, error=None, usage=usage)
    except HTTPException as exc:
        return IngestResponse(success=False, error=str(exc.detail), study_set=None)
    except Exception as exc:
        return IngestResponse(success=False, error=str(exc), study_set=None)


@app.post("/api/ingest", response_model=AsyncIngestResponse, status_code=202)
async def ingest_material(
    request: IngestRequest,
    http_request: Request,
    _: None = Depends(ai_guard_dependency),
):
    detected_source = detect_source_type(request.content, request.source_type)

    if detected_source == "youtube":
        task_id = str(uuid.uuid4())
        INGEST_TASKS[task_id] = IngestTask(task_id=task_id, status=IngestStatus.PENDING)
        scheduler.add_job(
            process_youtube_video,
            args=[task_id, request.content, request.depth, request.include_screenshots],
        )
        return AsyncIngestResponse(task_id=task_id)

    if not request.content.strip():
        raise HTTPException(status_code=400, detail="Content is required.")

    provider, allow_fallback = resolve_ai_provider_settings(http_request)
    condensed_html = await generate_condensed_notes_html(
        request.content,
        request.source_type,
        request.depth,
        ai_provider=provider,
        allow_fallback=allow_fallback,
    )
    study_set = APIStudySet(
        id=str(uuid.uuid4()),
        title=request.content[:40] + "..." if len(request.content) > 40 else request.content[:40] or "Study Set",
        condensed_notes_html=condensed_html,
        full_text_chunks=chunk_text(request.content),
        depth=request.depth,
    )
    save_study_set(study_set)
    
    task_id = str(uuid.uuid4())
    INGEST_TASKS[task_id] = IngestTask(task_id=task_id, status=IngestStatus.COMPLETED, study_set=study_set)
    
    return AsyncIngestResponse(task_id=task_id)


@app.get("/api/ingest/status/{task_id}", response_model=IngestTask)
async def get_ingest_status(task_id: str):
    task = INGEST_TASKS.get(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    return task


async def process_youtube_video(task_id: str, youtube_url: str, depth: Optional[str], include_screenshots: Optional[bool]):
    task = INGEST_TASKS[task_id]
    task.status = IngestStatus.PROCESSING
    print(f"[ingest] task={task_id} status=processing")
    
    try:
        study_set = await asyncio.wait_for(
            ingest_youtube_logic(youtube_url, depth, include_screenshots),
            timeout=300
        )
        task.study_set = study_set
        task.status = IngestStatus.COMPLETED
        print(f"[ingest] task={task_id} status=completed")
    except asyncio.TimeoutError:
        task.status = IngestStatus.FAILED
        task.error = "Ingestion timed out. Try again or use a shorter video."
        print(f"[ingest] task={task_id} status=failed error=timeout")
    except Exception as e:
        task.status = IngestStatus.FAILED
        task.error = str(e)
        print(f"[ingest] task={task_id} status=failed error={e}")


async def ingest_youtube_logic(youtube_url: str, depth: Optional[str], include_screenshots: Optional[bool]) -> APIStudySet:
    video_id = None
    if "youtube.com/watch?v=" in youtube_url:
        video_id = youtube_url.split("v=")[1].split("&")[0]
    elif "youtu.be/" in youtube_url:
        video_id = youtube_url.split("youtu.be/")[1].split("?")[0]

    if not video_id:
        raise ValueError("Invalid YouTube URL provided.")

    MAX_AUDIO_BYTES = 25 * 1024 * 1024
    full_transcript = ""
    try:
        transcript_text = await asyncio.wait_for(run_in_threadpool(try_get_transcript, video_id), timeout=20)
    except asyncio.TimeoutError:
        transcript_text = None

    if not transcript_text:
        try:
            transcript_text = await asyncio.wait_for(run_in_threadpool(try_get_transcript_via_ytdlp, video_id), timeout=30)
            if transcript_text:
                print("subtitle_ok_ytdlp")
        except asyncio.TimeoutError:
            pass

    if transcript_text:
        full_transcript = transcript_text
        print("subtitle_ok")
    else:
        print("subtitle_fail: No transcript found.")
        if not ENABLE_WHISPER_FALLBACK or not OPENAI_ENABLED:
            raise RuntimeError("No transcript available for this video.")
        print("fallback_start (Whisper)")
        try:
            with tempfile.TemporaryDirectory(prefix="yt_audio_") as td:
                td_path = Path(td)
                out_tmpl = str(td_path / "audio.%(ext)s")

                def _dl():
                    YTDLP_BIN = os.getenv("YTDLP_BIN", "yt-dlp")
                    COOKIES_FROM = os.getenv("YTDLP_COOKIES_FROM_BROWSER", "firefox")
                    COOKIES_FILE = os.getenv("YTDLP_COOKIES_FILE")

                    cmd = [YTDLP_BIN]
                    if COOKIES_FILE:
                        cmd.extend(["--cookies", COOKIES_FILE])
                    else:
                        cmd.extend(["--cookies-from-browser", COOKIES_FROM])
                    
                    cmd.extend([
                        "--no-playlist",
                        "--sleep-interval", "2",
                        "--max-sleep-interval", "6",
                        "-f", "bestaudio/best",
                        "-o", out_tmpl,
                        f"https://www.youtube.com/watch?v={video_id}",
                    ])
                    print("YTDLP CMD =", cmd)
                    p = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
                    if p.returncode != 0:
                        raise RuntimeError(f"yt-dlp failed ({p.returncode}): {p.stderr.strip()[:2000]}")
                await run_in_threadpool(_dl)

                audio_files = list(td_path.glob("audio.*"))
                if not audio_files:
                    raise RuntimeError("yt-dlp produced no audio file")
                raw_audio = audio_files[0]

                mp3_path = td_path / "audio.mp3"

                def _ff():
                    subprocess.run(
                        ["ffmpeg", "-y", "-i", str(raw_audio), "-vn", "-ac", "1", "-ar", "16000", "-b:a", "32k", str(mp3_path)],
                        check=True,
                        capture_output=True,
                        timeout=180
                    )
                await run_in_threadpool(_ff)

                audio_size = mp3_path.stat().st_size
                print(f"audio_size_bytes={audio_size}")
                if audio_size > MAX_AUDIO_BYTES:
                    raise RuntimeError("Compressed audio still >25MB; implement chunk splitting.")

                print("whisper_start")
                try:
                    full_transcript = await asyncio.wait_for(
                        transcribe_audio_with_openai(str(mp3_path)),
                        timeout=150,
                    )
                except asyncio.TimeoutError:
                    raise RuntimeError("Whisper transcription timed out.") from None
                print(f"whisper_ok transcript_chars={len(full_transcript)}")
                print(f"fallback_ok transcript_chars={len(full_transcript)}")

        except Exception as fb_exc:
            print(f"fallback_fail={fb_exc}")
            raise RuntimeError(f"Transcript fetch failed (no transcript available). Fallback transcription failed ({fb_exc}).")

    try:
        youtube_material = await asyncio.wait_for(
            generate_youtube_material_from_transcript(full_transcript, depth),
            timeout=60,
        )
    except asyncio.TimeoutError:
        youtube_material = {
            "summary": fallback_condensed_html(full_transcript),
            "timestamps": [],
            "error": "Timed out while generating summary; using fallback.",
        }
    except Exception as exc:
        youtube_material = {
            "summary": fallback_condensed_html(full_transcript),
            "timestamps": [],
            "error": f"Summary generation failed: {exc}",
        }
    
    summary_html = youtube_material.get("summary", "")
    timestamps = youtube_material.get("timestamps", [])

    screenshot_paths: List[str] = []
    if (include_screenshots or ENABLE_YT_SCREENSHOTS) and timestamps:
        screenshot_paths = await run_in_threadpool(take_screenshots_from_youtube, video_id, timestamps)
    image_urls = [f"/static/{Path(p).name}" for p in screenshot_paths]

    final_html = assemble_youtube_material_html(summary_html, screenshot_paths)

    study_set = APIStudySet(
        id=str(uuid.uuid4()),
        title=f"YouTube: {full_transcript[:30]}..." if len(full_transcript) > 30 else "YouTube Study Set",
        condensed_notes_html=final_html,
        full_text_chunks=chunk_text(full_transcript),
        depth=depth,
        image_urls=image_urls,
    )
    save_study_set(study_set)
    return study_set


def run_chat_completion(
    messages: List[Dict[str, str]],
    temperature: float = 0.4,
    ai_provider: Optional[str] = None,
    max_tokens: Optional[int] = None,
    allow_fallback: bool = True,
) -> str:
    last_error = None

    def _create_completion(llm_client: OpenAI, model: str) -> str:
        payload = {"model": model, "messages": messages, "temperature": temperature}
        if max_tokens is not None:
            payload["max_tokens"] = max_tokens
        response = llm_client.chat.completions.create(**payload)
        return response.choices[0].message.content.strip()

    def _try_deepseek() -> str:
        if deepseek_client is None:
            raise RuntimeError("DeepSeek client not configured.")
        return _create_completion(deepseek_client, DEEPSEEK_MODEL)

    def _try_openai() -> str:
        if openai_client is None:
            raise RuntimeError("OpenAI client not configured.")
        return _create_completion(openai_client, OPENAI_MODEL)

    if ai_provider == "deepseek":
        try:
            return _try_deepseek()
        except Exception as exc:
            last_error = exc
        if allow_fallback:
            try:
                return _try_openai()
            except Exception as exc:
                last_error = exc
    elif ai_provider == "openai":
        try:
            return _try_openai()
        except Exception as exc:
            last_error = exc
        if allow_fallback:
            try:
                return _try_deepseek()
            except Exception as exc:
                last_error = exc
    else: # Default or auto-select
        if deepseek_client:
            try:
                return _try_deepseek()
            except Exception as exc:
                last_error = exc
                if openai_client and allow_fallback: # Fallback to OpenAI if DeepSeek fails/not configured
                    try:
                        return _try_openai()
                    except Exception as exc_fb:
                        last_error = exc_fb
        elif openai_client: # If only OpenAI is available
            try:
                return _try_openai()
            except Exception as exc:
                last_error = exc
        else:
            raise RuntimeError("No LLM clients configured.")


    raise RuntimeError(f"No chat provider available or all failed. Last error: {last_error}")


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
            messages,
            0.3,
            ai_provider,
            MAX_TOKENS_INGEST,
            allow_fallback,
        )
    except Exception:
        return fallback_condensed_html(content)


async def generate_chat_reply(
    chat_request: ChatRequest,
    ai_provider_override: Optional[str] = None,
    allow_fallback: bool = True,
) -> ChatResponse:
    default_prompt = (
        "You are a helpful language tutor. "
        "Analyze the user's input for grammar/vocabulary mistakes. "
        "Return ONLY a JSON object with: "
        "- 'reply': Your conversational response (1-3 sentences). "
        "- 'corrections': A list of objects { 'original': ..., 'correction': ..., 'explanation': ... } for any errors found. "
        "If no errors, 'corrections' should be empty array. "
        "Do not output markdown code blocks, just raw JSON."
        f"{depth_prompt_snippet(chat_request.depth)}"
    )
    system_prompt = (
        chat_request.system_instruction.strip()
        if chat_request.system_instruction and chat_request.system_instruction.strip()
        else default_prompt
    )
    messages = build_chat_messages(system_prompt, chat_request.chat_history, chat_request.user_message)
    provider = ai_provider_override or chat_request.ai_provider

    try:
        raw = await run_in_threadpool(
            run_chat_completion,
            messages,
            0.6,
            provider,
            MAX_TOKENS_CHAT,
            allow_fallback,
        )
        
        try:
            json_str = extract_json_blob(raw)
            data = json.loads(json_str)
            reply = data.get("reply", "")
            corrections_data = data.get("corrections", [])
            corrections = []
            for c in corrections_data:
                corrections.append(ChatCorrection(
                    original=c.get("original", ""),
                    correction=c.get("correction", ""),
                    explanation=c.get("explanation", "")
                ))
            
            # If reply is empty but we parsed JSON, maybe the model messed up structure
            if not reply:
                 reply = raw # Fallback to full text
            
            return ChatResponse(ai_message=reply, corrections=corrections)
            
        except (ValueError, json.JSONDecodeError):
            # Fallback: Model returned plain text instead of JSON
            return ChatResponse(ai_message=raw)
            
    except Exception:
        return ChatResponse(ai_message=f"(offline) Echo: {chat_request.user_message}")


async def generate_quiz_questions(
    context: str,
    history: List[ChatMessage],
    depth: Optional[str],
    ai_provider: Optional[str] = None,
    allow_fallback: bool = True,
) -> List[QuizQuestion]:
    system_prompt = (
        "Create 3-5 multiple-choice questions from the provided study context. "
        "Return ONLY valid JSON with a top-level 'quiz_questions' list. "
        "Each item MUST have: 'text' (Hanzi), 'pinyin' (with tone marks), "
        "'options' (list with 'text', 'pinyin', and 'is_correct'), "
        "'explanation' (English), and 'explanation_pinyin'. "
        "Use 4 options per question. Keep grammar simple and aligned to depth."
    )
    messages = build_chat_messages(system_prompt, history, f"Context:\n{context}")

    try:
        raw = await run_in_threadpool(
            run_chat_completion,
            messages,
            0.5,
            ai_provider,
            MAX_TOKENS_QUIZ,
            allow_fallback,
        )
        data = json.loads(extract_json_blob(raw))
        quiz_items = data.get("quiz_questions", data if isinstance(data, list) else [])
        parsed = []
        for item in quiz_items:
            options = [
                QuizOption(
                    text=opt.get("text", ""), 
                    pinyin=opt.get("pinyin", ""),
                    is_correct=bool(opt.get("is_correct"))
                )
                for opt in item.get("options", [])
            ]
            if not options:
                options = [
                    QuizOption(text="A", pinyin="A", is_correct=True),
                    QuizOption(text="B", pinyin="B", is_correct=False),
                ]
            parsed.append(
                QuizQuestion(
                    text=item.get("text", "Question?"),
                    pinyin=item.get("pinyin", ""),
                    options=options,
                    explanation=item.get("explanation", ""),
                    explanation_pinyin=item.get("explanation_pinyin", "")
                )
            )
        return parsed or fallback_quiz(context)
    except Exception as e:
        print(f"Quiz generation failed: {e}")
        return fallback_quiz(context)


async def generate_flashcards_from_context(
    context: str,
    history: List[ChatMessage],
    count: int,
    depth: Optional[str],
    ai_provider: Optional[str] = None,
    allow_fallback: bool = True,
) -> List[Flashcard]:
    system_prompt = (
        "Create concise flashcards from the study context. "
        "Return ONLY JSON with top-level 'flashcards': list of items with 'front' and 'back'. "
        "Front should be a question or term; back should be the answer. Cover definitions, key distinctions, and 1-2 examples if useful. "
        f"{depth_prompt_snippet(depth)} "
        "Use 1 emoji in front when helpful."
    )
    messages = build_chat_messages(system_prompt, history, f"Context:\n{context}\nCount: {count}")

    try:
        raw = await run_in_threadpool(
            run_chat_completion,
            messages,
            0.4,
            ai_provider,
            MAX_TOKENS_FLASHCARDS,
            allow_fallback,
        )
        data = json.loads(extract_json_blob(raw))
        card_items = data.get("flashcards", data if isinstance(data, list) else [])
        parsed = [
            Flashcard(front=item.get("front", "Placeholder?"), back=item.get("back", "Answer"))
            for item in card_items
        ]
        return parsed or fallback_flashcards(context, count)
    except Exception as e:
        print(f"Flashcard generation failed: {e}")
        return fallback_flashcards(context, count)


# Placeholders for youtube_transcript_api and screenshot
def try_get_transcript(video_id: str) -> Optional[str]:
    try:
        transcript_list = YouTubeTranscriptApi.get_transcript(video_id)
        transcript = " ".join([d["text"] for d in transcript_list])
        return transcript
    except NoTranscriptFound:
        return None
    except Exception as e:
        print(f"Error getting transcript via YouTubeTranscriptApi: {e}")
        return None

def try_get_transcript_via_ytdlp(video_id: str) -> Optional[str]:
    try:
        # Simplified for reconstruction, a full implementation would use subprocess with yt-dlp
        print(f"Attempting to get transcript via yt-dlp for video_id: {video_id}")
        return None # Placeholder
    except Exception as e:
        print(f"Error getting transcript via yt-dlp: {e}")
        return None

def generate_youtube_material_from_transcript(transcript: str, depth: Optional[str]) -> Dict[str, Any]:
    # Placeholder for summary and timestamps logic
    print("Generating YouTube material from transcript (placeholder)")
    return {
        "summary": fallback_condensed_html(transcript),
        "timestamps": [],
        "error": None,
    }

def take_screenshots_from_youtube(video_id: str, timestamps: List[float]) -> List[str]:
    print(f"Taking screenshots from YouTube (placeholder for video: {video_id})")
    return []

def assemble_youtube_material_html(summary_html: str, screenshot_paths: List[str]) -> str:
    # Placeholder for assembling HTML
    return summary_html

# --- Progress & SRS models --------------------------------------------------------------------

# --- Monitoring & Rate Limiting ---
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("KnowAI-SRS")

# Simple in-memory rate limiter: {user_id: [timestamps]}
RATE_LIMITS: Dict[str, List[float]] = {}

def check_rate_limit(user_id: str, limit: int = 60, window: int = 60):
    now = time.time()
    user_calls = RATE_LIMITS.get(user_id, [])
    # Keep only calls within the last 'window' seconds
    user_calls = [t for t in user_calls if t > now - window]
    if len(user_calls) >= limit:
        return False
    user_calls.append(now)
    RATE_LIMITS[user_id] = user_calls
    return True

# --- Progress & SRS models --------------------------------------------------------------------

class ProgressRecord(BaseModel):
    user_id: str
    item_id: str
    item_type: str  # "word" or "passage"
    success: bool   # True = correct, False = incorrect
    timestamp: Optional[str] = None # For frontend sync time

def init_progress_db():
    conn = sqlite3.connect("progress.db", check_same_thread=False)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS progress (
            user_id TEXT,
            item_id TEXT,
            item_type TEXT,
            interval INTEGER DEFAULT 0,
            ease_factor REAL DEFAULT 2.5,
            repetitions INTEGER DEFAULT 0,
            last_reviewed TEXT,
            due_date TEXT,
            PRIMARY KEY (user_id, item_id)
        )
    """)
    conn.commit()
    logger.info("Progress database initialized.")
    return conn

PROGRESS_DB = init_progress_db()

def update_srs(user_id: str, item_id: str, item_type: str, success: bool):
    cursor = PROGRESS_DB.cursor()
    # Fetch existing data using UTC aware parameters
    cursor.execute("SELECT interval, ease_factor, repetitions FROM progress WHERE user_id = ? AND item_id = ?", (user_id, item_id))
    row = cursor.fetchone()
    
    if row:
        interval, ease, reps = row
    else:
        interval, ease, reps = 0, 2.5, 0
        
    if success:
        if reps == 0:
            interval = 1
        elif reps == 1:
            interval = 6
        else:
            interval = math.ceil(interval * ease)
        reps += 1
        ease = min(5.0, ease + 0.1) # Cap ease factor
    else:
        # Penalty for failure: Reset progress but keep some 'ease' memory
        reps = 0
        interval = 1
        ease = max(1.3, ease - 0.2)
        
    now = datetime.now(timezone.utc)
    due = now + timedelta(days=interval)
    
    cursor.execute("""
        INSERT INTO progress (user_id, item_id, item_type, interval, ease_factor, repetitions, last_reviewed, due_date)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(user_id, item_id) DO UPDATE SET
            interval=excluded.interval,
            ease_factor=excluded.ease_factor,
            repetitions=excluded.repetitions,
            last_reviewed=excluded.last_reviewed,
            due_date=excluded.due_date
    """, (user_id, item_id, item_type, interval, ease, reps, now.isoformat(), due.isoformat()))
    PROGRESS_DB.commit()
    logger.info(f"Updated SRS for user={user_id} item={item_id} success={success} next_due={due}")

# --- API Endpoints ---

@app.post("/api/progress")
async def record_progress(record: ProgressRecord):
    if not check_rate_limit(record.user_id):
        logger.warning(f"Rate limit exceeded for user={record.user_id}")
        raise HTTPException(status_code=429, detail="Too many requests. Please slow down.")
        
    try:
        update_srs(record.user_id, record.item_id, record.item_type, record.success)
        return {"status": "ok", "server_time": datetime.now(timezone.utc).isoformat()}
    except Exception as e:
        logger.error(f"Failed to record progress for user={record.user_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/api/progress/reset")
async def reset_progress(user_id: str):
    try:
        cursor = PROGRESS_DB.cursor()
        cursor.execute("DELETE FROM progress WHERE user_id = ?", (user_id,))
        PROGRESS_DB.commit()
        logger.info(f"Progress reset for user={user_id}")
        return {"status": "cleared"}
    except Exception as e:
        logger.error(f"Failed to reset progress for user={user_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/due_items")
async def get_due_items(user_id: str, limit: int = 50):
    if not check_rate_limit(user_id):
        raise HTTPException(status_code=429, detail="Rate limit exceeded")
        
    cursor = PROGRESS_DB.cursor()
    now = datetime.now(timezone.utc).isoformat()
    # Stable ordering: prioritize oldest due items first
    cursor.execute("""
        SELECT item_id, item_type FROM progress 
        WHERE user_id = ? AND due_date <= ? 
        ORDER BY due_date ASC 
        LIMIT ?
    """, (user_id, now, limit))
    rows = cursor.fetchall()
    logger.info(f"Fetched {len(rows)} due items for user={user_id}")
    return [{"id": r[0], "type": r[1]} for r in rows]

@app.post("/api/chat", response_model=ChatResponse)
async def chat(
    request: ChatRequest,
    http_request: Request,
    _: None = Depends(ai_guard_dependency),
):
    provider, allow_fallback = resolve_ai_provider_settings(http_request)
    # Resolve study set context
    context_content = ""
    if request.study_set_id and request.study_set_id in STUDY_SETS:
        context_content = "\n\n".join(STUDY_SETS[request.study_set_id].full_text_chunks)
        # Add condensed notes if available and not explicitly overridden by system instruction
        if request.condensed_notes and not request.system_instruction:
            context_content = request.condensed_notes + "\n\n" + context_content

    # Prepend context to user message or system instruction
    if context_content:
        if request.system_instruction:
            request.system_instruction = f"Context: {context_content}\n\n{request.system_instruction}"
        else:
            request.user_message = f"Based on the following context:\n{context_content}\n\n{request.user_message}"


    return await generate_chat_reply(request, ai_provider_override=provider, allow_fallback=allow_fallback)


@app.post("/api/generate/quiz", response_model=GenerateQuizResponse)
async def generate_quiz(
    request: GenerateQuizRequest,
    http_request: Request,
    _: None = Depends(ai_guard_dependency),
):
    context, depth = resolve_context_and_depth(request.context, request.study_set_id, request.depth)
    provider, allow_fallback = resolve_ai_provider_settings(http_request)
    questions = await generate_quiz_questions(
        context,
        request.chat_history,
        depth,
        ai_provider=provider or request.ai_provider,
        allow_fallback=allow_fallback,
    )
    return GenerateQuizResponse(quiz_questions=questions)


@app.post("/api/generate/flashcards", response_model=GenerateFlashcardsResponse)
async def generate_flashcards(
    request: GenerateFlashcardsRequest,
    http_request: Request,
    _: None = Depends(ai_guard_dependency),
):
    context, depth = resolve_context_and_depth(request.context, request.study_set_id, request.depth)
    provider, allow_fallback = resolve_ai_provider_settings(http_request)
    flashcards = await generate_flashcards_from_context(
        context,
        request.chat_history,
        request.count,
        depth,
        ai_provider=provider or request.ai_provider,
        allow_fallback=allow_fallback,
    )
    return GenerateFlashcardsResponse(flashcards=flashcards)




# Legacy /api/vocabulary and /api/vocabulary/search endpoints removed.
# Use /api/v2/vocabulary and /api/v2/search instead.



@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    print(f"Unhandled exception: {exc}")
    return JSONResponse(
        status_code=500,
        content={"detail": f"Server error: {str(exc)}"},
    )
