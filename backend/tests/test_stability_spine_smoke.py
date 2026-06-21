import os
import sys

from fastapi.testclient import TestClient

sys.path.append(os.path.join(os.getcwd(), "backend"))

from main import app


client = TestClient(app)


def test_health_path_and_brain_mission_smoke():
    health = client.get("/health")
    assert health.status_code == 200

    journey = client.get("/api/v2/path/journey", headers={"X-User-Id": "smoke_user"})
    assert journey.status_code == 200
    assert "nodes" in journey.json()

    mission = client.post(
        "/api/v2/brain/mission",
        headers={"X-User-Id": "smoke_user"},
        json={"language_code": "zh", "intent": "daily", "limit": 1},
    )
    assert mission.status_code == 200
    assert "mission_id" in mission.json()
