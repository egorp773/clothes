from __future__ import annotations

import io

from fastapi.testclient import TestClient
from PIL import Image

from app.main import app, jwt_verifier, visual_search, visual_store
from app.visual_search.schemas import (
    AuthenticatedUser,
    VisualSearchResponse,
)


def _jpeg() -> bytes:
    output = io.BytesIO()
    Image.new("RGB", (64, 64), "black").save(output, "JPEG")
    return output.getvalue()


def test_visual_search_requires_supported_mime(monkeypatch):
    monkeypatch.setattr(
        jwt_verifier,
        "verify",
        lambda _: AuthenticatedUser(id="user"),
    )
    response = TestClient(app).post(
        "/v1/visual-search",
        headers={"Authorization": "Bearer test"},
        files={"file": ("query.gif", b"GIF89a", "image/gif")},
    )
    assert response.status_code == 415


def test_visual_search_returns_ranked_payload(monkeypatch):
    monkeypatch.setattr(
        jwt_verifier,
        "verify",
        lambda _: AuthenticatedUser(id="user"),
    )
    monkeypatch.setattr(
        visual_search,
        "search",
        lambda image, image_hash, filters: VisualSearchResponse(
            image_hash=image_hash,
            model_version="test@1",
            timings_ms={"total": 12},
        ),
    )
    response = TestClient(app).post(
        "/v1/visual-search",
        headers={"Authorization": "Bearer test"},
        files={"file": ("query.jpg", _jpeg(), "image/jpeg")},
    )
    assert response.status_code == 200
    assert response.json()["model_version"] == "test@1"


def test_visual_search_is_available_without_login(monkeypatch):
    monkeypatch.setattr(
        visual_search,
        "search",
        lambda image, image_hash, filters: VisualSearchResponse(
            image_hash=image_hash,
            model_version="test@1",
            timings_ms={"total": 12},
        ),
    )
    response = TestClient(app).post(
        "/v1/visual-search",
        files={"file": ("query.jpg", _jpeg(), "image/jpeg")},
    )
    assert response.status_code == 200


def test_product_indexing_is_owner_only(monkeypatch):
    monkeypatch.setattr(
        jwt_verifier,
        "verify",
        lambda _: AuthenticatedUser(id="owner"),
    )
    monkeypatch.setattr(
        visual_store,
        "get_product",
        lambda _: {
            "id": "product",
            "seller_id": "someone-else",
            "status": "published",
            "is_hidden": False,
        },
    )
    response = TestClient(app).post(
        "/v1/products/product/embeddings",
        headers={"Authorization": "Bearer test"},
    )
    assert response.status_code == 403
