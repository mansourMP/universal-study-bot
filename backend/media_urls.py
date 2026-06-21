"""Helpers for image URL output policy.

Env flags:
- IMAGE_ORIGIN_MODE: local_static | cdn_prefixed
- IMAGE_CDN_BASE_URL: base URL used when mode is cdn_prefixed
- IMAGE_PATH_VERSION: optional query tag appended to relative image paths
"""

from __future__ import annotations

import os
from urllib.parse import quote_plus


def _settings() -> tuple[str, str, str]:
    mode = str(os.getenv("IMAGE_ORIGIN_MODE", "local_static")).strip().lower()
    cdn_base = str(os.getenv("IMAGE_CDN_BASE_URL", "")).strip().rstrip("/")
    path_version = str(os.getenv("IMAGE_PATH_VERSION", "")).strip()
    return mode, cdn_base, path_version


def normalize_image_url(raw_url: str | None) -> str | None:
    """Normalize image URL according to runtime policy."""
    raw = str(raw_url or "").strip()
    if not raw:
        return None

    # Keep absolute URLs as-is.
    if raw.startswith("http://") or raw.startswith("https://"):
        return raw

    mode, cdn_base, path_version = _settings()
    path = raw if raw.startswith("/") else f"/{raw}"
    if path_version:
        sep = "&" if "?" in path else "?"
        path = f"{path}{sep}v={quote_plus(path_version)}"

    if mode == "cdn_prefixed" and cdn_base:
        return f"{cdn_base}{path}"
    return path


def concept_image_url(public_id: str) -> str | None:
    """Build canonical image endpoint URL for a concept public id."""
    cid = str(public_id or "").strip()
    if not cid:
        return None
    return normalize_image_url(f"/api/v2/image/{cid}")

