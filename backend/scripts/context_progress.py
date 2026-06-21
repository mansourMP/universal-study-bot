#!/usr/bin/env python3
"""Show context-translation progress from shard/result files."""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _load_json(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _read_progress(root: Path) -> tuple[int, int, int, int, int]:
    shards = sorted((root / "docs" / "context_shards_50").glob("context_shard_*.json"))
    results = sorted((root / "docs" / "context_results").glob("*.result.json"))

    jobs_total = 0
    for shard in shards:
        jobs_total += len(_load_json(shard).get("jobs", []))

    items_total = 0
    failures_total = 0
    for result in results:
        payload = _load_json(result)
        items_total += len(payload.get("items", []))
        failures_total += len(payload.get("failures", []))

    return len(shards), len(results), jobs_total, items_total, failures_total


def _print_once(root: Path) -> None:
    shards_n, results_n, jobs_total, items_total, failures_total = _read_progress(root)
    pct = (items_total / jobs_total * 100.0) if jobs_total else 0.0
    print(
        f"shards={results_n}/{shards_n} "
        f"items={items_total}/{jobs_total} ({pct:.2f}%) "
        f"fails={failures_total}"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Show context shard/result progress")
    parser.add_argument("--loop", type=int, default=0, help="Repeat every N seconds")
    args = parser.parse_args()

    root = _repo_root()
    if args.loop and args.loop > 0:
        while True:
            _print_once(root)
            time.sleep(args.loop)
    else:
        _print_once(root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
