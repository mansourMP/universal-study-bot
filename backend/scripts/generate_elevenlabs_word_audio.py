#!/usr/bin/env python3
"""Generate word-only audio files via ElevenLabs TTS.

Writes files to backend/static/audio as:
  word_<concept_id>.mp3

This script intentionally uses only `concepts.text` (single-word headword)
and does not generate sentence/dialog audio.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime as dt
import json
import os
import sqlite3
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Iterable, List, Tuple


API_BASE = "https://api.elevenlabs.io/v1/text-to-speech"
DEFAULT_MODEL_ID = "eleven_multilingual_v2"


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _connect(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    return conn


def _table_exists(conn: sqlite3.Connection, name: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
        (name,),
    ).fetchone()
    return bool(row)


def _read_only_ids(path: Path) -> set[str]:
    if not path.exists():
        raise FileNotFoundError(f"only-ids file not found: {path}")
    ids: set[str] = set()
    for raw in path.read_text(encoding="utf-8").splitlines():
        value = raw.strip()
        if not value or value.startswith("#"):
            continue
        ids.add(value)
    return ids


def _fetch_words(
    conn: sqlite3.Connection,
    *,
    path_only: bool,
    levels: list[str],
    only_ids: set[str] | None,
    limit: int | None,
) -> list[tuple[str, str]]:
    where: list[str] = ["c.text IS NOT NULL", "TRIM(c.text) != ''"]
    params: list[object] = []

    if path_only:
        where.append(
            "EXISTS (SELECT 1 FROM unit_concepts uc WHERE uc.concept_id = c.id AND uc.unit_id LIKE 'UNIT_HSK%_%')"
        )

    if levels:
        if not _table_exists(conn, "concept_curriculum_map"):
            raise RuntimeError("concept_curriculum_map table not found; cannot filter by --levels")
        placeholders = ",".join("?" for _ in levels)
        where.append(
            "EXISTS (SELECT 1 FROM concept_curriculum_map m "
            "WHERE m.concept_id = c.id AND m.standard = 'HSK3.0' "
            f"AND m.level IN ({placeholders}) AND m.band = 'core')"
        )
        params.extend(levels)

    query = (
        "SELECT c.id, c.text FROM concepts c "
        f"WHERE {' AND '.join(where)} "
        "ORDER BY c.id"
    )

    rows = conn.execute(query, params).fetchall()
    items = [(str(r["id"]), str(r["text"]).strip()) for r in rows]

    if only_ids is not None:
        items = [item for item in items if item[0] in only_ids]

    if limit is not None and limit > 0:
        items = items[:limit]

    return items


def _numeric_id_from_cid(cid: str) -> str | None:
    value = str(cid).strip()
    if value.startswith("W") and value[1:].isdigit():
        try:
            return str(int(value[1:]))
        except ValueError:
            return None
    if value.isdigit():
        return str(int(value))
    return None


def _audio_candidate_paths(out_dir: Path, cid: str) -> list[Path]:
    candidates: list[Path] = [out_dir / f"word_{cid}.mp3"]
    numeric = _numeric_id_from_cid(cid)
    if numeric is not None:
        numeric_path = out_dir / f"word_{numeric}.mp3"
        if numeric_path not in candidates:
            candidates.append(numeric_path)
    return candidates


def _target_audio_path(out_dir: Path, cid: str) -> Path:
    # Prefer numeric-style filenames for Wxxxxx IDs to stay compatible with
    # existing packs and older scripts that produced word_<numeric>.mp3.
    numeric = _numeric_id_from_cid(cid)
    if numeric is not None:
        return out_dir / f"word_{numeric}.mp3"
    return out_dir / f"word_{cid}.mp3"


def _has_existing_audio(out_dir: Path, cid: str) -> bool:
    return any(path.exists() for path in _audio_candidate_paths(out_dir, cid))


def _request_tts(
    *,
    api_key: str,
    voice_id: str,
    model_id: str,
    text: str,
    timeout_sec: int,
) -> bytes:
    url = f"{API_BASE}/{voice_id}"
    payload = {
        "text": text,
        "model_id": model_id,
    }
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "xi-api-key": api_key,
            "Content-Type": "application/json",
            "Accept": "audio/mpeg",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout_sec) as resp:
        return resp.read()


def _write_atomic(path: Path, content: bytes) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_bytes(content)
    tmp.replace(path)


def _worker(
    cid: str,
    text: str,
    *,
    out_dir: Path,
    api_key: str,
    voice_id: str,
    model_id: str,
    timeout_sec: int,
    retries: int,
    overwrite: bool,
) -> tuple[str, str, str]:
    out_path = _target_audio_path(out_dir, cid)
    if _has_existing_audio(out_dir, cid) and not overwrite:
        return (cid, "skipped", "exists")

    last_error = ""
    for attempt in range(1, retries + 1):
        try:
            audio = _request_tts(
                api_key=api_key,
                voice_id=voice_id,
                model_id=model_id,
                text=text,
                timeout_sec=timeout_sec,
            )
            if len(audio) < 256:
                raise RuntimeError(f"audio too small ({len(audio)} bytes)")
            _write_atomic(out_path, audio)
            return (cid, "ok", "")
        except urllib.error.HTTPError as e:
            try:
                detail = e.read().decode("utf-8", errors="ignore")[:500]
            except Exception:
                detail = ""
            last_error = f"HTTP {e.code}: {detail}"
            # Retry on 429/5xx, fail fast on other 4xx.
            if e.code not in (429, 500, 502, 503, 504):
                break
        except Exception as e:
            last_error = str(e)

        # Exponential backoff with a small floor.
        sleep_s = min(20.0, 0.6 * (2 ** (attempt - 1)))
        time.sleep(sleep_s)

    return (cid, "failed", last_error)


def _normalize_levels(raw: str | None) -> list[str]:
    if not raw:
        return []
    result: list[str] = []
    for part in raw.split(","):
        value = part.strip().upper()
        if not value:
            continue
        if value.startswith("HSK"):
            digits = "".join(ch for ch in value if ch.isdigit())
            if digits:
                value = f"HSK{int(digits)}"
            else:
                continue
        elif value.isdigit():
            value = f"HSK{int(value)}"
        else:
            continue
        if value not in result:
            result.append(value)
    return result


def _write_report(report_path: Path, payload: dict) -> None:
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate word-only ElevenLabs audio for concepts")
    parser.add_argument("--db", default="backend/learning_path.db")
    parser.add_argument("--output-dir", default="backend/static/audio")
    parser.add_argument("--voice-id", default=os.getenv("ELEVENLABS_VOICE_ID", ""))
    parser.add_argument("--model-id", default=DEFAULT_MODEL_ID)
    parser.add_argument("--api-key", default=os.getenv("ELEVENLABS_API_KEY", ""))
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--max-retries", type=int, default=5)
    parser.add_argument("--timeout-sec", type=int, default=60)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--path-only", action="store_true", help="Only concepts mapped to UNIT_HSK* path")
    parser.add_argument("--levels", default="", help="Comma-separated HSK levels, e.g. HSK1,HSK2 or 1,2")
    parser.add_argument("--only-ids", default="", help="Path to newline-delimited concept_id list")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not args.api_key:
        print("Missing API key. Set ELEVENLABS_API_KEY or pass --api-key")
        return 2
    if not args.voice_id:
        print("Missing voice id. Set ELEVENLABS_VOICE_ID or pass --voice-id")
        return 2

    repo_root = _repo_root()
    db_path = repo_root / args.db
    if not db_path.exists():
        print(f"DB not found: {db_path}")
        return 2

    out_dir = repo_root / args.output_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    only_ids: set[str] | None = None
    if args.only_ids:
        only_ids = _read_only_ids(repo_root / args.only_ids)

    levels = _normalize_levels(args.levels)
    limit = args.limit if args.limit > 0 else None

    conn = _connect(db_path)
    try:
        words = _fetch_words(
            conn,
            path_only=args.path_only,
            levels=levels,
            only_ids=only_ids,
            limit=limit,
        )
    finally:
        conn.close()

    total = len(words)
    if total == 0:
        print("No words matched filters.")
        return 0

    pending = 0
    for cid, _ in words:
        if args.overwrite or not _has_existing_audio(out_dir, cid):
            pending += 1

    print("--- ElevenLabs Word Audio ---")
    print(f"Total matched words: {total}")
    print(f"Pending generation: {pending}")
    print(f"Output dir: {out_dir}")
    print(f"Workers: {args.workers}")
    print("Mode: WORD-ONLY (concepts.text), no sentences")

    if args.dry_run or pending == 0:
        return 0

    ok = 0
    skipped = 0
    failed = 0
    failures: list[dict[str, str]] = []
    lock = threading.Lock()

    def _handle_result(result: tuple[str, str, str]) -> None:
        nonlocal ok, skipped, failed
        cid, status, detail = result
        with lock:
            if status == "ok":
                ok += 1
            elif status == "skipped":
                skipped += 1
            else:
                failed += 1
                failures.append({"concept_id": cid, "error": detail})

            done = ok + skipped + failed
            if done % 25 == 0 or done == pending:
                print(f"progress: {done}/{pending} ok={ok} skipped={skipped} failed={failed}")

    futures: list[concurrent.futures.Future] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.workers)) as ex:
        for cid, text in words:
            futures.append(
                ex.submit(
                    _worker,
                    cid,
                    text,
                    out_dir=out_dir,
                    api_key=args.api_key,
                    voice_id=args.voice_id,
                    model_id=args.model_id,
                    timeout_sec=max(5, args.timeout_sec),
                    retries=max(1, args.max_retries),
                    overwrite=args.overwrite,
                )
            )

        for fut in concurrent.futures.as_completed(futures):
            _handle_result(fut.result())

    ts = dt.datetime.utcnow().strftime("%Y-%m-%dT%H-%M-%SZ")
    report_path = repo_root / "docs" / "reports" / f"elevenlabs_word_audio_{ts}.json"
    _write_report(
        report_path,
        {
            "created_at_utc": ts,
            "db": str(db_path),
            "output_dir": str(out_dir),
            "total_matched": total,
            "pending": pending,
            "ok": ok,
            "skipped": skipped,
            "failed": failed,
            "path_only": bool(args.path_only),
            "levels": levels,
            "only_ids": args.only_ids or None,
            "limit": limit,
            "model_id": args.model_id,
            "voice_id": args.voice_id,
            "failures": failures[:1000],
        },
    )

    print("--- Done ---")
    print(f"ok={ok} skipped={skipped} failed={failed}")
    print(f"report={report_path}")

    return 1 if failed > 0 else 0


if __name__ == "__main__":
    raise SystemExit(main())
