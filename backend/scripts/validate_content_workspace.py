#!/usr/bin/env python3
"""Validate required content workspace structure and manifest templates."""

from __future__ import annotations

import json
from pathlib import Path


REQUIRED_DIRS = [
    "backend/content/workspace/words/source",
    "backend/content/workspace/words/normalized",
    "backend/content/workspace/localizations/raw",
    "backend/content/workspace/localizations/validated",
    "backend/content/workspace/localizations/approved",
    "backend/content/workspace/sentences/raw",
    "backend/content/workspace/sentences/validated",
    "backend/content/workspace/sentences/approved",
    "backend/content/workspace/dialogues/raw",
    "backend/content/workspace/dialogues/validated",
    "backend/content/workspace/dialogues/approved",
    "backend/content/workspace/manifests",
]

REQUIRED_MANIFESTS = [
    "backend/content/workspace/manifests/content_run.template.json",
    "backend/content/workspace/manifests/sentence_batch.template.json",
    "backend/content/workspace/manifests/dialogue_batch.template.json",
]

REQUIRED_KEYS = [
    "batch_id",
    "created_at",
    "provider",
    "model",
    "status",
]


def main() -> int:
    root = Path(__file__).resolve().parents[2]

    missing_dirs = [p for p in REQUIRED_DIRS if not (root / p).is_dir()]
    missing_files = [p for p in REQUIRED_MANIFESTS if not (root / p).is_file()]
    invalid_json: list[str] = []
    missing_keys: dict[str, list[str]] = {}

    for rel in REQUIRED_MANIFESTS:
        path = root / rel
        if not path.is_file():
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            invalid_json.append(rel)
            continue
        need = [k for k in REQUIRED_KEYS if k not in data]
        if need:
            missing_keys[rel] = need

    ok = not (missing_dirs or missing_files or invalid_json or missing_keys)
    payload = {
        "ok": ok,
        "missing_dirs": missing_dirs,
        "missing_files": missing_files,
        "invalid_json": invalid_json,
        "missing_manifest_keys": missing_keys,
    }
    print(json.dumps(payload, ensure_ascii=False))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

