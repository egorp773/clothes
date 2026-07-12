from __future__ import annotations

import numpy as np

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
