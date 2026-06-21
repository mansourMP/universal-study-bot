import base64
import os
import sys

from fastapi.testclient import TestClient


def _write_placeholder_webp(path: str) -> None:
    payload = base64.b64decode(
        "UklGRkoAAABXRUJQVlA4ICwAAAAwAQCdASoBAAEALoE0mk0iIiIiIgBoSywAAA=="
    )
    with open(path, "wb") as f:
        f.write(payload)


def test_image_endpoint_local_file():
    sys.path.append(os.path.join(os.getcwd(), "backend"))
    from main import app

    images_dir = os.path.join(os.getcwd(), "backend", "static", "images")
    os.makedirs(images_dir, exist_ok=True)
    image_path = os.path.join(images_dir, "word_36.webp")
    _write_placeholder_webp(image_path)

    client = TestClient(app)
    resp = client.get("/api/v2/image/36")
    assert resp.status_code == 200
    assert resp.headers.get("content-type") == "image/webp"
