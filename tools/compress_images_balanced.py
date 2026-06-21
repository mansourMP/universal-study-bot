#!/usr/bin/env python3
"""Quality-safe WebP compression pipeline with CSV + JSON reports.

Default policy:
- process only .webp files
- process files >= 250 KB
- keep max dimension <= 1024
- quality=86, method=6
- apply only if savings >= 10%

Dry-run by default; pass --apply to overwrite originals.
"""

from __future__ import annotations

import argparse
import csv
import json
import subprocess
import time
from dataclasses import dataclass, asdict
from datetime import datetime, UTC
from pathlib import Path


DEFAULT_DIRS = [
    "images omnis/vocab_images/assets_images",
    "assets/images",
    "backend/static/images",
]


@dataclass
class RowReport:
    path: str
    bytes_before: int
    bytes_after: int
    savings_pct: float
    width: int
    height: int
    resized: bool
    action: str
    error: str


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument(
        "--dirs",
        nargs="*",
        default=DEFAULT_DIRS,
        help="Directories to scan recursively.",
    )
    p.add_argument(
        "--extensions",
        nargs="*",
        default=[".webp"],
        help="Allowed file extensions (default: .webp).",
    )
    p.add_argument("--min-input-kb", type=int, default=250)
    p.add_argument("--min-savings-pct", type=float, default=10.0)
    p.add_argument("--max-dim", type=int, default=1024)
    p.add_argument("--quality", type=int, default=86)
    p.add_argument("--method", type=int, default=6)
    p.add_argument("--limit", type=int, default=0, help="0 = no limit")
    p.add_argument("--apply", action="store_true")
    p.add_argument("--report-dir", default="docs/reports")
    p.add_argument(
        "--progress-every",
        type=int,
        default=100,
        help="Print progress every N processed eligible files (0 disables).",
    )
    return p.parse_args()


def run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, capture_output=True, text=True, check=False)


def image_dims(path: Path) -> tuple[int, int]:
    probe = run(
        [
            "ffprobe",
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height",
            "-of",
            "csv=p=0:s=x",
            str(path),
        ]
    )
    if probe.returncode != 0:
        return 0, 0
    out = (probe.stdout or "").strip()
    if "x" not in out:
        return 0, 0
    w_str, h_str = out.split("x", 1)
    try:
        return int(w_str), int(h_str)
    except ValueError:
        return 0, 0


def encode_candidate(
    src: Path,
    dst: Path,
    *,
    quality: int,
    method: int,
    max_dim: int,
    width: int,
    height: int,
) -> tuple[bool, bool, str]:
    resized = bool(width > max_dim or height > max_dim)
    cmd = [
        "cwebp",
        "-quiet",
        "-q",
        str(quality),
        "-m",
        str(method),
    ]
    if resized:
        # Preserve aspect ratio while capping max dimension.
        if width >= height:
            out_w = max_dim
            out_h = max(1, int(round(height * max_dim / width)))
        else:
            out_h = max_dim
            out_w = max(1, int(round(width * max_dim / height)))
        cmd.extend(["-resize", str(out_w), str(out_h)])
    cmd.extend([str(src), "-o", str(dst)])
    proc = run(cmd)
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "").strip()
        return False, resized, err[:400]
    return dst.exists(), resized, ""


def discover_files(root: Path, allowed_exts: set[str]) -> list[Path]:
    if not root.exists():
        return []
    out: list[Path] = []
    for p in root.rglob("*"):
        if not p.is_file():
            continue
        if p.suffix.lower() not in allowed_exts:
            continue
        out.append(p)
    return sorted(out)


def main() -> int:
    args = parse_args()
    repo = Path(__file__).resolve().parents[1]
    report_dir = (repo / args.report_dir).resolve()
    report_dir.mkdir(parents=True, exist_ok=True)

    allowed = {e.lower() if e.startswith(".") else f".{e.lower()}" for e in args.extensions}
    min_bytes = int(args.min_input_kb * 1024)

    files: list[Path] = []
    for d in args.dirs:
        files.extend(discover_files((repo / d).resolve(), allowed))
    files = sorted(set(files))
    if args.limit and args.limit > 0:
        files = files[: args.limit]

    rows: list[RowReport] = []
    counters = {
        "total_seen": len(files),
        "eligible": 0,
        "processed": 0,
        "replaced": 0,
        "skip_too_small": 0,
        "skip_not_smaller": 0,
        "skip_small_gain": 0,
        "failed": 0,
        "saved_bytes": 0,
    }
    for p in files:
        try:
            if p.stat().st_size >= min_bytes:
                counters["eligible"] += 1
        except OSError:
            continue

    start_ts = time.time()
    mode_label = "APPLY" if args.apply else "DRY-RUN"
    print(
        f"[compress] mode={mode_label} total={counters['total_seen']} "
        f"eligible={counters['eligible']} min_input_kb={args.min_input_kb} "
        f"quality={args.quality} max_dim={args.max_dim}",
        flush=True,
    )

    for src in files:
        before = src.stat().st_size
        width, height = image_dims(src)
        if before < min_bytes:
            counters["skip_too_small"] += 1
            rows.append(
                RowReport(
                    path=str(src.relative_to(repo)),
                    bytes_before=before,
                    bytes_after=before,
                    savings_pct=0.0,
                    width=width,
                    height=height,
                    resized=False,
                    action="skip_too_small",
                    error="",
                )
            )
            continue

        tmp = src.with_name(f"{src.name}.tmp.webp")
        ok, resized, err = encode_candidate(
            src,
            tmp,
            quality=args.quality,
            method=args.method,
            max_dim=args.max_dim,
            width=width,
            height=height,
        )
        counters["processed"] += 1
        if args.progress_every > 0 and counters["processed"] % args.progress_every == 0:
            elapsed = max(1.0, time.time() - start_ts)
            rate = counters["processed"] / elapsed
            remaining = max(0, counters["eligible"] - counters["processed"])
            eta_sec = int(remaining / rate) if rate > 0 else 0
            print(
                f"[compress] processed={counters['processed']}/{counters['eligible']} "
                f"rate={rate:.2f}/s eta={eta_sec}s "
                f"replaced={counters['replaced']} failed={counters['failed']}",
                flush=True,
            )
        if not ok:
            counters["failed"] += 1
            if tmp.exists():
                tmp.unlink(missing_ok=True)
            rows.append(
                RowReport(
                    path=str(src.relative_to(repo)),
                    bytes_before=before,
                    bytes_after=before,
                    savings_pct=0.0,
                    width=width,
                    height=height,
                    resized=resized,
                    action="failed",
                    error=err,
                )
            )
            continue

        after = tmp.stat().st_size
        if after >= before:
            counters["skip_not_smaller"] += 1
            tmp.unlink(missing_ok=True)
            rows.append(
                RowReport(
                    path=str(src.relative_to(repo)),
                    bytes_before=before,
                    bytes_after=after,
                    savings_pct=0.0,
                    width=width,
                    height=height,
                    resized=resized,
                    action="skip_not_smaller",
                    error="",
                )
            )
            continue

        savings_pct = ((before - after) * 100.0) / float(before)
        if savings_pct < args.min_savings_pct:
            counters["skip_small_gain"] += 1
            tmp.unlink(missing_ok=True)
            rows.append(
                RowReport(
                    path=str(src.relative_to(repo)),
                    bytes_before=before,
                    bytes_after=after,
                    savings_pct=round(savings_pct, 3),
                    width=width,
                    height=height,
                    resized=resized,
                    action="skip_small_gain",
                    error="",
                )
            )
            continue

        action = "planned_replace"
        if args.apply:
            tmp.replace(src)
            action = "replaced"
            counters["replaced"] += 1
            counters["saved_bytes"] += (before - after)
        else:
            tmp.unlink(missing_ok=True)

        rows.append(
            RowReport(
                path=str(src.relative_to(repo)),
                bytes_before=before,
                bytes_after=after,
                savings_pct=round(savings_pct, 3),
                width=width,
                height=height,
                resized=resized,
                action=action,
                error="",
            )
        )

    ts = datetime.now(UTC).strftime("%Y-%m-%dT%H-%M-%SZ")
    base = f"image_compress_balanced_{ts}"
    csv_path = report_dir / f"{base}.csv"
    json_path = report_dir / f"{base}.json"

    with csv_path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(asdict(rows[0]).keys()) if rows else list(RowReport(
            path="",
            bytes_before=0,
            bytes_after=0,
            savings_pct=0.0,
            width=0,
            height=0,
            resized=False,
            action="",
            error="",
        ).__dict__.keys()))
        writer.writeheader()
        for row in rows:
            writer.writerow(asdict(row))

    summary = {
        "ok": True,
        "mode": "apply" if args.apply else "dry_run",
        "dirs": args.dirs,
        "extensions": sorted(allowed),
        "policy": {
            "min_input_kb": args.min_input_kb,
            "min_savings_pct": args.min_savings_pct,
            "max_dim": args.max_dim,
            "quality": args.quality,
            "method": args.method,
        },
        "counts": counters,
        "report_csv": str(csv_path.resolve()),
        "report_json": str(json_path.resolve()),
    }
    json_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
