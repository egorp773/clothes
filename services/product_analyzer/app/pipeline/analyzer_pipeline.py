from __future__ import annotations

import logging
import threading
import time
from collections import OrderedDict
from dataclasses import dataclass
from typing import Callable, TypeVar

import numpy as np
from PIL import Image

from app.catalog import BRANDS, ITEM_TYPE_TITLES
from app.color.masked_color_analyzer import ColorCandidate, MaskedColorAnalyzer
from app.config import Settings
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
            self._entries[key] = CacheEntry(result.model_copy(deep=True), time.monotonic() + self.ttl_seconds)
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
        self.brand_matcher = BrandMatcher(settings.brand_match_threshold)
        self.cache = AnalysisCache(settings.analysis_cache_size, settings.analysis_cache_ttl_seconds)
        self.result_sink = result_sink
        self._enrichment_inflight: set[str] = set()
        self._enrichment_lock = threading.Lock()

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

        fast_segment, segment_ms = self._stage(
            "rembg_segmentation",
            self._remaining_timeout(deadline, self.settings.fast_segmentation_timeout_seconds),
            self.models.fast_segmentation.segment,
            main_image,
            warnings=warnings,
        )
        timings["rembg_segmentation"] = segment_ms
        segment = fast_segment
        fallback_ms = 0
        if not self.models.fast_segmentation.is_acceptable(fast_segment):
            warnings.append("rembg_mask_low_quality_or_multiple_items")
            fallback_segment, fallback_ms = self._stage(
                "grounded_sam_fallback",
                self._remaining_timeout(deadline, self.settings.fallback_segmentation_timeout_seconds),
                self.models.segmentation.segment,
                main_image,
                warnings=warnings,
            )
            if fallback_segment is not None:
                segment = fallback_segment
        timings["grounded_sam_fallback"] = fallback_ms
        timings["segmentation"] = segment_ms + fallback_ms

        classification_image = segment.cutout if segment is not None else main_image
        category_future = self.models.submit(self._timed, self.models.classification.classify, classification_image)
        color_future = None
        if segment is not None:
            color_future = self.models.submit(
                self._timed,
                self.color.analyze,
                np.asarray(main_image.convert("RGB")),
                segment.mask,
            )

        candidates = self._await_future(
            "fashion_siglip",
            category_future,
            self._remaining_timeout(deadline, self.settings.classification_timeout_seconds),
            warnings,
        )
        if candidates is None:
            candidates = []
        timings["fashion_siglip"] = self._future_duration(category_future)

        color_candidates: list[ColorCandidate] = []
        if color_future is None:
            warnings.append("color_skipped_without_mask")
            timings["color"] = 0
        else:
            color_candidates = self._await_future("color", color_future, self._remaining_timeout(deadline, 2.0), warnings) or []
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
        self.cache.put(image_hash, result)
        self._schedule_enrichment(image_hash, main_image.copy(), segment, top)
        LOGGER.info("Fast analysis %s: %s", image_hash[:12], timings)
        cached = self.cache.get(image_hash)
        return cached or result

    def _schedule_enrichment(
        self,
        image_hash: str,
        image: Image.Image,
        segment: SegmentedGarment | None,
        top,
    ) -> None:
        with self._enrichment_lock:
            if image_hash in self._enrichment_inflight:
                return
            self._enrichment_inflight.add(image_hash)
        result = self.cache.get(image_hash)
        if result is not None:
            result.enrichment_status = "pending"
            self.cache.put(image_hash, result)
        self.models.submit(self._enrich, image_hash, image, segment.cutout if segment else None, top)

    def schedule_extra_images(self, image_hash: str, images: list[Image.Image]) -> bool:
        """Queue detail shots after the fast result; only OCR-worthy shots are read."""
        if not images or self.cache.get(image_hash) is None:
            return False
        prepared = [self._resize(image).copy() for image in images]
        self.models.submit(self._enrich_extra_images, image_hash, prepared)
        return True

    def _enrich(self, image_hash: str, image: Image.Image, cutout: Image.Image | None, top) -> None:
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
            target = self._await_future("ocr_target", target_future, self.settings.classification_timeout_seconds, warnings)
            timings["ocr_target"] = self._future_duration(target_future)
            ocr = OcrResult(texts=[], size=None, composition=None)
            if target in {"tag", "label", "logo"}:
                ocr_future = self.models.submit(self._timed, self.models.ocr.recognize, [image])
                ocr = self._await_future("ocr", ocr_future, self.settings.ocr_timeout_seconds, warnings) or ocr
                timings["ocr"] = self._future_duration(ocr_future)
            else:
                timings["ocr"] = 0

            vlm = VlmAttributes({}, 0.0, "qwen_unavailable")
            if qwen_future is not None:
                vlm = self._await_future("qwen", qwen_future, self.settings.qwen_timeout_seconds, warnings) or vlm
                timings["qwen"] = self._future_duration(qwen_future)
            else:
                timings["qwen"] = 0
            self._apply_enrichment(image_hash, ocr, vlm, warnings, timings)
        except Exception:
            LOGGER.exception("Unexpected enrichment failure")
            self._apply_enrichment(image_hash, OcrResult([], None, None), VlmAttributes({}, 0.0, "qwen_unavailable"), ["enrichment_failed"], timings)
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
    ) -> None:
        result = self.cache.get(image_hash)
        if result is None:
            return
        brand = self.brand_matcher.match(ocr.texts)
        material = vlm.values.get("material") or self._material_from_composition(ocr.composition)
        material_source = vlm.model if vlm.values.get("material") else ("paddleocr_composition" if material else "not_detected")
        material_confidence = vlm.confidence if vlm.values.get("material") else (0.78 if material else 0.0)
        gender = vlm.values.get("gender")
        result.section = self._field({"female": "women", "male": "men", "kids": "kids", "unisex": "unisex"}.get(gender or ""), vlm.confidence, vlm.model)
        result.gender = self._field(gender, vlm.confidence, vlm.model)
        result.brand = self._field(brand.brand_id if brand else None, brand.confidence if brand else 0.0, "paddleocr_brand_matcher" if brand else "not_detected")
        if brand and result.item_type.value:
            result.suggested_title = self._field(
                f"{BRANDS.get(brand.brand_id, brand.brand_id)} {result.item_type.value}",
                min(0.72, result.item_type.confidence),
                "pipeline_derived",
            )
        result.material = self._field(material, material_confidence, material_source)
        result.pattern = self._field(vlm.values.get("pattern"), vlm.confidence, vlm.model)
        result.season = self._field(vlm.values.get("season"), vlm.confidence, vlm.model)
        result.style = self._field(vlm.values.get("style"), vlm.confidence, vlm.model)
        result.fit = self._field(vlm.values.get("fit"), vlm.confidence, vlm.model)
        result.sleeve_length = self._field(vlm.values.get("sleeve_length"), vlm.confidence, vlm.model)
        result.closure = self._field(vlm.values.get("closure"), vlm.confidence, vlm.model)
        result.suggested_size = self._field(self._normalize_size(ocr.size), 0.82 if ocr.size else 0.0, "paddleocr" if ocr.size else "not_detected")
        result.ocr = OcrPayload(texts=ocr.texts, size=ocr.size, composition=ocr.composition)
        result.enrichment_status = "completed"
        result.warnings = list(dict.fromkeys([*result.warnings, *warnings]))
        result.timings_ms = {**result.timings_ms, **timings}
        self.cache.put(image_hash, result)
        self._save_result(result)
        LOGGER.info("Background enrichment %s: %s", image_hash[:12], timings)

    def _enrich_extra_images(self, image_hash: str, images: list[Image.Image]) -> None:
        warnings: list[str] = []
        started = time.perf_counter()
        try:
            futures = [
                self.models.submit(self._timed, self.models.classification.classify_ocr_target, image)
                for image in images
            ]
            targets = [
                self._await_future("ocr_target", future, self.settings.classification_timeout_seconds, warnings)
                for future in futures
            ]
            selected = [image for image, target in zip(images, targets) if target in {"tag", "label", "logo"}]
            if not selected:
                return
            ocr_future = self.models.submit(self._timed, self.models.ocr.recognize, selected)
            ocr = self._await_future("ocr", ocr_future, self.settings.ocr_timeout_seconds, warnings)
            if ocr is None:
                return
            result = self.cache.get(image_hash)
            if result is None:
                return
            texts = list(dict.fromkeys([*result.ocr.texts, *ocr.texts]))
            merged = OcrResult(texts, ocr.size or result.ocr.size, ocr.composition or result.ocr.composition)
            brand = self.brand_matcher.match(merged.texts)
            result.ocr = OcrPayload(texts=merged.texts, size=merged.size, composition=merged.composition)
            result.brand = self._field(brand.brand_id if brand else None, brand.confidence if brand else 0.0, "paddleocr_brand_matcher" if brand else "not_detected")
            if brand and result.item_type.value:
                result.suggested_title = self._field(
                    f"{BRANDS.get(brand.brand_id, brand.brand_id)} {result.item_type.value}",
                    min(0.72, result.item_type.confidence),
                    "pipeline_derived",
                )
            if result.material.value is None:
                material = self._material_from_composition(merged.composition)
                result.material = self._field(material, 0.78 if material else 0.0, "paddleocr_composition" if material else "not_detected")
            if result.suggested_size.value is None:
                result.suggested_size = self._field(self._normalize_size(merged.size), 0.82 if merged.size else 0.0, "paddleocr" if merged.size else "not_detected")
            result.enrichment_status = "completed"
            result.warnings = list(dict.fromkeys([*result.warnings, *warnings]))
            result.timings_ms = {**result.timings_ms, "ocr_extra": round((time.perf_counter() - started) * 1000)}
            self.cache.put(image_hash, result)
            self._save_result(result)
        except Exception:
            LOGGER.exception("Extra-image enrichment failed")

    def _base_response(self, *, image_hash: str, candidates, colors, warnings: list[str], timings: dict[str, int]) -> AnalysisResponse:
        top = candidates[0] if candidates else None
        primary = colors[0] if colors else None
        secondary = colors[1:]
        if primary and primary.color_id == "multicolor":
            secondary = colors[1:5]
        category_confidence = top.confidence if top else 0.0
        title = ITEM_TYPE_TITLES.get(top.definition.item_type, top.definition.item_type) if top else None
        pending = self._field(None, 0.0, "pending_enrichment")
        return AnalysisResponse(
            analysis_id=image_hash,
            enrichment_status="pending",
            section=pending,
            category=self._field(top.definition.category if top else None, category_confidence, self.settings.fashion_model_id if top else "not_detected"),
            subcategory=self._field(top.definition.subcategory if top else None, category_confidence, self.settings.fashion_model_id if top else "not_detected"),
            item_type=self._field(top.definition.item_type if top else None, category_confidence, self.settings.fashion_model_id if top else "not_detected"),
            gender=pending,
            primary_color=self._field(primary.color_id if primary else None, primary.confidence if primary else 0.0, self.color.source if primary else "not_detected"),
            secondary_colors=[self._field(item.color_id, item.confidence, self.color.source) for item in secondary if item.share >= 0.12],
            brand=pending,
            material=pending,
            pattern=pending,
            season=pending,
            style=pending,
            fit=pending,
            sleeve_length=pending,
            closure=pending,
            suggested_title=self._field(
                title,
                max(0.5, min(0.72, category_confidence)) if top else 0.0,
                "pipeline_derived",
            ),
            suggested_description=self._field(None, 0.0, "not_generated"),
            suggested_size=pending,
            category_top_k=[CategoryCandidate(category=item.definition.category, subcategory=item.definition.subcategory, item_type=item.definition.item_type, confidence=item.confidence) for item in candidates],
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

    def _stage(self, stage: str, timeout: float, operation: Callable[..., T], *args, warnings: list[str]) -> tuple[T | None, int]:
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
        return result.resize((round(result.width * scale), round(result.height * scale)), Image.Resampling.LANCZOS)

    @staticmethod
    def _elapsed_ms(started: float) -> int:
        return round((time.perf_counter() - started) * 1000)

    @staticmethod
    def _remaining_timeout(deadline: float, requested: float) -> float:
        # Keep enough control for constructing and returning a partial result.
        return max(0.01, min(requested, deadline - time.perf_counter()))

    @staticmethod
    def _field(value: str | None, confidence: float, source: str) -> AnalyzedField:
        return AnalyzedField(value=value, confidence=max(0.0, min(1.0, confidence)), source=source)

    @staticmethod
    def _material_from_composition(value: str | None) -> str | None:
        if not value:
            return None
        normalized = value.casefold()
        mapping = {"cotton": ("cotton", "хлопок"), "wool": ("wool", "шерсть"), "linen": ("linen", "лен", "лён"), "denim": ("denim", "деним"), "leather": ("leather", "кожа"), "polyester": ("polyester", "полиэстер")}
        matches = [key for key, aliases in mapping.items() if any(alias in normalized for alias in aliases)]
        return "mixed" if len(matches) > 1 else (matches[0] if matches else None)

    @staticmethod
    def _normalize_size(value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip().casefold().replace(" ", "_")
        return {"one_size": "one_size", "onesize": "one_size", "xxs": "xxs", "xs": "xs", "s": "s", "m": "m", "l": "l", "xl": "xl", "xxl": "xxl"}.get(normalized, value.strip())
