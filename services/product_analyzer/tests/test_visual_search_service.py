from __future__ import annotations

import numpy as np
from PIL import Image

from app.catalog import CategoryDefinition
from app.classification.fashion_siglip_adapter import (
    FashionCandidate,
    FashionEmbeddingResult,
)
from app.config import Settings
from app.model_manager import ModelManager
from app.visual_search.schemas import VisualSearchFilters
from app.visual_search.service import VisualSearchService


class _Store:
    def __init__(self):
        self.categories = []

    def retrieve(self, embedding, **kwargs):
        self.categories.append(kwargs["category"])
        if kwargs["category"]:
            return []
        return [
            {
                "product_id": "legacy-product",
                "image_url": "https://example.com/image.jpg",
                "visual_similarity": 0.8,
            }
        ]


class _SearchStore:
    def __init__(self, focused_count: int = 4):
        self.focused_count = focused_count
        self.categories: list[str | None] = []

    def retrieve(self, embedding, **kwargs):
        category = kwargs["category"]
        self.categories.append(category)
        count = self.focused_count if category else 6
        return [
            {
                "product_id": f"product-{index}",
                "image_url": f"https://example.com/{index}.jpg",
                "visual_similarity": 0.92 - index * 0.01,
                "category": "clothing",
                "subcategory": "tops",
                "item_type": "hoodie",
                "title": f"Hoodie {index}",
                "description": "A detailed product description long enough for quality.",
                "main_image": f"https://example.com/{index}.jpg",
                "images": ["one", "two"],
            }
            for index in range(count)
        ]


class _Classification:
    def __init__(self, candidates):
        self.candidates = candidates

    def embed_and_classify(self, image, top_k):
        return FashionEmbeddingResult(
            embedding=np.zeros(768, dtype=np.float32),
            candidates=self.candidates,
        )


class _SearchModels:
    def __init__(self, candidates):
        self.classification = _Classification(candidates)
        self.fast_segmentation = object()
        self.clothing_regions = object()


def _candidate(
    item_type: str,
    confidence: float,
    *,
    category: str = "clothing",
    subcategory: str = "tops",
) -> FashionCandidate:
    return FashionCandidate(
        CategoryDefinition(item_type, subcategory, category, (item_type,)),
        confidence,
    )


def test_retrieval_pools_are_separate_and_merge_without_duplicates():
    settings = Settings()
    store = _Store()
    models = ModelManager(settings)
    service = VisualSearchService(settings, models, store)  # type: ignore[arg-type]
    try:
        focused = service._retrieve_pool(
            np.zeros(768, dtype=np.float32),
            category="clothing",
            related_subcategories=["tops"],
            filters=VisualSearchFilters(),
            match_count=120,
            pool="focused",
        )
        fallback = service._retrieve_pool(
            np.zeros(768, dtype=np.float32),
            category=None,
            related_subcategories=None,
            filters=VisualSearchFilters(),
            match_count=200,
            pool="fallback",
        )
        rows = service._merge_candidates(focused, fallback)
        assert store.categories == ["clothing", None]
        assert rows[0]["product_id"] == "legacy-product"
        assert rows[0]["_retrieval_pool"] == "fallback"
    finally:
        service.close()
        models.close()


def test_confident_search_does_not_run_broad_rpc_when_focused_pool_is_healthy():
    candidates = [
        _candidate("hoodie", 0.60),
        _candidate("sweater", 0.15),
        _candidate("sneakers", 0.10, category="shoes", subcategory="shoes_all"),
    ]
    store = _SearchStore(focused_count=4)
    service = VisualSearchService(
        Settings(),
        _SearchModels(candidates),  # type: ignore[arg-type]
        store,  # type: ignore[arg-type]
    )
    try:
        service.search(Image.new("RGB", (64, 64)), "healthy", VisualSearchFilters())
    finally:
        service.close()

    assert store.categories == ["clothing"]


def test_sparse_focused_pool_keeps_broad_taxonomy_safety_net():
    candidates = [
        _candidate("hoodie", 0.60),
        _candidate("sweater", 0.15),
        _candidate("sneakers", 0.10, category="shoes", subcategory="shoes_all"),
    ]
    store = _SearchStore(focused_count=2)
    service = VisualSearchService(
        Settings(),
        _SearchModels(candidates),  # type: ignore[arg-type]
        store,  # type: ignore[arg-type]
    )
    try:
        service.search(Image.new("RGB", (64, 64)), "sparse", VisualSearchFilters())
    finally:
        service.close()

    assert store.categories == ["clothing", None]


def test_ambiguous_item_probability_uses_one_broad_rpc():
    candidates = [
        _candidate("hoodie", 0.20),
        _candidate("sweater", 0.18),
        _candidate("sneakers", 0.16, category="shoes", subcategory="shoes_all"),
    ]
    store = _SearchStore(focused_count=4)
    service = VisualSearchService(
        Settings(),
        _SearchModels(candidates),  # type: ignore[arg-type]
        store,  # type: ignore[arg-type]
    )
    try:
        service.search(Image.new("RGB", (64, 64)), "ambiguous", VisualSearchFilters())
    finally:
        service.close()

    assert store.categories == [None]
