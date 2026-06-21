#!/usr/bin/env python3
from __future__ import annotations

import ast
from pathlib import Path
from typing import Iterable, Optional, Set

REPO_ROOT = Path(__file__).resolve().parents[1]
BACKEND_DIR = REPO_ROOT / "backend"

ENTRYPOINTS = [
    BACKEND_DIR / "main.py",
]

LOCAL_PREFIXES = (
    "api",
    "learning_path",
    "services",
    "content_config",
    "auth",
    "cache_manager",
    "db_v2",
)


def is_local_module(mod: str) -> bool:
    return mod.startswith(LOCAL_PREFIXES)


def module_to_path(mod: str) -> Optional[Path]:
    parts = mod.split(".")
    p1 = BACKEND_DIR.joinpath(*parts).with_suffix(".py")
    if p1.exists():
        return p1
    p2 = BACKEND_DIR.joinpath(*parts) / "__init__.py"
    if p2.exists():
        return p2
    return None


def parse_imports(pyfile: Path) -> Set[str]:
    try:
        src = pyfile.read_text(encoding="utf-8")
    except Exception:
        return set()
    try:
        tree = ast.parse(src, filename=str(pyfile))
    except SyntaxError:
        return set()

    mods: Set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for n in node.names:
                mods.add(n.name)
        elif isinstance(node, ast.ImportFrom):
            if node.module:
                if node.level and node.level > 0:
                    continue
                mods.add(node.module)
    return mods


def walk_used_files(entrypoints: Iterable[Path]) -> Set[Path]:
    used: Set[Path] = set()
    stack = list(entrypoints)

    while stack:
        f = stack.pop()
        if not f.exists():
            continue
        if f in used:
            continue
        used.add(f)

        for mod in parse_imports(f):
            if not is_local_module(mod):
                continue
            candidates = [mod]
            if "." in mod:
                candidates.append(mod.split(".")[0])

            for c in candidates:
                p = module_to_path(c)
                if p and p not in used:
                    stack.append(p)

    return used


def all_backend_pyfiles() -> Set[Path]:
    return {p for p in BACKEND_DIR.rglob("*.py") if "path/to/venv" not in str(p)}


def main() -> None:
    used = walk_used_files(ENTRYPOINTS)
    allpy = all_backend_pyfiles()

    def is_exempt(p: Path) -> bool:
        s = str(p)
        return any([
            "/tests/" in s,
            "/scripts/" in s,
        ])

    unused = sorted([p for p in (allpy - used) if not is_exempt(p)])

    print("=== USED (runtime-imported) ===")
    for p in sorted(used):
        print(p.relative_to(REPO_ROOT))

    print("\n=== UNUSED CANDIDATES (not referenced by runtime imports) ===")
    for p in unused:
        print(p.relative_to(REPO_ROOT))

    print(f"\nUsed: {len(used)} files | Unused candidates: {len(unused)} files")


if __name__ == "__main__":
    main()
