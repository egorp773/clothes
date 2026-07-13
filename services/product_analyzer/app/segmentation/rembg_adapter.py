from __future__ import annotations

import gc
import logging
import threading
from dataclasses import dataclass

import cv2
import numpy as np
from PIL import Image

from app.config import Settings
from app.segmentation.grounded_sam_adapter import SegmentedGarment


LOGGER = logging.getLogger(__name__)


@dataclass(frozen=True)
class ForegroundProposal:
    bbox: tuple[int, int, int, int]
    confidence: float
    label: str | None = None


class RembgAdapter:
    """Lightweight foreground segmentation used on the synchronous path."""

    def __init__(self, settings: Settings, model_name: str | None = None) -> None:
        self.settings = settings
        self.rembg_model_name = model_name or settings.rembg_model_name
        self._lock = threading.Lock()
        self._loaded = False
        self._load_error: str | None = None
        self._session = None

    @property
    def model_name(self) -> str:
        return f"rembg/{self.rembg_model_name}"

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

                self._session = new_session(self.rembg_model_name)
                self._loaded = True
                self._load_error = None
                LOGGER.info("Loaded %s", self.model_name)
            except Exception as error:
                self._load_error = f"{type(error).__name__}: {error}"
                LOGGER.exception("Unable to load %s", self.model_name)
                raise

    def unload(self) -> None:
        """Release a lazy ONNX session before another large CPU model loads."""
        with self._lock:
            self._session = None
            self._loaded = False
        gc.collect()

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
            mask_u8 = mask.astype(np.uint8) * 255
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
                best = max(
                    significant, key=lambda index: stats[index, cv2.CC_STAT_AREA]
                )
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
                - (
                    ((xs.mean() / width) - 0.5) ** 2 + ((ys.mean() / height) - 0.5) ** 2
                ),
            )
            area_quality = (
                1.0
                if self.settings.rembg_min_area_share
                <= area_share
                <= self.settings.rembg_max_area_share
                else 0.2
            )
            confidence = min(0.98, 0.55 * area_quality + 0.45 * centrality)
            cutout = Image.fromarray(
                np.dstack([np.asarray(rgb_image), mask.astype(np.uint8) * 255])
            ).crop(bbox)
            label = "multiple_foregrounds" if len(significant) > 1 else "foreground"
            return SegmentedGarment(mask, cutout, bbox, label, confidence)

    def is_acceptable(self, segment: SegmentedGarment | None) -> bool:
        if segment is None or segment.label == "multiple_foregrounds":
            return False
        area = float(segment.mask.mean())
        return (
            segment.confidence >= self.settings.rembg_min_quality
            and self.settings.rembg_min_area_share
            <= area
            <= self.settings.rembg_max_area_share
        )

    def remove_background(self, image: Image.Image) -> Image.Image:
        """Return the model's soft alpha matte without thresholding fine edges."""
        self.load()
        with self._lock:
            from rembg import remove

            return remove(
                image.convert("RGB"),
                session=self._session,
                post_process_mask=False,
            ).convert("RGBA")

    def propose_regions(self, image: Image.Image) -> list[ForegroundProposal]:
        """Return sizeable disconnected foregrounds from the existing U2Net mask."""
        self.load()
        with self._lock:
            from rembg import remove

            rgb_image = image.convert("RGB")
            rgba = remove(rgb_image, session=self._session).convert("RGBA")
            alpha = np.asarray(rgba.getchannel("A"))
            mask_u8 = (alpha >= self.settings.rembg_alpha_threshold).astype(
                np.uint8
            ) * 255
            if not mask_u8.any():
                return []
            mask_u8 = cv2.morphologyEx(
                mask_u8,
                cv2.MORPH_CLOSE,
                np.ones((3, 3), dtype=np.uint8),
            )
            height, width = mask_u8.shape
            frame_area = float(height * width)
            count, _, stats, _ = cv2.connectedComponentsWithStats(mask_u8, 8)
            min_share = max(0.012, self.settings.rembg_min_area_share * 0.8)
            proposals: list[ForegroundProposal] = []
            for index in range(1, count):
                x = int(stats[index, cv2.CC_STAT_LEFT])
                y = int(stats[index, cv2.CC_STAT_TOP])
                box_width = int(stats[index, cv2.CC_STAT_WIDTH])
                box_height = int(stats[index, cv2.CC_STAT_HEIGHT])
                area_share = float(stats[index, cv2.CC_STAT_AREA]) / frame_area
                if (
                    area_share < min_share
                    or box_width < width * 0.06
                    or box_height < height * 0.06
                ):
                    continue
                pad_x = max(3, round(box_width * 0.06))
                pad_y = max(3, round(box_height * 0.06))
                left = max(0, x - pad_x)
                top = max(0, y - pad_y)
                right = min(width, x + box_width + pad_x)
                bottom = min(height, y + box_height + pad_y)
                center_x = (left + right) / (2 * width)
                center_y = (top + bottom) / (2 * height)
                centrality = max(
                    0.0,
                    1.0 - ((center_x - 0.5) ** 2 + (center_y - 0.5) ** 2),
                )
                confidence = min(0.97, 0.62 + min(area_share, 0.25) + 0.1 * centrality)
                proposals.append(
                    ForegroundProposal(
                        bbox=(left, top, right, bottom),
                        confidence=confidence,
                    )
                )
            proposals.sort(
                key=lambda proposal: (
                    (proposal.bbox[2] - proposal.bbox[0])
                    * (proposal.bbox[3] - proposal.bbox[1])
                ),
                reverse=True,
            )
            return proposals[:6]

    def propose_clothing_regions(
        self,
        image: Image.Image,
    ) -> list[ForegroundProposal]:
        """Split clothing on a person into upper, lower, and full-body regions."""
        self.load()
        with self._lock:
            rgb_image = image.convert("RGB")
            masks = self._session.predict(rgb_image)
            labels = ("upper_clothing", "lower_clothing", "full_clothing")
            height, width = rgb_image.height, rgb_image.width
            frame_area = float(height * width)
            proposals: list[ForegroundProposal] = []
            for label, raw_mask in zip(labels, masks):
                mask = np.asarray(raw_mask.convert("L")) >= 96
                mask_u8 = mask.astype(np.uint8) * 255
                mask_u8 = cv2.morphologyEx(
                    mask_u8,
                    cv2.MORPH_CLOSE,
                    np.ones((5, 5), dtype=np.uint8),
                )
                if not mask_u8.any():
                    continue
                count, component_labels, stats, _ = cv2.connectedComponentsWithStats(
                    mask_u8,
                    8,
                )
                significant = [
                    index
                    for index in range(1, count)
                    if float(stats[index, cv2.CC_STAT_AREA]) / frame_area >= 0.012
                ]
                if not significant:
                    continue
                significant.sort(
                    key=lambda index: stats[index, cv2.CC_STAT_AREA],
                    reverse=True,
                )
                for index in significant[:3]:
                    component_mask = component_labels == index
                    ys, xs = np.where(component_mask)
                    if not len(xs):
                        continue
                    left, top = int(xs.min()), int(ys.min())
                    right, bottom = int(xs.max()) + 1, int(ys.max()) + 1
                    box_width, box_height = right - left, bottom - top
                    pad_x = max(3, round(box_width * 0.06))
                    pad_y = max(3, round(box_height * 0.06))
                    left, top = max(0, left - pad_x), max(0, top - pad_y)
                    right = min(width, right + pad_x)
                    bottom = min(height, bottom + pad_y)
                    area_share = float(component_mask.sum()) / frame_area
                    proposals.append(
                        ForegroundProposal(
                            bbox=(left, top, right, bottom),
                            confidence=min(0.94, 0.72 + area_share),
                            label=label,
                        )
                    )
            return proposals

    def warmup(self) -> None:
        self.segment(Image.new("RGB", (256, 256), "white"))
