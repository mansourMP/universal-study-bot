import os
import tempfile
from functools import lru_cache
from pathlib import Path
from typing import List, Optional

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from pydantic import BaseModel

from auth import get_user_id, verify_api_key

try:
    from faster_whisper import WhisperModel
except Exception:  # pragma: no cover - dependency/runtime guard
    WhisperModel = None  # type: ignore

router = APIRouter(prefix="/api/v2/voice", tags=["voice"])


class VoiceSegment(BaseModel):
    start: float
    end: float
    text: str


class VoiceTranscribeResponse(BaseModel):
    text: str
    detected_language: Optional[str] = None
    model: str
    engine: str = "faster-whisper"
    segments: List[VoiceSegment]


def _stt_model_name() -> str:
    return os.getenv("VOICE_STT_MODEL", "small")


def _stt_device() -> str:
    return os.getenv("VOICE_STT_DEVICE", "cpu")


def _stt_compute_type() -> str:
    return os.getenv("VOICE_STT_COMPUTE_TYPE", "int8")


@lru_cache(maxsize=1)
def _load_model() -> "WhisperModel":
    if WhisperModel is None:
        raise RuntimeError(
            "faster-whisper is not installed. Install in backend/.venv first."
        )
    return WhisperModel(
        _stt_model_name(),
        device=_stt_device(),
        compute_type=_stt_compute_type(),
    )


@router.get("/health")
async def voice_health(
    preload: bool = Query(
        default=False,
        description="When true, attempts to load STT model to verify runtime readiness.",
    ),
    user_id: str = Depends(get_user_id),
    _: str = Depends(verify_api_key),
):
    _ = user_id  # explicitly consume dependency
    if not preload:
        return {
            "ok": True,
            "engine": "faster-whisper",
            "model": _stt_model_name(),
            "device": _stt_device(),
            "compute_type": _stt_compute_type(),
            "loaded": False,
            "note": "Set preload=true to verify model load/runtime.",
        }

    try:
        _load_model()
        return {
            "ok": True,
            "engine": "faster-whisper",
            "model": _stt_model_name(),
            "device": _stt_device(),
            "compute_type": _stt_compute_type(),
            "loaded": True,
        }
    except Exception as e:
        return {
            "ok": False,
            "engine": "faster-whisper",
            "error": str(e),
            "model": _stt_model_name(),
            "loaded": False,
        }


@router.post("/transcribe", response_model=VoiceTranscribeResponse)
async def transcribe_voice(
    audio: UploadFile = File(...),
    language: Optional[str] = Query(
        default=None,
        description="Optional language hint, e.g. zh, en. Auto-detect when omitted.",
    ),
    beam_size: int = Query(default=5, ge=1, le=10),
    user_id: str = Depends(get_user_id),
    _: str = Depends(verify_api_key),
):
    _ = user_id  # dependency side effect/auth check only

    filename = audio.filename or "voice_input.webm"
    ext = Path(filename).suffix or ".webm"
    raw = await audio.read()
    if not raw:
        raise HTTPException(status_code=400, detail="Empty audio upload.")

    try:
        model = _load_model()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"STT model unavailable: {e}")

    with tempfile.NamedTemporaryFile(suffix=ext, delete=True) as tmp:
        tmp.write(raw)
        tmp.flush()
        try:
            segments_iter, info = model.transcribe(
                tmp.name,
                language=language,
                beam_size=beam_size,
                vad_filter=True,
            )
            segments_list = list(segments_iter)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Transcription failed: {e}")

    normalized_segments: List[VoiceSegment] = [
        VoiceSegment(
            start=float(seg.start),
            end=float(seg.end),
            text=(seg.text or "").strip(),
        )
        for seg in segments_list
        if (seg.text or "").strip()
    ]
    full_text = " ".join(seg.text for seg in normalized_segments).strip()

    return VoiceTranscribeResponse(
        text=full_text,
        detected_language=getattr(info, "language", None),
        model=_stt_model_name(),
        segments=normalized_segments,
    )
