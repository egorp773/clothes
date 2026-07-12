from __future__ import annotations

import logging
import threading

import cv2
import numpy as np
from PIL import Image

from app.config import Settings
from app.segmentation.grounded_sam_adapter import SegmentedGarment


LOGGER = logging.getLogger(__name__)


class RembgAdapter:
    """Lightweight foreground segmentation used on the synchronous path."""

    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._lock = threading.Lock()
        self._loaded = False
        self._load_error: str | None = None
        self._session = None

    @property
    def model_name(self) -> str:
        return f"rembg/{self.settings.rembg_model_name}"

    @property
    def available(self) -> bool:
        try:
            import rembg  # noqa: F401

            return True
        except ImportError:
            return False

    @property
    def loaded(self) -> bool:
        return self._loaded

    @property
    def detail(self) -> str | None:
        return self._load_error

    def load(self) -> None:
        if self._loaded:
            return
        with self._lock:
            if self._loaded:
                return
            if not self.available:
                self._load_error = "rembg is not installed"
                raise RuntimeError(self._load_error)
            try:
                from rembg import new_session

                self._session = new_session(self.settings.rembg_model_name)
                self._loaded = True
                self._load_error = None
                LOGGER.info("Loaded %s", self.model_name)
            except Exception as error:
                self._load_error = f"{type(error).__name__}: {error}"
                LOGGER.exception("Unable to load %s", self.model_name)
                raise

    def segment(self, image: Image.Image) -> SegmentedGarment | None:
        self.load()
        with self._lock:
            from rembg import remove

            rgb_image = image.convert("RGB")
            rgba = remove(rgb_image, session=self._session).convert("RGBA")
            alpha = np.asarray(rgba.getchannel("A"))
            mask = alpha >= self.settings.rembg_alpha_threshold
            if not mask.any():
                return None
            # Close tiny holes without merging separate garments; connected
            # components below are also used as the multi-item signal.
            mask_u8 = (mask.astype(np.uint8) * 255)
            mask_u8 = cv2.morphologyEx(
                mask_u8,
                cv2.MORPH_CLOSE,
                np.ones((3, 3), dtype=np.uint8),
            )
            mask = mask_u8.astype(bool)
            height, width = mask.shape
            components, labels, stats, _ = cv2.connectedComponentsWithStats(mask_u8, 8)
            frame_area = float(height * width)
            significant = [
                index
                for index in range(1, components)
                if stats[index, cv2.CC_STAT_AREA] / frame_area
                >= self.settings.rembg_secondary_component_min_share
            ]
            # Retain the dominant foreground only. A second sizeable component
            # is intentionally exposed through the label for SAM fallback.
            if significant:
                best = max(significant, key=lambda index: stats[index, cv2.CC_STAT_AREA])
                mask = labels == best
                mask_u8 = mask.astype(np.uint8) * 255
            area_share = float(mask.sum()) / frame_area
            if not mask.any():
                return None
            ys, xs = np.where(mask)
            bbox = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
            centrality = max(
                0.0,
                1.0
                - (((xs.mean() / width) - 0.5) ** 2 + ((ys.mean() / height) - 0.5) ** 2),
            )
            area_quality = 1.0 if self.settings.rembg_min_area_share <= area_share <= self.settings.rembg_max_area_share else 0.2
            confidence = min(0.98, 0.55 * area_quality + 0.45 * centrality)
            cutout = Image.fromarray(np.dstack([np.asarray(rgb_image), mask.astype(np.uint8) * 255])).crop(bbox)
            label = "multiple_foregrounds" if len(significant) > 1 else "foreground"
            return SegmentedGarment(mask, cutout, bbox, label, confidence)

    def is_acceptable(self, segment: SegmentedGarment | None) -> bool:
        if segment is None or segment.label == "multiple_foregrounds":
            return False
        area = float(segment.mask.mean())
        return (
            segment.confidence >= self.settings.rembg_min_quality
            and self.settings.rembg_min_area_share <= area <= self.settings.rembg_max_area_share
        )

    def warmup(self) -> None:
        self.segment(Image.new("RGB", (256, 256), "white"))
