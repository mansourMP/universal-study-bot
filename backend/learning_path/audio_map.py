"""Audio mapping utilities for Learning Path concepts."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Dict, Optional


AUDIO_MAP_PATH = Path(__file__).parent.parent / "content" / "audio_map.json"


def load_audio_map() -> Dict[str, str]:
    """Load explicit concept_id -> audio_url mappings (if present)."""
    if AUDIO_MAP_PATH.exists():
        try:
            data = json.loads(AUDIO_MAP_PATH.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                return {str(k): str(v) for k, v in data.items()}
        except Exception:
            return {}
    return {}


def resolve_audio_url(concept_id: str, mapping: Optional[Dict[str, str]] = None) -> str:
    """Resolve audio URL for a concept id.

    Default strategy: use TTS endpoint (/api/v2/audio/{concept_id}).
    If audio_map.json provides a mapping, it overrides the default.
    """
    cid = str(concept_id)
    if mapping is None:
        mapping = load_audio_map()
    return mapping.get(cid, f"/api/v2/audio/{cid}")
