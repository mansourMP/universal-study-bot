#!/usr/bin/env python3
"""Report passage coverage by unit based on content/passages files."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _load_manifest(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def main() -> int:
    parser = argparse.ArgumentParser(description="Report passage coverage by unit")
    parser.add_argument("--manifest", default="backend/content/paths/zh_standard.json")
    args = parser.parse_args()

    repo_root = _repo_root()
    manifest_path = repo_root / args.manifest
    passages_dir = repo_root / "backend" / "content" / "passages"

    if not manifest_path.exists():
        print(f"Manifest not found: {manifest_path}")
        return 1

    manifest = _load_manifest(manifest_path)
    unit_ids = []
    for realm in manifest.get("realms", {}).values():
        for unit in realm.get("units", []):
            unit_ids.append(str(unit.get("unit_number")))

    matched = 0
    missing = []
    for uid in unit_ids:
        path = passages_dir / f"unit_{uid}_passage.json"
        if path.exists():
            matched += 1
        else:
            missing.append(uid)

    print("--- Passage Coverage Report ---")
    print(f"Units in manifest: {len(unit_ids)}")
    print(f"Passages found: {matched}")
    print(f"Missing passages: {len(missing)}")
    if missing:
        print("Top 50 missing unit_ids:")
        for uid in missing[:50]:
            print(uid)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
