from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path


SERVICE_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE_ROOT))

from app.config import get_settings  # noqa: E402
from app.model_manager import ModelManager  # noqa: E402
from app.visual_search.service import VisualSearchService  # noqa: E402
from app.visual_search.store import SupabaseVisualSearchStore  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Idempotently backfill FashionSigLIP product embeddings."
    )
    parser.add_argument("--product-id", action="append", default=[])
    parser.add_argument("--batch-size", type=int, default=100)
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    settings = get_settings()
    models = ModelManager(settings)
    store = SupabaseVisualSearchStore(settings)
    service = VisualSearchService(settings, models, store)
    if not store.enabled:
        raise SystemExit("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required")
    try:
        models.classification.load()
        models.fast_segmentation.load()
        if args.product_id:
            results = []
            failed = 0
            for product_id in args.product_id:
                try:
                    results.append(service.index_product(product_id).model_dump(mode="json"))
                except Exception as error:
                    failed += 1
                    logging.exception("Failed to index %s", product_id)
                    results.append({"product_id": product_id, "error": str(error)})
            print(json.dumps({"results": results, "failed": failed}, ensure_ascii=False))
            return 1 if failed else 0
        summary = service.reindex_all(batch_size=max(1, min(args.batch_size, 500)))
        summary.update(store.index_stats(service.model_version))
        print(json.dumps(summary, ensure_ascii=False))
        return 1 if summary["failed"] else 0
    finally:
        service.close()
        store.close()
        models.close()


if __name__ == "__main__":
    raise SystemExit(main())
