#!/usr/bin/env python3
"""Validate asset availability for audio/images and optionally copy to static.

Default: read-only validation. Use --copy to copy assets into backend/static/*.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sqlite3
from pathlib import Path
from typing import Dict, Iterable, List


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _connect(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    return conn


def _collect_concept_ids(conn: sqlite3.Connection) -> list[str]:
    rows = conn.execute("SELECT DISTINCT concept_id FROM unit_concepts").fetchall()
    return [str(r[0]) for r in rows]


def _load_manifest(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _read_only_ids(path: Path) -> list[str]:
    return [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]


def _resolve_manifest_path(repo_root: Path, raw: str) -> Path:
    p = Path(raw)
    if p.is_absolute():
        return p
    return repo_root / raw


def _resolve_asset(cid: str, manifest: dict, key: str, assets_dir: Path, ext: str, repo_root: Path) -> Path | None:
    mapping = manifest.get(key, {}) if isinstance(manifest, dict) else {}
    if isinstance(mapping, dict) and cid in mapping:
        candidate = _resolve_manifest_path(repo_root, str(mapping[cid]))
        return candidate if candidate.exists() else None
    candidate = assets_dir / f"word_{cid}.{ext}"
    return candidate if candidate.exists() else None


def _summarize(label: str, ready: List[str], missing: List[str]) -> None:
    print(f"{label} ready: {len(ready)}")
    print(f"{label} missing: {len(missing)}")
    if missing:
        print(f"Top 50 missing {label} IDs:")
        for cid in missing[:50]:
            print(cid)


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate asset manifest and optional copy")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--manifest", default="assets/content_pack_v1.json")
    parser.add_argument("--audio-dir", default="assets/audio")
    parser.add_argument("--image-dir", default="assets/images")
    parser.add_argument("--only-ids", help="Path to newline-delimited concept_ids to include")
    parser.add_argument("--copy", action="store_true", help="Copy assets into backend/static/*")
    args = parser.parse_args()

    repo_root = _repo_root()
    db_path = repo_root / args.db
    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 1

    conn = _connect(db_path)
    try:
        concept_ids = _collect_concept_ids(conn)
    finally:
        conn.close()

    if args.only_ids:
        only_path = repo_root / args.only_ids
        if not only_path.exists():
            print(f"only-ids file not found: {only_path}")
            return 1
        allowed = set(_read_only_ids(only_path))
        concept_ids = [cid for cid in concept_ids if cid in allowed]

    manifest = _load_manifest(repo_root / args.manifest)
    audio_dir = repo_root / args.audio_dir
    image_dir = repo_root / args.image_dir

    audio_ready: List[str] = []
    audio_missing: List[str] = []
    image_ready: List[str] = []
    image_missing: List[str] = []

    for cid in concept_ids:
        audio_src = _resolve_asset(cid, manifest, "audio", audio_dir, "mp3", repo_root)
        if audio_src:
            audio_ready.append(cid)
            if args.copy:
                dst = repo_root / "backend" / "static" / "audio" / f"word_{cid}.mp3"
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(audio_src, dst)
        else:
            audio_missing.append(cid)

        image_src = _resolve_asset(cid, manifest, "images", image_dir, "webp", repo_root)
        if image_src:
            image_ready.append(cid)
            if args.copy:
                dst = repo_root / "backend" / "static" / "images" / f"word_{cid}.webp"
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(image_src, dst)
        else:
            image_missing.append(cid)

    print("--- Asset Manifest Validation ---")
    print(f"Concept IDs evaluated: {len(concept_ids)}")
    _summarize("Audio", audio_ready, audio_missing)
    _summarize("Image", image_ready, image_missing)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
