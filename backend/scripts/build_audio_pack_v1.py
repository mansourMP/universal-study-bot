#!/usr/bin/env python3
"""Build Content Pack v1 audio files from external assets.

Inputs:
- assets/content_pack_v1.json (optional)
- assets/audio_v1/{concept_id}.mp3 (fallback)

Outputs:
- backend/static/audio/word_{concept_id}.mp3
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sqlite3


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
        if isinstance(data, dict):
            return data
    except Exception:
        return {}
    return {}


def _resolve_audio_source(
    cid: str,
    manifest: dict,
    repo_root: Path,
    primary_dir: Path,
    fallback_dir: Path,
) -> Path | None:
    audio_map = manifest.get("audio", {}) if isinstance(manifest, dict) else {}
    if isinstance(audio_map, dict) and cid in audio_map:
        candidate = repo_root / audio_map[cid]
        return candidate if candidate.exists() else None
    candidate = primary_dir / f"word_{cid}.mp3"
    if candidate.exists():
        return candidate
    candidate = fallback_dir / f"{cid}.mp3"
    return candidate if candidate.exists() else None


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description="Build Content Pack v1 audio from external assets")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--manifest", default="assets/content_pack_v1.json")
    parser.add_argument("--only-ids", help="Path to newline-delimited concept_ids to include")
    parser.add_argument("--input-dir", default="assets/audio_v1")
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--strict", action="store_true")
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
        allowed = {
            line.strip()
            for line in only_path.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.strip().startswith("#")
        }
        concept_ids = [cid for cid in concept_ids if cid in allowed]

    manifest = _load_manifest(repo_root / args.manifest)
    input_dir = repo_root / args.input_dir
    primary_dir = repo_root / "assets" / "audio"
    output_dir = repo_root / "backend" / "static" / "audio"
    output_dir.mkdir(parents=True, exist_ok=True)
    placeholder_path = output_dir / "_placeholder_template.mp3"
    placeholder_hash = _sha256(placeholder_path) if placeholder_path.exists() else None

    copied = 0
    skipped = 0
    missing = []
    placeholder = []

    for cid in concept_ids:
        src = _resolve_audio_source(cid, manifest, repo_root, primary_dir, input_dir)
        dst = output_dir / f"word_{cid}.mp3"
        if src is None:
            missing.append(cid)
            continue
        if dst.exists() and not args.overwrite:
            skipped += 1
        else:
            shutil.copyfile(src, dst)
            copied += 1
        if placeholder_hash and _sha256(dst) == placeholder_hash:
            placeholder.append(cid)

    print("--- Audio Pack v1 Build ---")
    print(f"Concept IDs: {len(concept_ids)}")
    print(f"Copied files: {copied}")
    print(f"Skipped existing: {skipped}")
    print(f"Missing audio IDs: {len(missing)}")
    print(f"Placeholder audio IDs: {len(placeholder)}")
    if missing:
        print("Top 50 missing IDs:")
        for cid in missing[:50]:
            print(cid)
    if placeholder:
        print("Top 50 placeholder IDs:")
        for cid in placeholder[:50]:
            print(cid)

    if args.strict and missing:
        print("ERROR: Missing audio in strict mode.")
        return 2
    if args.strict and placeholder:
        print("ERROR: Placeholder audio present in strict mode.")
        return 3

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
