from __future__ import annotations

import logging
import threading
import time
from collections import OrderedDict, defaultdict
from dataclasses import dataclass
from typing import Callable, TypeVar

import numpy as np
from PIL import Image

from app.catalog import BRANDS, ITEM_TYPE_TITLES, NORMALIZED_CATEGORIES
from app.color.masked_color_analyzer import (
    COLOR_FAMILIES,
    ColorCandidate,
    MaskedColorAnalyzer,
)
from app.config import Settings
from app.enrichment.quality import PhotoQualityAnalyzer
from app.enrichment.visual_attributes import VisualAttributeSuggester
from app.model_manager import ModelManager, StageTimeoutError
from app.ocr.brand_matcher import BrandMatcher
from app.ocr.paddleocr_adapter import OcrResult
from app.schemas import AnalysisResponse, AnalyzedField, CategoryCandidate, OcrPayload
from app.segmentation.grounded_sam_adapter import SegmentedGarment
from app.vlm.qwen_adapter import VlmAttributes


LOGGER = logging.getLogger(__name__)
T = TypeVar("T")


@dataclass
class CacheEntry:
    result: AnalysisResponse
    expires_at: float


@dataclass
class AnalysisEvidence:
    embeddings: list[np.ndarray]
    embedding_weights: list[float]
    color_batches: list[tuple[float, list[ColorCandidate]]]


class AnalysisCache:
    def __init__(self, max_size: int, ttl_seconds: int) -> None:
        self.max_size = max_size
        self.ttl_seconds = ttl_seconds
        self._lock = threading.Lock()
        self._entries: OrderedDict[str, CacheEntry] = OrderedDict()

    def get(self, key: str) -> AnalysisResponse | None:
        with self._lock:
            entry = self._entries.get(key)
            if entry is None or entry.expires_at <= time.monotonic():
                self._entries.pop(key, None)
                return None
            self._entries.move_to_end(key)
            return entry.result.model_copy(deep=True)

    def put(self, key: str, result: AnalysisResponse) -> None:
        with self._lock:
            self._entries[key] = CacheEntry(
                result.model_copy(deep=True), time.monotonic() + self.ttl_seconds
            )
            self._entries.move_to_end(key)
            while len(self._entries) > self.max_size:
                self._entries.popitem(last=False)


class AnalyzerPipeline:
    """Fast main-photo result plus non-blocking, cache-backed enrichment."""

    def __init__(
        self,
        settings: Settings,
        models: ModelManager,
        result_sink: Callable[[AnalysisResponse], None] | None = None,
    ) -> None:
        self.settings = settings
        self.models = models
        self.color = MaskedColorAnalyzer()
        self.photo_quality = PhotoQualityAnalyzer()
        self.visual_attributes = VisualAttributeSuggester(models.classification)
        self.brand_matcher = BrandMatcher(settings.brand_match_threshold)
        self.cache = AnalysisCache(
            settings.analysis_cache_size, settings.analysis_cache_ttl_seconds
        )
        self.result_sink = result_sink
        self._enrichment_inflight: set[str] = set()
        self._extra_enrichment_pending: set[str] = set()
        self._enrichment_lock = threading.Lock()
        self._evidence: OrderedDict[str, AnalysisEvidence] = OrderedDict()
        self._evidence_lock = threading.Lock()

    def get_cached(self, image_hash: str) -> AnalysisResponse | None:
        return self.cache.get(image_hash)

    def restore_cached(self, image_hash: str, result: AnalysisResponse) -> None:
        restored = result.model_copy(deep=True)
        # Internal persistence callbacks use the content hash to fan out an
        # enrichment to every durable listing job for the same image.
        restored.analysis_id = image_hash
        self.cache.put(image_hash, restored)

    def analyze(
        self,
        image: Image.Image,
        image_hash: str,
        *,
        download_ms: int = 0,
        decode_ms: int = 0,
    ) -> AnalysisResponse:
        cached = self.cache.get(image_hash)
        if cached is not None:
            return cached

        timings: dict[str, int] = {"download": download_ms, "decode": decode_ms}
        warnings: list[str] = []
        started = time.perf_counter()
        deadline = started + self.settings.fast_pipeline_timeout_seconds
        main_image = self._resize(image)
        timings["resize"] = self._elapsed_ms(started)
        quality_started = time.perf_counter()
        main_quality_weight = max(
            0.25,
            self.photo_quality.analyze(main_image).score,
        )
        timings["photo_quality"] = self._elapsed_ms(quality_started)

        fast_segments, segment_ms = self._stage(
            "rembg_segmentation",
            self._remaining_timeout(
                deadline, self.settings.fast_segmentation_timeout_seconds
            ),
            self.models.fast_segmentation.segment_many,
            main_image,
            warnings=warnings,
        )
        timings["rembg_segmentation"] = segment_ms
        segments = fast_segments or []
        segment = segments[0] if segments else None
        fallback_ms = 0
        if len(segments) > 1:
            # rembg already isolated the objects.  Grounded-SAM used to run
            # here, add several seconds, and then discard all but one mask.
            warnings.append(f"multiple_items_detected:{len(segments)}")
        elif not self.models.fast_segmentation.is_acceptable(segment):
            warnings.append("rembg_mask_low_quality_or_multiple_items")
            fallback_segments, fallback_ms = self._stage(
                "grounded_sam_fallback",
                self._remaining_timeout(
                    deadline, self.settings.fallback_segmentation_timeout_seconds
                ),
                self.models.segmentation.segment_many,
                main_image,
                warnings=warnings,
            )
            if fallback_segments:
                segments = fallback_segments
                segment = segments[0]
                if len(segments) > 1:
                    warnings.append(f"multiple_items_detected:{len(segments)}")
        timings["grounded_sam_fallback"] = fallback_ms
        timings["segmentation"] = segment_ms + fallback_ms

        classification_images = (
            [item.cutout for item in segments] if segments else [main_image]
        )
        if len(classification_images) > 1:
            category_future = self.models.submit(
                self._timed,
                self.models.classification.embed_and_classify_many,
                classification_images,
            )
        else:
            category_future = self.models.submit(
                self._timed,
                self.models.classification.embed_and_classify,
                classification_images[0],
            )
        color_future = None
        if segment is not None:
            color_future = self.models.submit(
                self._timed,
                self.color.analyze,
                np.asarray(main_image.convert("RGB")),
                segment.mask,
            )

        classified = self._await_future(
            "fashion_siglip",
            category_future,
            self._remaining_timeout(
                deadline, self.settings.classification_timeout_seconds
            ),
            warnings,
        )
        visual_embedding = None
        if classified is None:
            candidates = []
        elif len(classification_images) > 1:
            visual_embedding = classified[0].embedding if classified else None
            candidates = self._merge_region_candidates(
                [item.candidates for item in classified],
                limit=max(
                    self.settings.classification_top_k,
                    min(
                        len(classification_images), self.settings.max_detected_garments
                    ),
                ),
            )
        else:
            visual_embedding = classified.embedding
            candidates = classified.candidates
        timings["fashion_siglip"] = self._future_duration(category_future)

        color_candidates: list[ColorCandidate] = []
        if color_future is None:
            warnings.append("color_skipped_without_mask")
            timings["color"] = 0
        else:
            color_candidates = (
                self._await_future(
                    "color",
                    color_future,
                    self._remaining_timeout(deadline, 2.0),
                    warnings,
                )
                or []
            )
            timings["color"] = self._future_duration(color_future)

        timings["fast_total"] = self._elapsed_ms(started)

        top = candidates[0] if candidates else None
        result = self._base_response(
            image_hash=image_hash,
            candidates=candidates,
            colors=color_candidates,
            warnings=warnings,
            timings=timings,
        )
        self._remember_evidence(
            image_hash,
            visual_embedding,
            color_candidates,
            main_quality_weight,
        )
        self.cache.put(image_hash, result)
        self._schedule_enrichment(
            image_hash,
            main_image.copy(),
            segment,
            top,
            visual_embedding,
        )
        LOGGER.info("Fast analysis %s: %s", image_hash[:12], timings)
        cached = self.cache.get(image_hash)
        return cached or result

    def _schedule_enrichment(
        self,
        image_hash: str,
        image: Image.Image,
        segment: SegmentedGarment | None,
        top,
        visual_embedding: np.ndarray | None,
    ) -> None:
        with self._enrichment_lock:
            if image_hash in self._enrichment_inflight:
                return
            self._enrichment_inflight.add(image_hash)
        result = self.cache.get(image_hash)
        if result is not None:
            result.enrichment_status = "pending"
            self.cache.put(image_hash, result)
        if not self.models.ocr.available and not self.models.vlm.available:
            self.models.submit_background(
                self._enrich_visual_only,
                image_hash,
                visual_embedding,
            )
            return
        self.models.submit_background(
            self._enrich,
            image_hash,
            image,
            segment.cutout if segment else None,
            top,
            visual_embedding,
        )

    def _enrich_visual_only(
        self,
        image_hash: str,
        visual_embedding: np.ndarray | None,
    ) -> None:
        """Propose category attributes with the already-computed SigLIP vector."""
        try:
            self._apply_enrichment(
                image_hash,
                OcrResult([], None, None),
                VlmAttributes({}, 0.0, "disabled"),
                ["ocr_and_vlm_disabled_visual_fallback_used"],
                {},
                visual_embedding,
            )
        except Exception:
            LOGGER.exception("Visual-only enrichment failed")
            result = self.cache.get(image_hash)
            if result is not None:
                result.enrichment_status = "completed"
                result.warnings = list(
                    dict.fromkeys([*result.warnings, "visual_enrichment_failed"])
                )
                self.cache.put(image_hash, result)
                self._save_result(result)
        finally:
            with self._enrichment_lock:
                self._enrichment_inflight.discard(image_hash)

    def schedule_extra_images(self, image_hash: str, images: list[Image.Image]) -> bool:
        """Fuse a few extra views asynchronously; OCR remains optional."""
        result = self.cache.get(image_hash)
        if not images or result is None:
            return False
        prepared = [
            self._resize(image).copy()
            for image in images[: max(1, self.settings.analysis_extra_visual_images)]
        ]
        with self._enrichment_lock:
            if image_hash in self._extra_enrichment_pending:
                return False
            self._extra_enrichment_pending.add(image_hash)
        result.enrichment_status = "pending"
        self.cache.put(image_hash, result)
        self._save_result(result)
        self.models.submit_background(self._enrich_extra_images, image_hash, prepared)
        return True

    def _enrich(
        self,
        image_hash: str,
        image: Image.Image,
        cutout: Image.Image | None,
        top,
        visual_embedding: np.ndarray | None,
    ) -> None:
        warnings: list[str] = []
        timings: dict[str, int] = {}
        try:
            # Qwen starts immediately and runs independently from the cheap
            # label/logo classifier and OCR path.
            qwen_future = None
            if top is not None and self.models.vlm.available:
                qwen_future = self.models.submit(
                    self._timed,
                    self.models.vlm.analyze,
                    [image],
                    cutout,
                    top.definition.item_type,
                )

            target_future = self.models.submit(
                self._timed,
                self.models.classification.classify_ocr_target,
                image,
            )
            target = self._await_future(
                "ocr_target",
                target_future,
                self.settings.classification_timeout_seconds,
                warnings,
            )
            timings["ocr_target"] = self._future_duration(target_future)
            ocr = OcrResult(texts=[], size=None, composition=None)
            if target in {"tag", "label", "logo"}:
                ocr_future = self.models.submit(
                    self._timed, self.models.ocr.recognize, [image]
                )
                ocr = (
                    self._await_future(
                        "ocr", ocr_future, self.settings.ocr_timeout_seconds, warnings
                    )
                    or ocr
                )
                timings["ocr"] = self._future_duration(ocr_future)
            else:
                timings["ocr"] = 0

            vlm = VlmAttributes({}, 0.0, "qwen_unavailable")
            if qwen_future is not None:
                vlm = (
                    self._await_future(
                        "qwen",
                        qwen_future,
                        self.settings.qwen_timeout_seconds,
                        warnings,
                    )
                    or vlm
                )
                timings["qwen"] = self._future_duration(qwen_future)
            else:
                timings["qwen"] = 0
            self._apply_enrichment(
                image_hash,
                ocr,
                vlm,
                warnings,
                timings,
                visual_embedding,
            )
        except Exception:
            LOGGER.exception("Unexpected enrichment failure")
            self._apply_enrichment(
                image_hash,
                OcrResult([], None, None),
                VlmAttributes({}, 0.0, "qwen_unavailable"),
                ["enrichment_failed"],
                timings,
                visual_embedding,
            )
        finally:
            with self._enrichment_lock:
                self._enrichment_inflight.discard(image_hash)

    def _apply_enrichment(
        self,
        image_hash: str,
        ocr: OcrResult,
        vlm: VlmAttributes,
        warnings: list[str],
        timings: dict[str, int],
        visual_embedding: np.ndarray | None = None,
    ) -> None:
        result = self.cache.get(image_hash)
        if result is None:
            return
        brand = self.brand_matcher.match(ocr.texts)
        material = vlm.values.get("material") or self._material_from_composition(
            ocr.composition
        )
        material_source = (
            vlm.model
            if vlm.values.get("material")
            else ("paddleocr_composition" if material else "not_detected")
        )
        material_confidence = (
            vlm.confidence
            if vlm.values.get("material")
            else (0.78 if material else 0.0)
        )
        gender = vlm.values.get("gender")
        result.section = self._field(
            {"female": "women", "male": "men", "kids": "kids", "unisex": "unisex"}.get(
                gender or ""
            ),
            vlm.confidence,
            vlm.model,
        )
        result.gender = self._field(gender, vlm.confidence, vlm.model)
        result.brand = self._field(
            brand.brand_id if brand else None,
            brand.confidence if brand else 0.0,
            "paddleocr_brand_matcher" if brand else "not_detected",
        )
        if brand and result.item_type.value:
            result.suggested_title = self._field(
                f"{BRANDS.get(brand.brand_id, brand.brand_id)} {result.item_type.value}",
                min(0.72, result.item_type.confidence),
                "pipeline_derived",
            )
        result.material = self._field(material, material_confidence, material_source)
        result.pattern = self._field(
            vlm.values.get("pattern"), vlm.confidence, vlm.model
        )
        result.season = self._field(vlm.values.get("season"), vlm.confidence, vlm.model)
        result.style = self._field(vlm.values.get("style"), vlm.confidence, vlm.model)
        result.fit = self._field(vlm.values.get("fit"), vlm.confidence, vlm.model)
        result.sleeve_length = self._field(
            vlm.values.get("sleeve_length"), vlm.confidence, vlm.model
        )
        result.closure = self._field(
            vlm.values.get("closure"), vlm.confidence, vlm.model
        )
        result.collar = self._field(vlm.values.get("collar"), vlm.confidence, vlm.model)
        result.rise = self._field(vlm.values.get("rise"), vlm.confidence, vlm.model)
        if visual_embedding is not None and result.normalized_category.value:
            suggestions = self.visual_attributes.suggest(
                visual_embedding,
                result.normalized_category.value,
                all_attributes=True,
            )
            for suggestion in suggestions:
                current = getattr(result, suggestion.key)
                if current.value is None:
                    setattr(
                        result,
                        suggestion.key,
                        self._field(
                            suggestion.value,
                            suggestion.confidence,
                            self.visual_attributes.version,
                        ),
                    )
        result.suggested_size = self._field(
            self._normalize_size(ocr.size),
            0.82 if ocr.size else 0.0,
            "paddleocr" if ocr.size else "not_detected",
        )
        result.ocr = OcrPayload(
            texts=ocr.texts, size=ocr.size, composition=ocr.composition
        )
        with self._enrichment_lock:
            has_extra_images = image_hash in self._extra_enrichment_pending
        result.enrichment_status = "pending" if has_extra_images else "completed"
        result.warnings = list(dict.fromkeys([*result.warnings, *warnings]))
        result.timings_ms = {**result.timings_ms, **timings}
        self.cache.put(image_hash, result)
        self._save_result(result)
        LOGGER.info("Background enrichment %s: %s", image_hash[:12], timings)

    def _enrich_extra_images(self, image_hash: str, images: list[Image.Image]) -> None:
        warnings: list[str] = []
        started = time.perf_counter()
        try:
            result = self.cache.get(image_hash)
            if result is None:
                return
            visual_started = time.perf_counter()
            segments: list[
                tuple[
                    Image.Image,
                    SegmentedGarment,
                    list[ColorCandidate],
                    float,
                ]
            ] = []
            for image in images:
                segment = self.models.fast_segmentation.segment(image)
                if segment is None:
                    continue
                quality = self.photo_quality.analyze(image)
                if quality.score < 0.25:
                    continue
                colors = self.color.analyze(
                    np.asarray(image.convert("RGB")),
                    segment.mask,
                )
                segments.append((image, segment, colors, quality.score))

            if segments:
                encoded = self.models.classification.embed_and_classify_many(
                    [segment.cutout for _, segment, _, _ in segments],
                    top_k=1,
                )
                evidence = self._get_evidence(image_hash)
                main_embedding = evidence.embeddings[0] if evidence.embeddings else None
                accepted_embeddings = list(evidence.embeddings)
                accepted_weights = list(evidence.embedding_weights)
                color_batches = list(evidence.color_batches)
                for (_, segment, colors, quality_score), item in zip(
                    segments,
                    encoded,
                    strict=True,
                ):
                    similarity = (
                        float(np.dot(main_embedding, item.embedding))
                        if main_embedding is not None
                        else 1.0
                    )
                    # Reject label/detail shots and unrelated garments. Soft
                    # weighting keeps legitimate rear/side views useful.
                    if similarity < 0.50:
                        continue
                    weight = (
                        max(0.35, min(1.0, similarity))
                        * max(
                            0.45,
                            min(1.0, segment.confidence),
                        )
                        * max(0.25, quality_score)
                    )
                    accepted_embeddings.append(item.embedding)
                    accepted_weights.append(weight)
                    if colors:
                        color_batches.append((weight, colors))

                self._apply_visual_consensus(
                    result,
                    accepted_embeddings,
                    accepted_weights,
                    color_batches,
                )
                self._replace_evidence(
                    image_hash,
                    accepted_embeddings,
                    accepted_weights,
                    color_batches,
                )
            visual_ms = round((time.perf_counter() - visual_started) * 1000)

            if self.models.ocr.available:
                self._apply_extra_ocr(result, images, warnings)

            with self._enrichment_lock:
                self._extra_enrichment_pending.discard(image_hash)
            result.enrichment_status = "completed"
            result.warnings = list(dict.fromkeys([*result.warnings, *warnings]))
            result.timings_ms = {
                **result.timings_ms,
                "visual_extra": visual_ms,
                "extra_total": round((time.perf_counter() - started) * 1000),
            }
            self.cache.put(image_hash, result)
            self._save_result(result)
        except Exception:
            LOGGER.exception("Extra-image enrichment failed")
            with self._enrichment_lock:
                self._extra_enrichment_pending.discard(image_hash)
            result = self.cache.get(image_hash)
            if result is not None:
                result.enrichment_status = "completed"
                result.warnings = list(
                    dict.fromkeys([*result.warnings, "extra_image_enrichment_failed"])
                )
                self.cache.put(image_hash, result)
                self._save_result(result)
        finally:
            with self._enrichment_lock:
                self._extra_enrichment_pending.discard(image_hash)

    def _apply_extra_ocr(
        self,
        result: AnalysisResponse,
        images: list[Image.Image],
        warnings: list[str],
    ) -> None:
        futures = [
            self.models.submit(
                self._timed,
                self.models.classification.classify_ocr_target,
                image,
            )
            for image in images
        ]
        targets = [
            self._await_future(
                "ocr_target",
                future,
                self.settings.classification_timeout_seconds,
                warnings,
            )
            for future in futures
        ]
        selected = [
            image
            for image, target in zip(images, targets)
            if target in {"tag", "label", "logo"}
        ]
        if not selected:
            return
        ocr_future = self.models.submit(
            self._timed,
            self.models.ocr.recognize,
            selected,
        )
        ocr = self._await_future(
            "ocr",
            ocr_future,
            self.settings.ocr_timeout_seconds,
            warnings,
        )
        if ocr is None:
            return
        texts = list(dict.fromkeys([*result.ocr.texts, *ocr.texts]))
        merged = OcrResult(
            texts,
            ocr.size or result.ocr.size,
            ocr.composition or result.ocr.composition,
        )
        brand = self.brand_matcher.match(merged.texts)
        result.ocr = OcrPayload(
            texts=merged.texts,
            size=merged.size,
            composition=merged.composition,
        )
        result.brand = self._field(
            brand.brand_id if brand else None,
            brand.confidence if brand else 0.0,
            "paddleocr_brand_matcher" if brand else "not_detected",
        )
        if brand and result.item_type.value:
            result.suggested_title = self._field(
                f"{BRANDS.get(brand.brand_id, brand.brand_id)} {result.item_type.value}",
                min(0.72, result.item_type.confidence),
                "pipeline_derived",
            )
        material = self._material_from_composition(merged.composition)
        if material and result.material.source in {
            self.visual_attributes.version,
            "not_detected",
            "pending_enrichment",
            "disabled",
            "qwen_unavailable",
        }:
            result.material = self._field(
                material,
                0.78,
                "paddleocr_composition",
            )
        if result.suggested_size.value is None:
            result.suggested_size = self._field(
                self._normalize_size(merged.size),
                0.82 if merged.size else 0.0,
                "paddleocr" if merged.size else "not_detected",
            )

    def _remember_evidence(
        self,
        image_hash: str,
        embedding: np.ndarray | None,
        colors: list[ColorCandidate],
        weight: float,
    ) -> None:
        embeddings = (
            [np.asarray(embedding, dtype=np.float32).copy()]
            if embedding is not None
            else []
        )
        embedding_weights = [weight] if embeddings else []
        color_batches = [(weight, list(colors))] if colors else []
        self._replace_evidence(
            image_hash,
            embeddings,
            embedding_weights,
            color_batches,
        )

    def _replace_evidence(
        self,
        image_hash: str,
        embeddings: list[np.ndarray],
        embedding_weights: list[float],
        color_batches: list[tuple[float, list[ColorCandidate]]],
    ) -> None:
        with self._evidence_lock:
            self._evidence[image_hash] = AnalysisEvidence(
                embeddings=list(embeddings),
                embedding_weights=list(embedding_weights),
                color_batches=[
                    (weight, list(colors)) for weight, colors in color_batches
                ],
            )
            self._evidence.move_to_end(image_hash)
            while len(self._evidence) > self.settings.analysis_cache_size:
                self._evidence.popitem(last=False)

    def _get_evidence(self, image_hash: str) -> AnalysisEvidence:
        with self._evidence_lock:
            evidence = self._evidence.get(image_hash)
            if evidence is None:
                return AnalysisEvidence([], [], [])
            self._evidence.move_to_end(image_hash)
            return AnalysisEvidence(
                embeddings=list(evidence.embeddings),
                embedding_weights=list(evidence.embedding_weights),
                color_batches=[
                    (weight, list(colors)) for weight, colors in evidence.color_batches
                ],
            )

    def _apply_visual_consensus(
        self,
        result: AnalysisResponse,
        embeddings: list[np.ndarray],
        weights: list[float],
        color_batches: list[tuple[float, list[ColorCandidate]]],
    ) -> None:
        category = result.normalized_category.value
        if embeddings and category and len(embeddings) == len(weights):
            for suggestion in self.visual_attributes.suggest_many(
                embeddings,
                category,
                weights,
                all_attributes=True,
            ):
                current = getattr(result, suggestion.key)
                if current.source in {
                    self.visual_attributes.version,
                    "not_detected",
                    "pending_enrichment",
                    "disabled",
                    "qwen_unavailable",
                }:
                    setattr(
                        result,
                        suggestion.key,
                        self._field(
                            suggestion.value,
                            suggestion.confidence,
                            self.visual_attributes.version,
                        ),
                    )

        consensus = self._color_consensus(color_batches)
        if consensus:
            result.primary_color = self._field(
                consensus[0].color_id,
                consensus[0].confidence,
                "opencv_masked_multiview_v1",
            )
            result.secondary_colors = [
                self._field(
                    candidate.color_id,
                    candidate.confidence,
                    "opencv_masked_multiview_v1",
                )
                for candidate in consensus[1:5]
                if candidate.share >= 0.08
            ]

    @staticmethod
    def _color_consensus(
        batches: list[tuple[float, list[ColorCandidate]]],
    ) -> list[ColorCandidate]:
        usable = [(max(0.05, weight), values) for weight, values in batches if values]
        if not usable:
            return []
        total_weight = sum(weight for weight, _ in usable)
        shares: defaultdict[str, float] = defaultdict(float)
        support: defaultdict[str, float] = defaultdict(float)
        for weight, candidates in usable:
            visible = [item for item in candidates if item.color_id != "multicolor"]
            for index, candidate in enumerate(visible):
                shares[candidate.color_id] += weight * candidate.share
                if index == 0 or candidate.share >= 0.12:
                    support[candidate.color_id] += weight

        ranked = sorted(
            shares,
            key=lambda color_id: (
                shares[color_id] / total_weight
                + 0.12 * support[color_id] / total_weight
            ),
            reverse=True,
        )
        colors = [
            ColorCandidate(
                color_id=color_id,
                share=round(shares[color_id] / total_weight, 4),
                confidence=round(
                    min(
                        0.97,
                        0.50
                        + 0.32 * support[color_id] / total_weight
                        + 0.18 * min(1.0, shares[color_id] / total_weight),
                    ),
                    4,
                ),
            )
            for color_id in ranked
        ]
        prominent = [item for item in colors if item.share >= 0.10]
        families = {
            COLOR_FAMILIES.get(item.color_id, item.color_id) for item in prominent
        }
        if len(prominent) >= 3 and len(families) >= 3:
            multicolor = ColorCandidate(
                "multicolor",
                round(sum(item.share for item in prominent[:4]), 4),
                round(min(0.94, 0.68 + 0.06 * len(families)), 4),
            )
            return [multicolor, *colors[:4]]
        return colors[:5]

    @staticmethod
    def _merge_region_candidates(candidate_batches, *, limit: int):
        """Keep the primary garment first and expose other detected types.

        The response schema has one primary item plus a top-k list.  A
        round-robin merge preserves that contract: the largest rembg component
        remains the primary item, while the best distinct type from each other
        component is represented before lower-ranked alternatives.
        """
        if limit <= 0:
            return []
        merged = []
        seen_item_types: set[str] = set()

        def append(candidate) -> None:
            item_type = candidate.definition.item_type
            if item_type in seen_item_types or len(merged) >= limit:
                return
            seen_item_types.add(item_type)
            merged.append(candidate)

        for batch in candidate_batches:
            if batch:
                append(batch[0])
        depth = 1
        while len(merged) < limit and any(
            len(batch) > depth for batch in candidate_batches
        ):
            for batch in candidate_batches:
                if len(batch) > depth:
                    append(batch[depth])
            depth += 1
        return merged

    def _base_response(
        self,
        *,
        image_hash: str,
        candidates,
        colors,
        warnings: list[str],
        timings: dict[str, int],
    ) -> AnalysisResponse:
        top = candidates[0] if candidates else None
        primary = colors[0] if colors else None
        secondary = colors[1:]
        if primary and primary.color_id == "multicolor":
            secondary = colors[1:5]
        category_confidence = top.confidence if top else 0.0
        title = (
            ITEM_TYPE_TITLES.get(top.definition.item_type, top.definition.item_type)
            if top
            else None
        )
        pending = self._field(None, 0.0, "pending_enrichment")
        return AnalysisResponse(
            analysis_id=image_hash,
            enrichment_status="pending",
            section=pending,
            category=self._field(
                top.definition.category if top else None,
                category_confidence,
                self.settings.fashion_model_id if top else "not_detected",
            ),
            subcategory=self._field(
                top.definition.subcategory if top else None,
                category_confidence,
                self.settings.fashion_model_id if top else "not_detected",
            ),
            item_type=self._field(
                top.definition.item_type if top else None,
                category_confidence,
                self.settings.fashion_model_id if top else "not_detected",
            ),
            normalized_category=self._field(
                NORMALIZED_CATEGORIES.get(top.definition.item_type) if top else None,
                category_confidence,
                "taxonomy_normalization_v1" if top else "not_detected",
            ),
            gender=pending,
            audience=pending,
            primary_color=self._field(
                primary.color_id if primary else None,
                primary.confidence if primary else 0.0,
                self.color.source if primary else "not_detected",
            ),
            secondary_colors=[
                self._field(item.color_id, item.confidence, self.color.source)
                for item in secondary
                if item.share >= 0.12
            ],
            brand=pending,
            material=pending,
            pattern=pending,
            season=pending,
            style=pending,
            fit=pending,
            sleeve_length=pending,
            collar=pending,
            rise=pending,
            closure=pending,
            suggested_title=self._field(
                title,
                max(0.5, min(0.72, category_confidence)) if top else 0.0,
                "pipeline_derived",
            ),
            suggested_description=self._field(None, 0.0, "not_generated"),
            suggested_size=pending,
            category_top_k=[
                CategoryCandidate(
                    category=item.definition.category,
                    subcategory=item.definition.subcategory,
                    item_type=item.definition.item_type,
                    confidence=item.confidence,
                )
                for item in candidates
            ],
            ocr=OcrPayload(),
            warnings=list(dict.fromkeys(warnings)),
            timings_ms=timings,
        )

    def _save_result(self, result: AnalysisResponse) -> None:
        if self.result_sink is not None:
            try:
                self.result_sink(result)
            except Exception:
                LOGGER.exception("Result sink failed for %s", result.analysis_id)

    def _stage(
        self,
        stage: str,
        timeout: float,
        operation: Callable[..., T],
        *args,
        warnings: list[str],
    ) -> tuple[T | None, int]:
        future = self.models.submit(self._timed, operation, *args)
        value = self._await_future(stage, future, timeout, warnings)
        return value, self._future_duration(future)

    def _await_future(self, stage: str, future, timeout: float, warnings: list[str]):
        try:
            value, _ = self.models.await_result(future, timeout, stage)
            return value
        except StageTimeoutError:
            warnings.append(f"{stage}_timeout")
        except Exception as error:
            LOGGER.warning("%s failed: %s", stage, error)
            warnings.append(f"{stage}_unavailable:{type(error).__name__}")
        return None

    @staticmethod
    def _timed(operation: Callable[..., T], *args) -> tuple[T, int]:
        started = time.perf_counter()
        value = operation(*args)
        return value, round((time.perf_counter() - started) * 1000)

    @staticmethod
    def _future_duration(future) -> int:
        if future.done() and not future.cancelled():
            try:
                return int(future.result()[1])
            except Exception:
                pass
        return 0

    def _resize(self, image: Image.Image) -> Image.Image:
        result = image.convert("RGB")
        if max(result.size) <= self.settings.max_main_image_side:
            return result
        scale = self.settings.max_main_image_side / max(result.size)
        return result.resize(
            (round(result.width * scale), round(result.height * scale)),
            Image.Resampling.LANCZOS,
        )

    @staticmethod
    def _elapsed_ms(started: float) -> int:
        return round((time.perf_counter() - started) * 1000)

    @staticmethod
    def _remaining_timeout(deadline: float, requested: float) -> float:
        # Keep enough control for constructing and returning a partial result.
        return max(0.01, min(requested, deadline - time.perf_counter()))

    @staticmethod
    def _field(value: str | None, confidence: float, source: str) -> AnalyzedField:
        return AnalyzedField(
            value=value, confidence=max(0.0, min(1.0, confidence)), source=source
        )

    @staticmethod
    def _material_from_composition(value: str | None) -> str | None:
        if not value:
            return None
        normalized = value.casefold()
        mapping = {
            "cotton": ("cotton", "хлопок"),
            "wool": ("wool", "шерсть"),
            "linen": ("linen", "лен", "лён"),
            "denim": ("denim", "деним"),
            "leather": ("leather", "кожа"),
            "polyester": ("polyester", "полиэстер"),
        }
        matches = [
            key
            for key, aliases in mapping.items()
            if any(alias in normalized for alias in aliases)
        ]
        return "mixed" if len(matches) > 1 else (matches[0] if matches else None)

    @staticmethod
    def _normalize_size(value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip().casefold().replace(" ", "_")
        return {
            "one_size": "one_size",
            "onesize": "one_size",
            "xxs": "xxs",
            "xs": "xs",
            "s": "s",
            "m": "m",
            "l": "l",
            "xl": "xl",
            "xxl": "xxl",
        }.get(normalized, value.strip())
