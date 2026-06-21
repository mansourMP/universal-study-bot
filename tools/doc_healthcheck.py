#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]

DOC_FILES = [
    REPO_ROOT / "README.md",
    REPO_ROOT / "BRAIN_SOVEREIGNTY_STATE.md",
    REPO_ROOT / "docs" / "PROJECT_COMPASS.md",
    REPO_ROOT / "docs" / "PROJECT_COMPASS_TEMPLATE.md",
    REPO_ROOT / "docs" / "ASSET_STYLE_GUIDE.md",
]

PATH_REGEX = re.compile(
    r"(?<!\w)(?:backend|docs|dragon_chinese|assets|tools|\.github)/[A-Za-z0-9_./-]+"
)

def _is_template(path: str) -> bool:
    if any(token in path for token in ("{", "}", "*", "YYYY", "concept_id")):
        return True
    if path.endswith("word_"):
        return True
    if ".venv" in path or "/venv/" in path:
        return True
    return False

def _clean_path(path: str) -> str:
    return path.rstrip(".,:;)]}\"'")

def main() -> None:
    missing: list[tuple[Path, str]] = []

    for doc in DOC_FILES:
        try:
            lines = doc.read_text(encoding="utf-8").splitlines()
        except Exception:
            continue

        candidates = set()
        in_code = False
        for line in lines:
            if line.strip().startswith("```"):
                in_code = not in_code
                continue
            if in_code:
                continue
            if "UNKNOWN" in line or "TODO" in line or "ARCHIVED" in line:
                continue
            # Backtick paths
            for match in re.findall(r"`([^`]+)`", line):
                if match.startswith("http"):
                    continue
                for token in match.split():
                    if "/" in token:
                        candidates.add(token)
            # Plain paths
            for match in PATH_REGEX.findall(line):
                candidates.add(match)

        for raw in candidates:
            path = _clean_path(raw)
            if _is_template(path):
                continue
            abs_path = REPO_ROOT / path
            if not abs_path.exists():
                missing.append((doc, path))

    if not missing:
        print("Doc health check OK")
        return

    print("Doc health check FAILED. Missing references:")
    for doc, path in missing:
        rel = doc.relative_to(REPO_ROOT)
        print(f"- {rel}: {path}")

if __name__ == "__main__":
    main()
