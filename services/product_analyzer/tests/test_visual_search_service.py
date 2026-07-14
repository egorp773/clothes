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

    def embed_and_classify_many(self, images, top_k):
        return [self.embed_and_classify(image, top_k) for image in images]


class _NoSegmentation:
    def segment(self, image):
        return None


class _SearchModels:
    def __init__(self, candidates):
        self.classification = _Classification(candidates)
        self.fast_segmentation = _NoSegmentation()
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


def test_weak_but_relevant_results_are_returned_as_similar_only():
    candidates = [
        _candidate("hoodie", 0.60),
        _candidate("sweater", 0.15),
        _candidate("sneakers", 0.10, category="shoes", subcategory="shoes_all"),
    ]
    service = VisualSearchService(
        Settings(visual_search_strong_similarity=0.99),
        _SearchModels(candidates),  # type: ignore[arg-type]
        _SearchStore(focused_count=4),  # type: ignore[arg-type]
    )
    try:
        response = service.search(
            Image.new("RGB", (64, 64)),
            "similar-only",
            VisualSearchFilters(),
        )
    finally:
        service.close()

    assert response.products == []
    assert response.similar_products
    assert response.match_status == "similar_only"


def test_product_image_order_uses_cutout_context_and_three_extra_views():
    settings = Settings(visual_search_max_product_images=5)
    service = VisualSearchService(
        settings,
        _SearchModels([]),  # type: ignore[arg-type]
        _SearchStore(),  # type: ignore[arg-type]
    )
    product = {
        "cutout_image": "https://example.com/cutout.png",
        "outfit_images": ["https://example.com/cutout.png"],
        "main_image": "https://example.com/main.jpg",
        "image": "https://example.com/main.jpg",
        "original_image": "https://example.com/main.jpg",
        "images": [
            "https://example.com/main.jpg",
            "https://example.com/side.jpg",
            "https://example.com/back.jpg",
            "https://example.com/detail.jpg",
            "https://example.com/extra.jpg",
        ],
    }
    try:
        urls = service._product_image_urls(product)
    finally:
        service.close()

    assert urls == [
        "https://example.com/cutout.png",
        "https://example.com/main.jpg",
        "https://example.com/side.jpg",
        "https://example.com/back.jpg",
        "https://example.com/detail.jpg",
    ]


def test_foreground_similarity_dominates_context_background():
    foreground = [
        {"product_id": "garment", "visual_similarity": 0.80},
        {"product_id": "crowd", "visual_similarity": 0.55},
    ]
    context = [
        {"product_id": "garment", "visual_similarity": 0.40},
        {"product_id": "crowd", "visual_similarity": 0.95},
    ]

    fused = VisualSearchService._fuse_query_candidates(foreground, context)

    assert fused[0]["visual_similarity"] > fused[1]["visual_similarity"]
