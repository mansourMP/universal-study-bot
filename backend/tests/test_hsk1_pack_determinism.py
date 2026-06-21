import json
import subprocess
import sys
from pathlib import Path
from tempfile import TemporaryDirectory


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _run_generator(out_path: Path) -> dict:
    repo_root = _repo_root()
    cmd = [
        sys.executable,
        "backend/scripts/generate_hsk1_exercises_pack.py",
        "--out",
        str(out_path),
        "--no-copy-assets",
    ]
    subprocess.check_call(cmd, cwd=repo_root)
    data = json.loads(out_path.read_text(encoding="utf-8"))
    data.pop("generated_at", None)
    return data


def test_hsk1_pack_deterministic():
    with TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        first = _run_generator(tmp_path / "pack_a.json")
        second = _run_generator(tmp_path / "pack_b.json")

    assert first["schema_version"] == second["schema_version"]
    assert first["items"] == second["items"]
