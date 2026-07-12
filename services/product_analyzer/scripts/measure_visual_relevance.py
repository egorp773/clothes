from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path


SERVICE_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = SERVICE_ROOT.parents[1]
sys.path.insert(0, str(SERVICE_ROOT))

from app.config import get_settings  # noqa: E402
from app.model_manager import ModelManager  # noqa: E402
from app.visual_search.schemas import VisualSearchFilters  # noqa: E402
from app.visual_search.service import VisualSearchService  # noqa: E402
from app.visual_search.store import SupabaseVisualSearchStore  # noqa: E402


def main() -> None:
    settings = get_settings()
    models = ModelManager(settings)
    store = SupabaseVisualSearchStore(settings)
    service = VisualSearchService(settings, models, store)
    queries = {
        "catalog_sweatshirt": "https://hbwzxtwcjlsfldjcqudt.supabase.co/storage/v1/object/public/product-images/items/86e5c86e-5b17-43c9-8ee3-9d4019306f56.jpg",
        "catalog_cardigan": "https://hbwzxtwcjlsfldjcqudt.supabase.co/storage/v1/object/public/product-images/items/e7bd922a-ba4a-4038-b506-f5b19109dca6.jpg",
        "cardigan_alternate_unindexed": "https://hbwzxtwcjlsfldjcqudt.supabase.co/storage/v1/object/public/product-images/items/454b82da-9f83-4c47-8f7e-0b4e000efc1e.jpg",
    }
    try:
        models.load_enabled()
        models.warmup()
        output = {}
        for name, url in queries.items():
            payload, image = service._download_image(url)
            result = service.search(
                image,
                hashlib.sha256(payload).hexdigest(),
                VisualSearchFilters(),
            )
            output[name] = {
                "query_category": result.category,
                "confidence": result.category_confidence,
                "candidates": [
                    {
                        "title": product.title,
                        "category": product.category,
                        "item_type": product.item_type,
                        "similarity": product.visual_similarity,
                        "score": product.score,
                    }
                    for product in result.products
                ],
            }
        print(json.dumps(output, ensure_ascii=False, indent=2))
    finally:
        service.close()
        store.close()
        models.close()


if __name__ == "__main__":
    main()
