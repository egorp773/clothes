from __future__ import annotations

import numpy as np
import pytest
from PIL import Image

from app.classification.fashion_siglip_adapter import FashionEmbeddingResult
from app.config import Settings
from app.visual_search.schemas import VisualSearchFilters
from app.visual_search.service import VisualSearchService


def _fusion_service(settings: Settings | None = None) -> VisualSearchService:
    service = object.__new__(VisualSearchService)
    service.settings = settings or Settings(_env_file=None)
    return service


def _scores_by_product(rows: list[dict[str, object]]) -> dict[str, float]:
    return {
        str(row["product_id"]): float(row["visual_similarity"])
        for row in rows
    }


def test_good_foreground_is_nearly_invariant_to_different_contexts():
    service = _fusion_service()
    foreground = [
        {"product_id": "plain-background", "visual_similarity": 0.80},
        {"product_id": "busy-background", "visual_similarity": 0.80},
    ]
    context = [
        {"product_id": "plain-background", "visual_similarity": 0.10},
        {"product_id": "busy-background", "visual_similarity": 0.99},
    ]

    fused = service._fuse_query_candidates(
        foreground,
        context,
        segmentation_tier="good",
    )
    scores = _scores_by_product(fused)

    assert abs(scores["plain-background"] - scores["busy-background"]) <= 0.0031


def test_context_cannot_displace_a_clearly_better_foreground_candidate():
    service = _fusion_service()
    foreground = [
        {"product_id": "right-garment", "visual_similarity": 0.82},
        {"product_id": "background-lookalike", "visual_similarity": 0.70},
    ]
    context = [
        {"product_id": "right-garment", "visual_similarity": 0.05},
        {"product_id": "background-lookalike", "visual_similarity": 1.0},
    ]

    fused = service._fuse_query_candidates(
        foreground,
        context,
        segmentation_tier="medium",
    )
    ranked = sorted(
        fused,
        key=lambda row: float(row["visual_similarity"]),
        reverse=True,
    )

    assert ranked[0]["product_id"] == "right-garment"


def test_visual_search_fusion_weights_are_configurable_through_env(monkeypatch):
    monkeypatch.setenv("VISUAL_SEARCH_FOREGROUND_WEIGHT", "8")
    monkeypatch.setenv("VISUAL_SEARCH_CONTEXT_WEIGHT", "2")

    settings = Settings(_env_file=None)
    service = _fusion_service(settings)
    fused = service._fuse_query_candidates(
        [{"product_id": "product", "visual_similarity": 0.50}],
        [{"product_id": "product", "visual_similarity": 0.55}],
        segmentation_tier="good",
    )

    assert settings.visual_search_foreground_weight == pytest.approx(0.80)
    assert settings.visual_search_context_weight == pytest.approx(0.20)
    assert (
        settings.visual_search_foreground_weight
        + settings.visual_search_context_weight
    ) == pytest.approx(1.0)
    assert fused[0]["visual_similarity"] == pytest.approx(0.51)


def test_fusion_is_quality_aware_and_poor_segmentation_uses_context_only():
    service = _fusion_service()
    foreground = [{"product_id": "product", "visual_similarity": 0.50}]
    context = [{"product_id": "product", "visual_similarity": 0.60}]

    good = service._fuse_query_candidates(
        foreground,
        context,
        segmentation_tier="good",
    )
    medium = service._fuse_query_candidates(
        foreground,
        context,
        segmentation_tier="medium",
    )
    poor = service._fuse_query_candidates(
        foreground,
        context,
        segmentation_tier="poor",
    )

    assert good[0]["visual_similarity"] == pytest.approx(0.503)
    assert medium[0]["visual_similarity"] == pytest.approx(0.515)
    assert poor[0]["visual_similarity"] == pytest.approx(0.60)


class _NoForegroundSegmentation:
    def segment(self, image):
        return None


class _TrackingClassification:
    def __init__(self) -> None:
        self.batch_sizes: list[int] = []

    def embed_and_classify_many(self, images, top_k):
        self.batch_sizes.append(len(images))
        return [
            FashionEmbeddingResult(
                embedding=np.zeros(768, dtype=np.float32),
                candidates=[],
            )
            for _ in images
        ]


class _ContextOnlyModels:
    def __init__(self) -> None:
        self.fast_segmentation = _NoForegroundSegmentation()
        self.classification = _TrackingClassification()
        self.clothing_regions = object()


class _ContextOnlyStore:
    def __init__(self) -> None:
        self.retrievals = 0

    def retrieve(self, embedding, **kwargs):
        self.retrievals += 1
        return [
            {
                "product_id": "context-match",
                "image_url": "https://example.com/context.jpg",
                "visual_similarity": 0.91,
                "title": "Context fallback product",
                "description": "A sufficiently detailed product description for reranking.",
                "main_image": "https://example.com/context.jpg",
                "images": ["front", "back"],
            }
        ]


def test_search_uses_single_context_fallback_when_foreground_is_unavailable():
    models = _ContextOnlyModels()
    store = _ContextOnlyStore()
    service = VisualSearchService(
        Settings(_env_file=None),
        models,  # type: ignore[arg-type]
        store,  # type: ignore[arg-type]
    )
    try:
        response = service.search(
            Image.new("RGB", (64, 64)),
            "context-only",
            VisualSearchFilters(),
        )
    finally:
        service.close()

    returned = [*response.products, *response.similar_products]
    assert models.classification.batch_sizes == [1]
    assert store.retrievals == 1
    assert returned[0].product_id == "context-match"
    assert "query_foreground_unavailable" in response.warnings
