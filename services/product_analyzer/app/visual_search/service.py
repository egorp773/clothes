from __future__ import annotations

import hashlib
import io
import logging
import threading
import time
from collections import OrderedDict
from dataclasses import dataclass
from typing import Any

import httpx
import numpy as np
from PIL import Image, ImageOps

from app.config import Settings
from app.model_manager import ModelManager
from app.visual_search.preprocessor import VisualSearchPreprocessor
from app.visual_search.regions import RegionDetectionResult, VisualSearchRegionDetector
from app.visual_search.reranker import VisualSearchReranker
from app.visual_search.schemas import (
    ProductEmbeddingResponse,
    VisualSearchFilters,
    VisualSearchResponse,
)
from app.visual_search.store import SupabaseVisualSearchStore


LOGGER = logging.getLogger(__name__)


@dataclass
class _CacheEntry:
    expires_at: float
    response: VisualSearchResponse


class VisualSearchService:
    def __init__(
        self,
        settings: Settings,
        models: ModelManager,
        store: SupabaseVisualSearchStore,
    ) -> None:
        self.settings = settings
        self.models = models
        self.store = store
        self.preprocessor = VisualSearchPreprocessor(settings, models.fast_segmentation)
        self.region_detector = VisualSearchRegionDetector(
            settings,
            models.fast_segmentation,
            models.clothing_regions,
            models.classification,
        )
        self.reranker = VisualSearchReranker(settings)
        self.model_version = f"{settings.fashion_model_id}@{settings.fashion_model_revision}"
        self._cache: OrderedDict[str, _CacheEntry] = OrderedDict()
        self._cache_lock = threading.Lock()
        self._download_client = httpx.Client(
            follow_redirects=True,
            timeout=httpx.Timeout(settings.visual_search_download_timeout_seconds, connect=2.5),
        )

    def detect_regions(self, image: Image.Image) -> RegionDetectionResult:
        return self.region_detector.detect(image)

    def search(
        self,
        image: Image.Image,
        image_hash: str,
        filters: VisualSearchFilters,
    ) -> VisualSearchResponse:
        started = time.perf_counter()
        cache_key = self._cache_key(image_hash, filters)
        cached = self._cache_get(cache_key)
        if cached is not None:
            cached.cached = True
            cached.timings_ms = {**cached.timings_ms, "cache": 0}
            return cached

        prepared = self.preprocessor.prepare_query_variants(image)
        embedding_started = time.perf_counter()
        query_images = (
            [prepared.foreground, prepared.context]
            if prepared.foreground is not None
            else [prepared.context]
        )
        encoded_variants = self.models.classification.embed_and_classify_many(
            query_images,
            top_k=max(6, self.settings.classification_top_k),
        )
        encoded = encoded_variants[0]
        context_encoded = encoded_variants[-1]
        embedding_ms = round((time.perf_counter() - embedding_started) * 1000)
        top = encoded.candidates[0] if encoded.candidates else None
        confidence = top.confidence if top else 0.0
        category = top.definition.category if top else None
        subcategory = top.definition.subcategory if top else None
        item_type = top.definition.item_type if top else None
        category_margin = self._category_margin(encoded.candidates, category)
        item_type_margin = self._item_type_margin(encoded.candidates)
        confident_category = bool(
            top
            and confidence >= self.settings.visual_search_high_category_confidence
            and category_margin >= self.settings.visual_search_min_category_margin
        )
        confident_item_type = bool(
            top
            and confidence >= self.settings.visual_search_high_item_type_confidence
            and item_type_margin >= self.settings.visual_search_min_item_type_margin
        )
        # A fine-grained item probability is not automatically a calibrated
        # broad-category decision.  Narrow retrieval only when both confidence
        # and the cross-category margin are strong; ambiguous outfits use one
        # broad pgvector query instead of a brittle focused+fallback sequence.
        retrieval_category = (
            category
            if confident_category
            else None
        )
        related = self._related_subcategories(encoded.candidates) if retrieval_category else None

        retrieval_ms = 0
        rerank_ms = 0
        candidates: list[dict[str, Any]] = []
        products = []
        if confident_category:
            stage_started = time.perf_counter()
            candidates = self._retrieve_pool(
                encoded.embedding,
                category=retrieval_category,
                related_subcategories=related,
                filters=filters,
                match_count=min(120, self.settings.visual_search_candidate_count),
                pool="focused",
            )
            retrieval_ms += round((time.perf_counter() - stage_started) * 1000)
            stage_started = time.perf_counter()
            products = self._rerank(
                candidates,
                category=category,
                subcategory=subcategory,
                item_type=item_type,
                filters=filters,
                confident_category=True,
                confident_item_type=confident_item_type,
            )
            rerank_ms += round((time.perf_counter() - stage_started) * 1000)
        # Reranking deliberately returns only relevant products, so its output
        # length is not a retrieval-coverage signal.  Falling back whenever it
        # contains fewer than four results made almost every query issue two
        # sequential network RPCs.  Use unique pre-rerank products instead;
        # a genuinely sparse/legacy taxonomy pool still gets the broad safety
        # net requested here.
        focused_product_count = self._unique_product_count(candidates)
        if (
            not confident_category
            or focused_product_count < self.settings.visual_search_focused_min_results
        ):
            stage_started = time.perf_counter()
            fallback = self._retrieve_pool(
                encoded.embedding,
                category=None,
                related_subcategories=None,
                filters=filters,
                match_count=self.settings.visual_search_candidate_count,
                pool="fallback" if confident_category else "broad",
            )
            retrieval_ms += round((time.perf_counter() - stage_started) * 1000)
            candidates = self._merge_candidates(candidates, fallback)
            stage_started = time.perf_counter()
            products = self._rerank(
                candidates,
                category=category,
                subcategory=subcategory,
                item_type=item_type,
                filters=filters,
                confident_category=confident_category,
                confident_item_type=confident_item_type,
            )
            rerank_ms += round((time.perf_counter() - stage_started) * 1000)
        if prepared.foreground is not None:
            stage_started = time.perf_counter()
            context_candidates = self._retrieve_pool(
                context_encoded.embedding,
                category=retrieval_category,
                related_subcategories=related,
                filters=filters,
                match_count=self.settings.visual_search_candidate_count,
                pool="context",
            )
            retrieval_ms += round((time.perf_counter() - stage_started) * 1000)
            candidates = self._fuse_query_candidates(
                candidates,
                context_candidates,
                segmentation_tier=prepared.segmentation_tier,
                segmentation_warning=",".join(prepared.warnings) or None,
                segmentation_quality=prepared.segmentation_quality,
                segmentation_coverage=prepared.segmentation_coverage,
            )
            stage_started = time.perf_counter()
            products = self._rerank(
                candidates,
                category=category,
                subcategory=subcategory,
                item_type=item_type,
                filters=filters,
                confident_category=confident_category,
                confident_item_type=confident_item_type,
            )
            rerank_ms += round((time.perf_counter() - stage_started) * 1000)
        else:
            # Context is the complete fallback when segmentation is missing or
            # measurably poor. Scores stay unchanged; this pass only attaches
            # internal diagnostics and emits the same per-candidate debug log
            # as foreground-aware fusion.
            candidates = self._fuse_query_candidates(
                [],
                candidates,
                segmentation_tier="poor",
                segmentation_warning=",".join(prepared.warnings) or None,
                segmentation_quality=prepared.segmentation_quality,
                segmentation_coverage=prepared.segmentation_coverage,
            )
        best_similarity = max(
            (product.visual_similarity for product in products),
            default=0.0,
        )
        strong_products = [
            product
            for product in products
            if product.visual_similarity >= self.settings.visual_search_strong_similarity
            and product.score >= self.settings.visual_search_strong_rerank_score
        ]
        similar_products = (
            []
            if strong_products
            else products[: self.settings.visual_search_similar_result_count]
        )
        match_status = (
            "strong"
            if strong_products
            else "similar_only"
            if similar_products
            else "none"
        )
        response = VisualSearchResponse(
            image_hash=image_hash,
            model_version=self.model_version,
            category=category,
            subcategory=subcategory,
            item_type=item_type,
            category_confidence=round(confidence, 6),
            candidate_count=len(candidates),
            products=strong_products,
            similar_products=similar_products,
            match_status=match_status,
            best_similarity=round(best_similarity, 6),
            timings_ms={
                **prepared.timings_ms,
                "preparation": sum(prepared.timings_ms.values()),
                "embedding": embedding_ms,
                "pgvector_retrieval": retrieval_ms,
                "reranking": rerank_ms,
                "total": round((time.perf_counter() - started) * 1000),
            },
            warnings=prepared.warnings,
        )
        self._cache_put(cache_key, response)
        return response

    def index_product(self, product_id: str) -> ProductEmbeddingResponse:
        started = time.perf_counter()
        product = self.store.get_product(product_id)
        if product is None:
            raise KeyError(product_id)
        urls = self._product_image_urls(product)
        cutout_urls = self._product_cutout_urls(product)
        context_urls = (
            self._product_context_urls(product) if cutout_urls else set()
        )
        if not urls:
            raise ValueError("Product has no usable image URLs")
        rows: list[dict[str, Any]] = []
        prepared_sources: list[tuple[str, bytes, Image.Image]] = []
        skipped = 0
        download_ms = 0
        preparation_ms = 0
        for url in urls:
            download_started = time.perf_counter()
            try:
                payload, image = self._download_image(url)
            except Exception:
                skipped += 1
                continue
            download_ms += round((time.perf_counter() - download_started) * 1000)
            preparation_started = time.perf_counter()
            prepared = (
                self.preprocessor.prepare_cutout(image)
                if url in cutout_urls
                else self.preprocessor.prepare_query(image)
                if url in context_urls
                else self.preprocessor.prepare(image)
            )
            preparation_ms += round((time.perf_counter() - preparation_started) * 1000)
            prepared_sources.append((url, payload, prepared.image))
        if not prepared_sources:
            raise ValueError("No product images could be prepared")
        embedding_started = time.perf_counter()
        encoded_sources = self.models.classification.embed_and_classify_many(
            [source[2] for source in prepared_sources],
            top_k=1,
        )
        embedding_ms = round((time.perf_counter() - embedding_started) * 1000)
        main_embedding: np.ndarray | None = None
        main_category: str | None = None
        for (url, payload, _), encoded in zip(
            prepared_sources,
            encoded_sources,
            strict=True,
        ):
            category = encoded.candidates[0].definition.category if encoded.candidates else None
            definition = encoded.candidates[0].definition if encoded.candidates else None
            category_confidence = encoded.candidates[0].confidence if encoded.candidates else 0.0
            is_main = main_embedding is None
            if is_main:
                main_embedding = encoded.embedding
                main_category = category
            elif url not in context_urls:
                similarity = float(np.dot(main_embedding, encoded.embedding)) if main_embedding is not None else 0
                # Reject tags, defects and detail shots through visual/category
                # consistency with the main garment, without OCR/Qwen/SAM.
                if similarity < self.settings.visual_search_alternate_similarity or (
                    main_category and category and main_category != category
                ):
                    skipped += 1
                    continue
            rows.append(
                {
                    "product_id": product_id,
                    "image_url": url,
                    "image_hash": hashlib.sha256(payload).hexdigest(),
                    "embedding": self.store.vector_literal(encoded.embedding),
                    "view_type": "main" if is_main else "alternate",
                    "model_version": self.model_version,
                    "detected_category": definition.category if definition else None,
                    "detected_subcategory": definition.subcategory if definition else None,
                    "detected_item_type": definition.item_type if definition else None,
                    "detected_category_confidence": round(category_confidence, 6),
                }
            )
        if not rows:
            raise ValueError("No product images could be embedded")
        persist_started = time.perf_counter()
        idempotent = self.store.replace_embeddings(product_id, self.model_version, rows)
        persist_ms = round((time.perf_counter() - persist_started) * 1000)
        return ProductEmbeddingResponse(
            product_id=product_id,
            model_version=self.model_version,
            embedding_dimension=self.models.classification.embedding_dimension,
            indexed_images=len(rows),
            skipped_images=skipped,
            idempotent=idempotent,
            timings_ms={
                "download": download_ms,
                "preparation": preparation_ms,
                "embedding": embedding_ms,
                "persist": persist_ms,
                "total": round((time.perf_counter() - started) * 1000),
            },
        )

    def reindex_all(self, batch_size: int = 100) -> dict[str, int]:
        indexed = failed = offset = 0
        while True:
            products = self.store.list_published_products(offset, batch_size)
            if not products:
                break
            for product in products:
                try:
                    self.index_product(str(product["id"]))
                    indexed += 1
                except Exception:
                    failed += 1
            offset += len(products)
        return {"indexed": indexed, "failed": failed}

    def _retrieve_pool(
        self,
        embedding: np.ndarray,
        *,
        category: str | None,
        related_subcategories: list[str] | None,
        filters: VisualSearchFilters,
        match_count: int,
        pool: str,
    ) -> list[dict[str, Any]]:
        rows = self.store.retrieve(
            embedding,
            model_version=self.model_version,
            match_count=match_count,
            category=category,
            related_subcategories=related_subcategories,
            filters=filters.model_dump(),
        )
        return [{**row, "_retrieval_pool": pool} for row in rows]

    @staticmethod
    def _merge_candidates(
        first: list[dict[str, Any]],
        second: list[dict[str, Any]],
    ) -> list[dict[str, Any]]:
        merged: dict[tuple[str, str], dict[str, Any]] = {}
        for row in [*first, *second]:
            key = (str(row.get("product_id")), str(row.get("image_url")))
            previous = merged.get(key)
            if previous is None or float(row.get("visual_similarity") or 0) > float(
                previous.get("visual_similarity") or 0
            ):
                merged[key] = row
        return list(merged.values())

    def _fuse_query_candidates(
        self,
        foreground: list[dict[str, Any]],
        context: list[dict[str, Any]],
        *,
        segmentation_tier: str = "good",
        segmentation_warning: str | None = None,
        segmentation_quality: float | None = None,
        segmentation_coverage: float | None = None,
    ) -> list[dict[str, Any]]:
        if segmentation_tier == "poor" or not foreground:
            context_only: list[dict[str, Any]] = []
            for row in context:
                context_similarity = float(row.get("visual_similarity") or 0)
                LOGGER.debug(
                    "visual_search_fusion product_id=%s "
                    "foreground_similarity=%s context_similarity=%.6f "
                    "final_similarity=%.6f segmentation_tier=%s "
                    "segmentation_warning=%s segmentation_quality=%s "
                    "segmentation_coverage=%s",
                    row.get("product_id"),
                    None,
                    context_similarity,
                    context_similarity,
                    segmentation_tier,
                    segmentation_warning,
                    segmentation_quality,
                    segmentation_coverage,
                )
                context_only.append(
                    {
                        **row,
                        "visual_similarity": context_similarity,
                        "_foreground_similarity": None,
                        "_context_similarity": context_similarity,
                    }
                )
            return context_only

        if segmentation_tier == "medium":
            foreground_weight, context_weight = 0.85, 0.15
        else:
            foreground_weight = self.settings.visual_search_foreground_weight
            context_weight = self.settings.visual_search_context_weight

        context_by_product: dict[str, float] = {}
        for row in context:
            product_id = str(row.get("product_id"))
            similarity = float(row.get("visual_similarity") or 0)
            context_by_product[product_id] = max(
                similarity,
                context_by_product.get(product_id, -1.0),
            )
        fused = []
        for row in foreground:
            foreground_similarity = float(row.get("visual_similarity") or 0)
            context_similarity = context_by_product.get(
                str(row.get("product_id")),
                foreground_similarity,
            )
            # Context may confirm a foreground match, but it must never punish
            # it or turn a background look-alike into the winner.  Clamping
            # context to at most 0.10 above foreground bounds the default boost
            # to 0.003 for good masks and 0.015 for medium masks.  The absolute
            # cap also keeps unsafe environment overrides from bypassing this
            # invariant.
            effective_context = min(
                max(context_similarity, foreground_similarity),
                foreground_similarity + 0.10,
            )
            weighted_similarity = (
                foreground_weight * foreground_similarity
                + context_weight * effective_context
            )
            final_similarity = foreground_similarity + min(
                max(0.0, weighted_similarity - foreground_similarity),
                0.02,
            )
            LOGGER.debug(
                "visual_search_fusion product_id=%s "
                "foreground_similarity=%.6f context_similarity=%.6f "
                "final_similarity=%.6f segmentation_tier=%s "
                "segmentation_warning=%s segmentation_quality=%s "
                "segmentation_coverage=%s",
                row.get("product_id"),
                foreground_similarity,
                context_similarity,
                final_similarity,
                segmentation_tier,
                segmentation_warning,
                segmentation_quality,
                segmentation_coverage,
            )
            fused.append(
                {
                    **row,
                    "visual_similarity": final_similarity,
                    "_foreground_similarity": foreground_similarity,
                    "_context_similarity": context_similarity,
                }
            )
        return fused

    def _rerank(
        self,
        candidates: list[dict[str, Any]],
        *,
        category: str | None,
        subcategory: str | None,
        item_type: str | None,
        filters: VisualSearchFilters,
        confident_category: bool,
        confident_item_type: bool,
    ):
        return self.reranker.collapse_and_rerank(
            candidates,
            query_category=category,
            query_subcategory=subcategory,
            query_item_type=item_type,
            query_color=filters.colors[0] if len(filters.colors) == 1 else None,
            query_brand=filters.brands[0] if len(filters.brands) == 1 else None,
            query_condition=filters.conditions[0] if len(filters.conditions) == 1 else None,
            limit=self.settings.visual_search_result_count,
            confident_category=confident_category,
            confident_item_type=confident_item_type,
        )

    def _download_image(self, url: str) -> tuple[bytes, Image.Image]:
        response = self._download_client.get(url)
        response.raise_for_status()
        content_type = response.headers.get("content-type", "").split(";", 1)[0]
        if content_type not in {"image/jpeg", "image/png", "image/webp"}:
            raise ValueError(f"Unsupported remote image MIME: {content_type}")
        payload = response.content
        if len(payload) > self.settings.visual_search_max_image_bytes:
            raise ValueError("Remote image is too large")
        image = ImageOps.exif_transpose(Image.open(io.BytesIO(payload)))
        image.load()
        return payload, image

    def _product_image_urls(self, product: dict[str, Any]) -> list[str]:
        candidates = [
            product.get("cutout_image"),
            *(product.get("outfit_images") or []),
            product.get("main_image"),
            product.get("image"),
            product.get("original_image"),
            *(product.get("images") or []),
        ]
        urls: list[str] = []
        for value in candidates:
            url = str(value or "").strip()
            if url.startswith(("https://", "http://")) and url not in urls:
                urls.append(url)
            if len(urls) >= self.settings.visual_search_max_product_images:
                break
        return urls

    @staticmethod
    def _product_cutout_urls(product: dict[str, Any]) -> set[str]:
        return {
            str(value).strip()
            for value in [
                product.get("cutout_image"),
                *(product.get("outfit_images") or []),
            ]
            if str(value or "").strip().startswith(("https://", "http://"))
        }

    @staticmethod
    def _product_context_urls(product: dict[str, Any]) -> set[str]:
        return {
            str(value).strip()
            for value in [
                product.get("main_image"),
                product.get("image"),
                product.get("original_image"),
            ]
            if str(value or "").strip().startswith(("https://", "http://"))
        }

    @staticmethod
    def _related_subcategories(candidates) -> list[str]:
        return list(
            dict.fromkeys(
                candidate.definition.subcategory for candidate in candidates[:3]
            )
        )

    @staticmethod
    def _category_margin(candidates, category: str | None) -> float:
        if not candidates or not category:
            return 0.0
        top_confidence = float(candidates[0].confidence)
        strongest_other = max(
            (
                float(candidate.confidence)
                for candidate in candidates[1:]
                if candidate.definition.category != category
            ),
            default=0.0,
        )
        return max(0.0, top_confidence - strongest_other)

    @staticmethod
    def _item_type_margin(candidates) -> float:
        if not candidates:
            return 0.0
        runner_up = float(candidates[1].confidence) if len(candidates) > 1 else 0.0
        return max(0.0, float(candidates[0].confidence) - runner_up)

    @staticmethod
    def _unique_product_count(candidates: list[dict[str, Any]]) -> int:
        return len(
            {
                str(candidate.get("product_id"))
                for candidate in candidates
                if candidate.get("product_id") is not None
            }
        )

    def _cache_key(self, image_hash: str, filters: VisualSearchFilters) -> str:
        return hashlib.sha256(
            (image_hash + filters.model_dump_json() + self.model_version).encode()
        ).hexdigest()

    def _cache_get(self, key: str) -> VisualSearchResponse | None:
        with self._cache_lock:
            entry = self._cache.get(key)
            if entry is None:
                return None
            if entry.expires_at <= time.monotonic():
                self._cache.pop(key, None)
                return None
            self._cache.move_to_end(key)
            return entry.response.model_copy(deep=True)

    def _cache_put(self, key: str, response: VisualSearchResponse) -> None:
        with self._cache_lock:
            self._cache[key] = _CacheEntry(
                expires_at=time.monotonic() + self.settings.visual_search_cache_ttl_seconds,
                response=response.model_copy(deep=True),
            )
            self._cache.move_to_end(key)
            while len(self._cache) > self.settings.visual_search_cache_size:
                self._cache.popitem(last=False)

    def close(self) -> None:
        self._download_client.close()
