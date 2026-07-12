from pathlib import Path

from fastapi.testclient import TestClient

from app.main import app, jwt_verifier, settings
from app.visual_search.schemas import AuthenticatedUser


def test_health_does_not_load_models():
    response = TestClient(app).get("/health")
    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] in {"ok", "degraded"}
    assert set(payload["components"]) == {"fast_segmentation", "segmentation", "classification", "ocr", "vlm"}


def test_analysis_degrades_to_partial_result_without_weights():
    fixture = Path(__file__).parent / "fixtures" / "dark_blue_on_red.ppm"
    with fixture.open("rb") as image:
        response = TestClient(app).post(
            "/v1/analyze",
            files=[("files", (fixture.name, image, "image/x-portable-pixmap"))],
        )
    assert response.status_code == 200
    payload = response.json()
    assert payload["primary_color"]["value"] is None
    assert "timings_ms" in payload


def test_analysis_requires_jwt_when_enabled(monkeypatch):
    monkeypatch.setattr(settings, "require_analysis_auth", True)
    fixture = Path(__file__).parent / "fixtures" / "dark_blue_on_red.ppm"
    with fixture.open("rb") as image:
        response = TestClient(app).post(
            "/v1/analyze",
            files=[("files", (fixture.name, image, "image/x-portable-pixmap"))],
        )
    assert response.status_code == 401


def test_analysis_accepts_verified_jwt(monkeypatch):
    monkeypatch.setattr(settings, "require_analysis_auth", True)
    monkeypatch.setattr(
        jwt_verifier,
        "verify",
        lambda _: AuthenticatedUser(id="user"),
    )
    fixture = Path(__file__).parent / "fixtures" / "dark_blue_on_red.ppm"
    with fixture.open("rb") as image:
        response = TestClient(app).post(
            "/v1/analyze",
            headers={"Authorization": "Bearer test"},
            files=[("files", (fixture.name, image, "image/x-portable-pixmap"))],
        )
    assert response.status_code == 200
