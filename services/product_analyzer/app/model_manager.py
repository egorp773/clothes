from __future__ import annotations

import logging
from concurrent.futures import Future, ThreadPoolExecutor, TimeoutError, as_completed

from PIL import Image

from app.classification.fashion_siglip_adapter import FashionSiglipAdapter
from app.config import Settings
from app.ocr.paddleocr_adapter import PaddleOcrAdapter
from app.segmentation.grounded_sam_adapter import GroundedSamAdapter
from app.segmentation.rembg_adapter import RembgAdapter
from app.vlm.qwen_adapter import QwenAdapter


LOGGER = logging.getLogger(__name__)


class StageTimeoutError(TimeoutError):
    pass


class ModelManager:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.fast_segmentation = RembgAdapter(settings)
        self.clothing_regions = RembgAdapter(
            settings,
            model_name=settings.clothing_region_model_name,
        )
        self.background_removal = (
            self.fast_segmentation
            if settings.background_removal_model_name == settings.rembg_model_name
            else RembgAdapter(
                settings,
                model_name=settings.background_removal_model_name,
            )
        )
        self.segmentation = GroundedSamAdapter(settings)
        self.classification = FashionSiglipAdapter(settings)
        self.ocr = PaddleOcrAdapter(settings)
        self.vlm = QwenAdapter(settings)
        self._executor = ThreadPoolExecutor(
            max_workers=max(2, settings.background_workers + 2),
            thread_name_prefix="analyzer-inference",
        )
        # Enrichment functions coordinate several child inference futures and
        # may wait for OCR/Qwen.  Running those coordinators in the inference
        # pool can occupy every worker and delay the synchronous category path.
        self._background_executor = ThreadPoolExecutor(
            max_workers=max(1, settings.background_workers),
            thread_name_prefix="analyzer-background",
        )

    @property
    def adapters(self) -> dict[str, object]:
        return {
            "fast_segmentation": self.fast_segmentation,
            "clothing_regions": self.clothing_regions,
            "background_removal": self.background_removal,
            "segmentation": self.segmentation,
            "classification": self.classification,
            "ocr": self.ocr,
            "vlm": self.vlm,
        }

    def load_enabled(self) -> None:
        enabled = [
            self.fast_segmentation,
            self.classification,
        ]
        if (
            self.settings.visual_search_enable_clothing_parser
            and self.settings.visual_search_preload_region_model
        ):
            enabled.append(self.clothing_regions)
        if self.settings.preload_slow_models:
            enabled.extend((self.segmentation, self.ocr, self.vlm))
        enabled = [
            adapter for adapter in enabled if getattr(adapter, "available", False)
        ]
        with ThreadPoolExecutor(max_workers=min(3, len(enabled) or 1)) as pool:
            futures = {pool.submit(adapter.load): adapter for adapter in enabled}
            for future in as_completed(futures):
                adapter = futures[future]
                try:
                    future.result()
                except Exception:
                    LOGGER.warning("Adapter failed to load: %s", adapter.model_name)

    def warmup(self) -> None:
        for adapter in (self.fast_segmentation, self.classification):
            if not adapter.available:
                continue
            try:
                adapter.warmup()
            except Exception:
                LOGGER.exception("Warm-up failed for %s", adapter.model_name)
        if (
            self.settings.visual_search_enable_clothing_parser
            and self.settings.visual_search_preload_region_model
            and self.clothing_regions.available
        ):
            try:
                self.clothing_regions.propose_clothing_regions(
                    Image.new("RGB", (256, 384), "white")
                )
            except Exception:
                LOGGER.exception(
                    "Warm-up failed for %s",
                    self.clothing_regions.model_name,
                )

    def submit(self, operation, /, *args, **kwargs) -> Future:
        return self._executor.submit(operation, *args, **kwargs)

    def submit_background(self, operation, /, *args, **kwargs) -> Future:
        return self._background_executor.submit(operation, *args, **kwargs)

    @staticmethod
    def await_result(future: Future, timeout_seconds: float, stage: str):
        try:
            return future.result(timeout=timeout_seconds)
        except TimeoutError as error:
            # The model call may finish later, but it must never keep the HTTP
            # response open. The next request can use the already loaded model.
            future.cancel()
            raise StageTimeoutError(f"{stage} exceeded {timeout_seconds}s") from error

    def close(self) -> None:
        self._background_executor.shutdown(wait=False, cancel_futures=True)
        self._executor.shutdown(wait=False, cancel_futures=True)

    def health(self) -> dict[str, dict[str, object]]:
        return {
            name: {
                "loaded": bool(adapter.loaded),
                "available": bool(adapter.available),
                "model": str(adapter.model_name),
                "detail": adapter.detail,
            }
            for name, adapter in self.adapters.items()
        }
