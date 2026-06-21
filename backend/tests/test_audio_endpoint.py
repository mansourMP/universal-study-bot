import os
import sys
from fastapi.testclient import TestClient

sys.path.append(os.path.join(os.getcwd(), 'backend'))
from main import app

client = TestClient(app)


def test_audio_endpoint_serves_local_file(tmp_path):
    audio_dir = os.path.join(os.getcwd(), "backend", "static", "audio")
    os.makedirs(audio_dir, exist_ok=True)
    audio_path = os.path.join(audio_dir, "word_36.mp3")

    # Write a tiny deterministic placeholder file
    with open(audio_path, "wb") as f:
        f.write(b"ID3")

    resp = client.get("/api/v2/audio/36")
    assert resp.status_code == 200
    assert resp.headers.get("content-type", "").startswith("audio/mpeg")
