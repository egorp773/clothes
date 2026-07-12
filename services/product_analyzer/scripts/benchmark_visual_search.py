from __future__ import annotations

import hashlib
import io
import json
import statistics
import sys
import time
from pathlib import Path

from PIL import Image, ImageEnhance, ImageFilter


SERVICE_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = SERVICE_ROOT.parents[1]
sys.path.insert(0, str(SERVICE_ROOT))

from app.config import get_settings  # noqa: E402
from app.model_manager import ModelManager  # noqa: E402
from app.visual_search.schemas import VisualSearchFilters  # noqa: E402
from app.visual_search.service import VisualSearchService  # noqa: E402
from app.visual_search.store import SupabaseVisualSearchStore  # noqa: E402


def _encoded(image: Image.Image, quality: int = 90) -> tuple[bytes, Image.Image]:
    buffer = io.BytesIO()
    image.convert("RGB").save(buffer, format="JPEG", quality=quality)
    payload = buffer.getvalue()
    return payload, Image.open(io.BytesIO(payload)).convert("RGB")


def _rank(response, targets: set[str]) -> int | None:
    for index, product in enumerate(response.products, start=1):
        if product.product_id in targets:
            return index
    return None


def main() -> int:
    settings = get_settings()
    models = ModelManager(settings)
    store = SupabaseVisualSearchStore(settings)
    service = VisualSearchService(settings, models, store)
    try:
        models.load_enabled()
        models.warmup()
        rows = store._request(
            "GET",
            f"{store._url}/rest/v1/product_visual_embeddings",
            headers=store.headers,
            params={
                "model_version": f"eq.{service.model_version}",
                "select": "product_id,image_url,view_type",
                "order": "product_id,view_type",
                "limit": "100",
            },
        ).json()
        if len(rows) < 2:
            raise SystemExit("Need at least two indexed catalog images")
        by_product: dict[str, list[str]] = {}
        for row in rows:
            by_product.setdefault(str(row["product_id"]), []).append(row["image_url"])
        first_product = next(product for product, urls in by_product.items() if urls)
        first_payload, first_image = service._download_image(by_product[first_product][0])
        alternate_url = next(
            (urls[1] for product, urls in by_product.items() if product == first_product and len(urls) > 1),
            by_product[first_product][0],
        )
        alternate_payload, alternate_image = service._download_image(alternate_url)
        second_product = next(product for product in by_product if product != first_product)
        _, second_image = service._download_image(by_product[second_product][0])

        low_quality = first_image.resize((96, 96), Image.Resampling.BILINEAR).resize(
            first_image.size, Image.Resampling.BILINEAR
        )
        recolored = ImageEnhance.Color(first_image).enhance(0.15)
        blurred = first_image.filter(ImageFilter.GaussianBlur(radius=2.2))
        multiple = Image.new(
            "RGB",
            (first_image.width + second_image.width, max(first_image.height, second_image.height)),
            "white",
        )
        multiple.paste(first_image, (0, 0))
        multiple.paste(second_image, (first_image.width, 0))

        external_cases = [
            ("person_or_outfit", REPO_ROOT / "outfit.jpeg"),
            ("complex_background", REPO_ROOT / "assets" / "mock" / "outfit_hero.jpg"),
            ("wrong_category", REPO_ROOT / "assets" / "products" / "baggy_jeans.jpg"),
        ]
        cases: list[tuple[str, bytes, Image.Image, set[str]]] = [
            ("exact", first_payload, first_image, {first_product}),
            ("alternate_view", alternate_payload, alternate_image, {first_product}),
        ]
        for name, image, targets, quality in [
            ("low_quality", low_quality, {first_product}, 20),
            ("different_color", recolored, {first_product}, 75),
            ("blurred", blurred, {first_product}, 60),
            ("multiple_items", multiple, {first_product, second_product}, 75),
        ]:
            payload, decoded = _encoded(image, quality)
            cases.append((name, payload, decoded, targets))
        for name, path in external_cases:
            payload = path.read_bytes()
            cases.append((name, payload, Image.open(io.BytesIO(payload)).convert("RGB"), set()))

        output = []
        target_ranks = []
        for name, payload, image, targets in cases:
            response = service.search(
                image,
                hashlib.sha256(payload).hexdigest(),
                VisualSearchFilters(),
            )
            rank = _rank(response, targets) if targets else None
            if targets:
                target_ranks.append(rank)
            output.append(
                {
                    "case": name,
                    "rank": rank,
                    "category": response.category,
                    "confidence": response.category_confidence,
                    "candidates": response.candidate_count,
                    "top_ids": [product.product_id for product in response.products[:5]],
                    "timings_ms": response.timings_ms,
                }
            )
        cache_started = time.perf_counter()
        cached_response = service.search(
            first_image,
            hashlib.sha256(first_payload).hexdigest(),
            VisualSearchFilters(),
        )
        cached_wall_ms = round((time.perf_counter() - cache_started) * 1000, 3)
        timing_keys = ["preparation", "embedding", "pgvector_retrieval", "reranking", "total"]
        warm_rows = output[1:]
        summary = {
            "cases": output,
            "warm_timing_median_ms": {
                key: round(statistics.median(row["timings_ms"][key] for row in warm_rows))
                for key in timing_keys
            },
            "quality": {
                "queries_with_ground_truth": len(target_ranks),
                "top_5": sum(rank is not None and rank <= 5 for rank in target_ranks) / len(target_ranks),
                "top_10": sum(rank is not None and rank <= 10 for rank in target_ranks) / len(target_ranks),
                "top_20": sum(rank is not None and rank <= 20 for rank in target_ranks) / len(target_ranks),
            },
            "index": store.index_stats(service.model_version),
            "cache": {
                "hit": cached_response.cached,
                "wall_ms": cached_wall_ms,
            },
        }
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        return 0
    finally:
        service.close()
        store.close()
        models.close()


if __name__ == "__main__":
    raise SystemExit(main())
