import sys
from pathlib import Path

from fastapi.testclient import TestClient

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.append(str(BACKEND_ROOT))
from main import app  # noqa: E402


client = TestClient(app)
HEADERS = {"X-User-Id": "test_listening_contract"}


def test_listening_levels_contract():
    resp = client.get(
        "/api/v2/listening/levels?target_lang=zh&source_lang=en",
        headers=HEADERS,
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["schema_version"] == "1.0"
    assert body["target_lang"] == "zh"
    assert body["source_lang"] == "en"
    assert isinstance(body.get("groups"), list)
    assert len(body["groups"]) >= 1
    first = body["groups"][0]
    assert isinstance(first["level"], int)
    assert isinstance(first["label"], str)
    assert isinstance(first["total_words"], int)
    assert isinstance(first["lesson_count"], int)
    assert first["lesson_count"] >= 0


def test_listening_lessons_contract_and_detail():
    resp = client.get(
        "/api/v2/listening/lessons?target_lang=zh&source_lang=en&level=2",
        headers=HEADERS,
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["schema_version"] == "1.0"
    lessons = body.get("lessons", [])
    assert isinstance(lessons, list)
    assert len(lessons) >= 1

    first = lessons[0]
    assert first["id"].startswith("LIS_HSK2_")
    assert first["focus_dimension"] == "listening"
    assert first["intent"] == "drill"
    assert isinstance(first["forced_ids"], list)
    assert len(first["forced_ids"]) >= 1
    assert first["launch"]["exercise_count"] == first["question_count"]
    assert first["launch"]["target_min_seconds"] >= 120
    assert first["launch"]["target_max_seconds"] >= first["launch"]["target_min_seconds"]

    lesson_id = first["id"]
    detail = client.get(
        f"/api/v2/listening/lessons/{lesson_id}?target_lang=zh&source_lang=en",
        headers=HEADERS,
    )
    assert detail.status_code == 200
    d = detail.json()
    assert d["schema_version"] == "1.0"
    assert d["lesson"]["id"] == lesson_id
    assert d["mission"]["focus_dimension"] == "listening"
    assert d["mission"]["intent"] == "drill"
    assert d["mission"]["forced_ids"] == d["lesson"]["forced_ids"]
