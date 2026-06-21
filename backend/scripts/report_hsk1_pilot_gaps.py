#!/usr/bin/env python3
"""Report HSK1 pilot gaps (read-only).

Outputs:
  docs/reports/hsk1_pilot_gaps_YYYY-MM-DD.md
  docs/reports/hsk1_pilot_gaps_YYYY-MM-DD.json
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sqlite3
from collections import Counter
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _load_ids(path: Path) -> list[str]:
    if not path.exists():
        raise FileNotFoundError(path)
    return [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def _webp_dimensions(path: Path) -> tuple[int, int] | None:
    data = path.read_bytes()
    if len(data) < 16 or data[:4] != b"RIFF" or data[8:12] != b"WEBP":
        return None
    chunk = data[12:16]
    if chunk == b"VP8X" and len(data) >= 30:
        w = int.from_bytes(data[24:27], "little") + 1
        h = int.from_bytes(data[27:30], "little") + 1
        return w, h
    if chunk == b"VP8L" and len(data) >= 25:
        b0, b1, b2, b3 = data[21:25]
        w = (b0 | ((b1 & 0x3F) << 8)) + 1
        h = (((b1 & 0xC0) >> 6) | (b2 << 2) | ((b3 & 0x0F) << 10)) + 1
        return w, h
    return None


def _load_pack(path: Path) -> dict:
    if not path.exists():
        raise FileNotFoundError(path)
    return json.loads(path.read_text(encoding="utf-8"))


def _connect(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    return conn


def _variant_counts(db_path: Path, ids: list[str]) -> dict:
    if not db_path.exists():
        return {"status": "DB_MISSING"}
    conn = _connect(db_path)
    try:
        placeholders = ",".join(["?"] * len(ids))
        rows = conn.execute(
            f"SELECT word_id, COUNT(*) as c FROM word_exercises WHERE word_id IN ({placeholders}) GROUP BY word_id",
            ids,
        ).fetchall()
    finally:
        conn.close()
    counts = {str(r["word_id"]): int(r["c"]) for r in rows}
    full = {cid: counts.get(cid, 0) for cid in ids}
    dist = Counter()
    for v in full.values():
        if v >= 5:
            dist["5+"] += 1
        else:
            dist[str(v)] += 1
    total = len(full)
    avg = sum(full.values()) / total if total else 0
    return {
        "status": "OK",
        "distribution": dict(dist),
        "min": min(full.values()) if total else 0,
        "max": max(full.values()) if total else 0,
        "avg": round(avg, 3),
    }


def _coverage_images(repo_root: Path, ids: list[str]) -> dict:
    base = repo_root / "backend" / "static" / "images"
    placeholder_path = base / "_placeholder_1x1.webp"
    placeholder_hash = _sha256(placeholder_path) if placeholder_path.exists() else None
    matched = 0
    missing = 0
    placeholder = 0
    for cid in ids:
        path = base / f"word_{cid}.webp"
        if not path.exists():
            missing += 1
            continue
        matched += 1
        is_placeholder = False
        if placeholder_hash and _sha256(path) == placeholder_hash:
            is_placeholder = True
        dims = _webp_dimensions(path)
        if dims == (1, 1):
            is_placeholder = True
        if is_placeholder:
            placeholder += 1
    return {
        "matched": matched,
        "missing": missing,
        "placeholder": placeholder,
        "non_placeholder": matched - placeholder,
        "placeholder_hash_available": bool(placeholder_hash),
    }


def _coverage_audio(repo_root: Path, ids: list[str]) -> dict:
    base = repo_root / "backend" / "static" / "audio"
    placeholder_path = base / "_placeholder_template.mp3"
    placeholder_hash = _sha256(placeholder_path) if placeholder_path.exists() else None
    matched = 0
    missing = 0
    placeholder = 0
    for cid in ids:
        path = base / f"word_{cid}.mp3"
        if not path.exists():
            missing += 1
            continue
        matched += 1
        if placeholder_hash and _sha256(path) == placeholder_hash:
            placeholder += 1
    return {
        "matched": matched,
        "missing": missing,
        "placeholder": placeholder if placeholder_hash else None,
        "non_placeholder": (matched - placeholder) if placeholder_hash else None,
        "placeholder_hash_available": bool(placeholder_hash),
    }


def _missing_usage(repo_root: Path, ids: list[str]) -> dict:
    path = repo_root / "docs" / "reports" / "missing_usage_2026-02-02.txt"
    if not path.exists():
        return {"status": "MISSING_FILE", "path": str(path)}
    all_ids = [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    pilot = [cid for cid in all_ids if cid in set(ids)]
    return {
        "status": "OK",
        "path": str(path),
        "total": len(pilot),
        "ids": pilot,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Report HSK1 pilot gaps")
    parser.add_argument("--ids", default="docs/pilot/hsk1_pilot_ids.txt")
    parser.add_argument("--pack", default="docs/pilot/hsk1_exercises_v1.json")
    parser.add_argument("--db", default="backend/learning_path.db")
    args = parser.parse_args()

    repo_root = _repo_root()
    ids = _load_ids(repo_root / args.ids)
    pack = _load_pack(repo_root / args.pack)

    items = pack.get("items", [])
    by_type = Counter(item.get("exercise_type") for item in items)
    by_skill = Counter(item.get("skill") for item in items)
    by_level = Counter(item.get("level") for item in items)

    variant_depth = _variant_counts(repo_root / args.db, ids)
    image_cov = _coverage_images(repo_root, ids)
    audio_cov = _coverage_audio(repo_root, ids)
    missing_usage = _missing_usage(repo_root, ids)

    today = dt.date.today().isoformat()
    out_md = repo_root / "docs" / "reports" / f"hsk1_pilot_gaps_{today}.md"
    out_json = repo_root / "docs" / "reports" / f"hsk1_pilot_gaps_{today}.json"

    payload = {
        "date": today,
        "total_ids": len(ids),
        "pack_counts": {
            "total_items": len(items),
            "by_type": dict(by_type),
            "by_skill": dict(by_skill),
            "by_level": dict(by_level),
        },
        "missing_usage": missing_usage,
        "image_coverage": image_cov,
        "audio_coverage": audio_cov,
        "variant_depth": variant_depth,
    }

    out_json.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")

    lines = [
        "# HSK1 Pilot Gaps",
        "",
        f"Date: {today}",
        "",
        "## Pack counts",
        f"- Total items: {len(items)}",
        f"- By type: {dict(by_type)}",
        f"- By skill: {dict(by_skill)}",
        f"- By level: {dict(by_level)}",
        "",
        "## Missing usage sentences (HSK1 subset)",
    ]
    if missing_usage.get("status") != "OK":
        lines.append(f"- Status: {missing_usage.get('status')}")
        lines.append(f"- Path: {missing_usage.get('path')}")
    else:
        lines.append(f"- Count: {missing_usage.get('total')}")
        preview = missing_usage.get("ids", [])[:50]
        lines.append(f"- First 50 IDs: {preview}")
    lines += [
        "",
        "## Image coverage (HSK1 subset)",
        f"- Matched: {image_cov['matched']}",
        f"- Missing: {image_cov['missing']}",
        f"- Placeholder: {image_cov['placeholder']}",
        f"- Non-placeholder: {image_cov['non_placeholder']}",
        "",
        "## Audio coverage (HSK1 subset)",
        f"- Matched: {audio_cov['matched']}",
        f"- Missing: {audio_cov['missing']}",
        f"- Placeholder: {audio_cov['placeholder']}",
        f"- Non-placeholder: {audio_cov['non_placeholder']}",
        "",
        "## Variant depth (HSK1 subset)",
        f"- Status: {variant_depth.get('status')}",
    ]
    if variant_depth.get("status") == "OK":
        lines += [
            f"- Distribution: {variant_depth.get('distribution')}",
            f"- Min: {variant_depth.get('min')}",
            f"- Max: {variant_depth.get('max')}",
            f"- Avg: {variant_depth.get('avg')}",
        ]
    out_md.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"Wrote {out_md}")
    print(f"Wrote {out_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
