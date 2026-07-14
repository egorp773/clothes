from __future__ import annotations

import hashlib
import io
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

import numpy as np
from PIL import Image, ImageOps

from app.catalog import NORMALIZED_CATEGORIES
from app.color.masked_color_analyzer import MaskedColorAnalyzer
from app.config import Settings
from app.enrichment.quality import PhotoQuality, PhotoQualityAnalyzer
from app.enrichment.store import EnrichmentJob, SupabaseEnrichmentStore
from app.enrichment.visual_attributes import VisualAttributeSuggester
from app.model_manager import ModelManager


@dataclass
class _ImageWork:
    row: dict[str, Any]
    original: Image.Image
    original_hash: str
    quality: PhotoQuality
    cutout: Image.Image | None
    cutout_png: bytes | None
    foreground_hash: str | None
    colors: list[Any]
    original_embedding: np.ndarray | None = None
    foreground_embedding: np.ndarray | None = None
    detected_item_type: str | None = None
    detected_category: str | None = None
    detected_subcategory: str | None = None
    detected_confidence: float = 0.0


class ProductEnrichmentService:
    """Idempotent post-publication enrichment for a durable job."""

    pipeline_version = "publication-enrichment-v1"

    def __init__(
        self,
        settings: Settings,
        models: ModelManager,
        store: SupabaseEnrichmentStore,
    ) -> None:
        self.settings = settings
        self.models = models
        self.store = store
        self.quality = PhotoQualityAnalyzer()
        self.colors = MaskedColorAnalyzer()
        self.attributes = VisualAttributeSuggester(models.classification)
        self.model_version = (
            f"{settings.fashion_model_id}@{settings.fashion_model_revision}"
        )

    def process(self, job: EnrichmentJob) -> dict[str, Any]:
        product = self.store.get_product(job.product_id)
        images = self.store.get_product_images(job.product_id, product)
        if not images:
            raise ValueError("Product has no usable images")

        work = [self._prepare_image(row) for row in images]
        self._embed(work)
        visual_rows: list[dict[str, Any]] = []
        cutout_urls: list[str] = []

        for item in work:
            image_id = str(item.row["id"])
            no_background_url = item.row.get("no_background_url")
            if item.cutout_png is not None:
                no_background_url = self.store.upload_cutout(
                    job.product_id, image_id, item.cutout_png
                )
                cutout_urls.append(no_background_url)

            update: dict[str, Any] = {
                "quality_score": item.quality.score,
                "quality_details": {
                    "sharpness": item.quality.sharpness,
                    "exposure": item.quality.exposure,
                    "contrast": item.quality.contrast,
                    "resolution": item.quality.resolution,
                    "warnings": list(item.quality.warnings),
                    "model_version": self.quality.version,
                },
                "original_image_hash": item.original_hash,
                "embedding_model_version": self.model_version,
            }
            if item.original_embedding is not None:
                update["original_embedding"] = self.store.vector_literal(
                    item.original_embedding
                )
            if no_background_url:
                update["no_background_url"] = no_background_url
            if item.foreground_embedding is not None:
                update["foreground_embedding"] = self.store.vector_literal(
                    item.foreground_embedding
                )
                update["foreground_image_hash"] = item.foreground_hash
            self.store.update_product_image(image_id, update)

            original_url = str(item.row["original_url"])
            if item.original_embedding is not None:
                visual_rows.append(
                    self._visual_row(job.product_id, original_url, item)
                )
            if no_background_url and item.foreground_embedding is not None:
                visual_rows.append(
                    self._visual_row(
                        job.product_id,
                        str(no_background_url),
                        item,
                        foreground=True,
                    )
                )

        self.store.upsert_visual_embeddings(visual_rows)
        best = max(
            work,
            key=lambda item: (
                item.foreground_embedding is not None,
                item.quality.score,
            ),
        )
        normalized_category = str(product.get("normalized_category") or "").strip()
        if not normalized_category and best.detected_item_type:
            normalized_category = NORMALIZED_CATEGORIES.get(
                best.detected_item_type, ""
            )

        suggestions = []
        attribute_embedding = (
            best.foreground_embedding
            if best.foreground_embedding is not None
            else best.original_embedding
        )
        if attribute_embedding is not None and normalized_category:
            suggestions = self.attributes.suggest(
                attribute_embedding, normalized_category
            )
            for suggestion in suggestions:
                self.store.merge_attribute(
                    job.product_id,
                    suggestion.key,
                    suggestion.value,
                    suggestion.confidence,
                    self.attributes.version,
                )

        color_values = best.colors
        if color_values:
            self.store.merge_attribute(
                job.product_id,
                "primary_color",
                color_values[0].color_id,
                color_values[0].confidence,
                self.colors.source,
                source="computed",
            )
            if len(color_values) > 1:
                self.store.merge_attribute(
                    job.product_id,
                    "secondary_colors",
                    [candidate.color_id for candidate in color_values[1:]],
                    max(candidate.confidence for candidate in color_values[1:]),
                    self.colors.source,
                    source="computed",
                )

        moderation = (
            self.attributes.moderation_risk(attribute_embedding)
            if attribute_embedding is not None
            else {"score": 0.0, "label": "unknown", "signals": {}}
        )
        embeddings = [
            item.foreground_embedding
            for item in sorted(work, key=lambda value: value.quality.score, reverse=True)
            if item.foreground_embedding is not None
        ][:3]
        if not embeddings:
            embeddings = [
                item.original_embedding
                for item in work
                if item.original_embedding is not None
            ][:3]
        similarities = self.store.find_similar(
            job.product_id, embeddings, self.model_version
        )
        self.store.replace_similarities(job.product_id, similarities)

        tags = self._recommendation_tags(product, normalized_category, suggestions, color_values)
        search_text = self._search_text(product, normalized_category, suggestions, color_values)
        product_update: dict[str, Any] = {
            "enrichment_status": "completed",
            "enrichment_version": self.pipeline_version,
            "enrichment_completed_at": datetime.now(timezone.utc).isoformat(),
            "photo_quality_score": round(
                sum(item.quality.score for item in work) / len(work), 4
            ),
            "moderation_risk": moderation,
            "recommendation_tags": tags,
            "search_text": search_text,
        }
        if normalized_category:
            self.store.merge_attribute(
                job.product_id,
                "normalized_category",
                normalized_category,
                best.detected_confidence,
                self.model_version,
                source="computed",
            )
        if cutout_urls:
            # Legacy readers keep working while new code reads product_images.
            product_update["cutout_image"] = cutout_urls[0]
            product_update["outfit_images"] = cutout_urls
        self.store.update_product(job.product_id, product_update)
        return {
            "pipeline_version": self.pipeline_version,
            "model_version": self.model_version,
            "image_count": len(work),
            "original_embeddings": sum(
                item.original_embedding is not None for item in work
            ),
            "foreground_embeddings": sum(
                item.foreground_embedding is not None for item in work
            ),
            "attribute_count": len(suggestions),
            "similar_product_count": len(similarities),
            "moderation_risk": moderation,
        }

    def _prepare_image(self, row: dict[str, Any]) -> _ImageWork:
        payload, _ = self.store.download_image(
            str(row["original_url"]), self.settings.max_image_bytes
        )
        source = Image.open(io.BytesIO(payload))
        if source.width * source.height > self.settings.max_decoded_image_pixels:
            raise ValueError("Image dimensions are too large")
        original = ImageOps.exif_transpose(source).convert("RGB")
        original.load()
        original.thumbnail(
            (self.settings.enrichment_image_max_side,) * 2,
            Image.Resampling.LANCZOS,
        )
        quality = self.quality.analyze(original)
        segment = self.models.background_removal.segment(original)
        cutout = segment.cutout if segment is not None else None
        cutout_png = None
        foreground_hash = None
        colors = []
        if cutout is not None:
            output = io.BytesIO()
            cutout.save(output, format="PNG", optimize=True)
            cutout_png = output.getvalue()
            foreground_hash = hashlib.sha256(cutout_png).hexdigest()
            colors = self.colors.analyze(
                np.asarray(original.convert("RGB")), segment.mask
            )
        return _ImageWork(
            row=row,
            original=original,
            original_hash=hashlib.sha256(payload).hexdigest(),
            quality=quality,
            cutout=cutout,
            cutout_png=cutout_png,
            foreground_hash=foreground_hash,
            colors=colors,
        )

    def _embed(self, work: list[_ImageWork]) -> None:
        pending: list[tuple[_ImageWork, bool, Image.Image]] = []
        for item in work:
            pending.append((item, False, item.original))
            if item.cutout is not None:
                rgba = item.cutout.convert("RGBA")
                background = Image.new("RGBA", rgba.size, "white")
                pending.append(
                    (item, True, Image.alpha_composite(background, rgba).convert("RGB"))
                )
        batch_size = max(1, self.settings.enrichment_embedding_batch_size)
        for start in range(0, len(pending), batch_size):
            batch = pending[start : start + batch_size]
            encoded = self.models.classification.embed_and_classify_many(
                [entry[2] for entry in batch], top_k=1
            )
            for (item, foreground, _), result in zip(batch, encoded, strict=True):
                if foreground:
                    item.foreground_embedding = result.embedding
                else:
                    item.original_embedding = result.embedding
                if result.candidates and (
                    foreground or item.detected_item_type is None
                ):
                    top = result.candidates[0]
                    item.detected_item_type = top.definition.item_type
                    item.detected_category = top.definition.category
                    item.detected_subcategory = top.definition.subcategory
                    item.detected_confidence = top.confidence

    def _visual_row(
        self,
        product_id: str,
        image_url: str,
        item: _ImageWork,
        *,
        foreground: bool = False,
    ) -> dict[str, Any]:
        embedding = (
            item.foreground_embedding if foreground else item.original_embedding
        )
        image_hash = item.foreground_hash if foreground else item.original_hash
        if embedding is None or image_hash is None:
            raise ValueError("Embedding row is incomplete")
        return {
            "product_id": product_id,
            "image_url": image_url,
            "image_hash": image_hash,
            "embedding": self.store.vector_literal(embedding),
            "view_type": (
                "main" if str(item.row.get("role") or "") == "main" else "alternate"
            ),
            "model_version": self.model_version,
            "detected_category": item.detected_category,
            "detected_subcategory": item.detected_subcategory,
            "detected_item_type": item.detected_item_type,
            "detected_category_confidence": round(item.detected_confidence, 6),
        }

    @staticmethod
    def _recommendation_tags(product, category, suggestions, colors) -> list[str]:
        values = [
            category,
            product.get("normalized_brand") or product.get("brand"),
            product.get("audience") or product.get("gender"),
            *(candidate.color_id for candidate in colors[:3]),
            *(suggestion.value for suggestion in suggestions),
        ]
        return list(dict.fromkeys(str(value).strip().lower() for value in values if value))[
            :16
        ]

    @staticmethod
    def _search_text(product, category, suggestions, colors) -> str:
        values = [
            product.get("title"),
            product.get("description"),
            product.get("brand"),
            product.get("normalized_brand"),
            category,
            product.get("size"),
            product.get("condition"),
            product.get("audience") or product.get("gender"),
            *(candidate.color_id for candidate in colors),
            *(suggestion.value for suggestion in suggestions),
        ]
        return " ".join(str(value).strip() for value in values if value)
