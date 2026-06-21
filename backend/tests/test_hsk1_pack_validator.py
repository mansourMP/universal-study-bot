import subprocess
import sys
from pathlib import Path


def test_validate_hsk1_pack():
    repo_root = Path(__file__).resolve().parents[2]
    cmd = [
        sys.executable,
        "backend/scripts/validate_hsk1_pack.py",
        "--pack",
        "docs/pilot/hsk1_exercises_v1.json",
    ]
    subprocess.check_call(cmd, cwd=repo_root)
