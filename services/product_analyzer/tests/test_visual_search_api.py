from __future__ import annotations

import io

from fastapi.testclient import TestClient
from PIL import Image

from app.main import app, jwt_verifier, models, visual_search, visual_store
from app.segmentation.rembg_adapter import ForegroundProposal
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


def test_visual_search_response_contract_does_not_expose_fusion_debug_fields(
    monkeypatch,
):
    monkeypatch.setattr(
        visual_search,
        "search",
        lambda image, image_hash, filters: {
            "image_hash": image_hash,
            "model_version": "test@1",
            "products": [
                {
                    "product_id": "product",
                    "score": 0.8,
                    "visual_similarity": 0.9,
                    "matched_image_url": "https://example.com/product.jpg",
                    "_foreground_similarity": 0.91,
                    "_context_similarity": 0.72,
                    "_final_similarity": 0.9,
                }
            ],
            "_segmentation_quality": "good",
        },
    )

    response = TestClient(app).post(
        "/v1/visual-search",
        files={"file": ("query.jpg", _jpeg(), "image/jpeg")},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["image_hash"]
    assert payload["model_version"] == "test@1"
    assert payload["products"][0]["product_id"] == "product"
    assert "_segmentation_quality" not in payload
    assert "_foreground_similarity" not in payload["products"][0]
    assert "_context_similarity" not in payload["products"][0]
    assert "_final_similarity" not in payload["products"][0]


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


def test_visual_search_regions_returns_normalized_boxes(monkeypatch):
    monkeypatch.setattr(
        models.fast_segmentation,
        "propose_regions",
        lambda _: [
            ForegroundProposal((8, 4, 32, 28), 0.91),
            ForegroundProposal((36, 10, 60, 52), 0.84),
        ],
    )
    monkeypatch.setattr(
        models.clothing_regions,
        "propose_clothing_regions",
        lambda _: [],
    )
    monkeypatch.setattr(
        models.classification,
        "classify_many",
        lambda images, top_k: [[] for _ in images],
    )
    response = TestClient(app).post(
        "/v1/visual-search/regions",
        files={"file": ("query.jpg", _jpeg(), "image/jpeg")},
    )
    assert response.status_code == 200
    payload = response.json()
    assert payload["width"] == 64
    assert payload["height"] == 64
    assert len(payload["regions"]) == 2
    assert payload["regions"][0]["bbox"] == [0.125, 0.0625, 0.5, 0.4375]
    assert "total" in payload["timings_ms"]


def test_background_removal_releases_region_model_and_returns_local_png(monkeypatch):
    region_unloads = 0

    def track_region_model_unload():
        nonlocal region_unloads
        region_unloads += 1

    monkeypatch.setattr(
        jwt_verifier,
        "verify",
        lambda _: AuthenticatedUser(id="user"),
    )
    monkeypatch.setattr(
        models.background_removal,
        "remove_background",
        lambda image: image.convert("RGBA"),
    )
    monkeypatch.setattr(
        models.clothing_regions,
        "unload",
        track_region_model_unload,
    )
    response = TestClient(app).post(
        "/v1/remove-background",
        headers={"Authorization": "Bearer test"},
        files={"file": ("query.jpg", _jpeg(), "image/jpeg")},
    )
    assert response.status_code == 200
    assert response.headers["content-type"] == "image/png"
    assert response.headers["x-background-model"] == "u2netp"
    assert Image.open(io.BytesIO(response.content)).mode == "RGBA"
    assert region_unloads == 1


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
