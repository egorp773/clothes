from __future__ import annotations

import gc
import logging
import threading
from dataclasses import dataclass, replace

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
        """Return the dominant garment while retaining the multi-item signal.

        ``segment_many`` does the actual ONNX inference.  Keeping this wrapper
        preserves the original single-item API used by background removal and
        visual search while allowing the analyzer pipeline to consume every
        useful connected foreground without running the model twice.
        """
        segments = self.segment_many(image)
        if not segments:
            return None
        primary = segments[0]
        if len(segments) > 1:
            return replace(primary, label="multiple_foregrounds")
        return primary

    def segment_many(
        self,
        image: Image.Image,
        *,
        max_items: int | None = None,
    ) -> list[SegmentedGarment]:
        """Segment sizeable disconnected garments with one rembg inference."""
        self.load()
        with self._lock:
            from rembg import remove

            rgb_image = image.convert("RGB")
            rgba = remove(rgb_image, session=self._session).convert("RGBA")
            return self._segments_from_rgba(
                rgb_image,
                rgba,
                max_items=max_items or self.settings.max_detected_garments,
            )

    def _segments_from_rgba(
        self,
        rgb_image: Image.Image,
        rgba: Image.Image,
        *,
        max_items: int,
    ) -> list[SegmentedGarment]:
        alpha = np.asarray(rgba.getchannel("A"))
        mask_u8 = (alpha >= self.settings.rembg_alpha_threshold).astype(np.uint8) * 255
        if not mask_u8.any():
            return []
        # Closing a 3x3 neighbourhood removes pinholes but does not join
        # garments separated by a meaningful gap.
        mask_u8 = cv2.morphologyEx(
            mask_u8,
            cv2.MORPH_CLOSE,
            np.ones((3, 3), dtype=np.uint8),
        )
        height, width = mask_u8.shape
        frame_area = float(height * width)
        count, component_labels, stats, _ = cv2.connectedComponentsWithStats(
            mask_u8,
            8,
        )
        component_indices = [
            index
            for index in range(1, count)
            if int(stats[index, cv2.CC_STAT_AREA]) >= max(9, frame_area * 0.0005)
        ]
        groups = self._component_groups(component_indices, stats)
        ranked = sorted(
            groups,
            key=lambda group: sum(
                int(stats[index, cv2.CC_STAT_AREA]) for index in group
            ),
            reverse=True,
        )
        if not ranked:
            return []

        def group_area(group: tuple[int, ...]) -> float:
            return float(
                sum(int(stats[index, cv2.CC_STAT_AREA]) for index in group)
            )

        dominant_area = group_area(ranked[0])
        selected = [ranked[0]]
        for group in ranked[1:]:
            area = group_area(group)
            area_share = area / frame_area
            relative_area = area / max(dominant_area, 1.0)
            if (
                area_share < self.settings.rembg_secondary_component_min_share
                or relative_area
                < self.settings.rembg_secondary_component_min_relative_area
            ):
                continue
            selected.append(group)
            if len(selected) >= max(1, max_items):
                break

        rgb = np.asarray(rgb_image)
        segments: list[SegmentedGarment] = []
        for group in selected[: max(1, max_items)]:
            mask = np.isin(component_labels, group)
            ys, xs = np.where(mask)
            if not len(xs):
                continue
            area_share = float(mask.sum()) / frame_area
            bbox = (
                int(xs.min()),
                int(ys.min()),
                int(xs.max()) + 1,
                int(ys.max()) + 1,
            )
            centrality = max(
                0.0,
                1.0
                - (
                    ((float(xs.mean()) / width) - 0.5) ** 2
                    + ((float(ys.mean()) / height) - 0.5) ** 2
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
                np.dstack([rgb, mask.astype(np.uint8) * 255])
            ).crop(bbox)
            segments.append(
                SegmentedGarment(mask, cutout, bbox, "foreground", confidence)
            )
        return segments

    @classmethod
    def _component_groups(
        cls,
        indices: list[int],
        stats: np.ndarray,
    ) -> list[tuple[int, ...]]:
        """Group paired pieces such as two trouser legs or two shoes.

        Foreground models sometimes disconnect a semantically single item.
        Only close, similarly sized, strongly vertically aligned components are
        joined; distant garments remain independent classification crops.
        """
        parents = {index: index for index in indices}

        def find(index: int) -> int:
            while parents[index] != index:
                parents[index] = parents[parents[index]]
                index = parents[index]
            return index

        def union(first: int, second: int) -> None:
            first_root, second_root = find(first), find(second)
            if first_root != second_root:
                parents[second_root] = first_root

        for position, first in enumerate(indices):
            for second in indices[position + 1 :]:
                if cls._components_form_pair(stats[first], stats[second]):
                    union(first, second)

        grouped: dict[int, list[int]] = {}
        for index in indices:
            grouped.setdefault(find(index), []).append(index)
        return [tuple(group) for group in grouped.values()]

    @staticmethod
    def _components_form_pair(first: np.ndarray, second: np.ndarray) -> bool:
        first_x, first_y, first_width, first_height, first_area = map(int, first)
        second_x, second_y, second_width, second_height, second_area = map(int, second)
        if min(first_width, first_height, second_width, second_height) <= 0:
            return False
        vertical_overlap = max(
            0,
            min(first_y + first_height, second_y + second_height)
            - max(first_y, second_y),
        )
        overlap_share = vertical_overlap / min(first_height, second_height)
        height_ratio = min(first_height, second_height) / max(first_height, second_height)
        area_ratio = min(first_area, second_area) / max(first_area, second_area)
        horizontal_gap = max(
            0,
            max(first_x, second_x)
            - min(first_x + first_width, second_x + second_width),
        )
        return (
            overlap_share >= 0.72
            and height_ratio >= 0.62
            and area_ratio >= 0.35
            and horizontal_gap <= max(4, round(min(first_width, second_width) * 0.45))
        )

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
            records: list[tuple[ForegroundProposal, float]] = []
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
                    if float(stats[index, cv2.CC_STAT_AREA]) / frame_area
                    >= max(0.01, self.settings.rembg_min_area_share * 0.7)
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
                    area_share = float(component_mask.sum()) / frame_area
                    fill_ratio = float(component_mask.sum()) / max(
                        box_width * box_height,
                        1,
                    )
                    if (
                        box_width < max(6, width * 0.045)
                        or box_height < max(6, height * 0.045)
                        or fill_ratio < 0.08
                    ):
                        continue
                    pad_x = max(3, round(box_width * 0.06))
                    pad_y = max(3, round(box_height * 0.06))
                    left, top = max(0, left - pad_x), max(0, top - pad_y)
                    right = min(width, right + pad_x)
                    bottom = min(height, bottom + pad_y)
                    records.append(
                        (
                            ForegroundProposal(
                                bbox=(left, top, right, bottom),
                                confidence=min(
                                    0.95,
                                    0.68
                                    + min(0.18, area_share * 1.5)
                                    + min(0.07, fill_ratio * 0.1),
                                ),
                                label=label,
                            ),
                            area_share,
                        )
                    )
            return self._filter_clothing_regions(records, height=height)

    @classmethod
    def _filter_clothing_regions(
        cls,
        records: list[tuple[ForegroundProposal, float]],
        *,
        height: int,
    ) -> list[ForegroundProposal]:
        """Remove duplicate parse boxes and redundant full-body clothing masks."""
        deduplicated: list[tuple[ForegroundProposal, float]] = []
        for record in records:
            proposal, _ = record
            if any(
                proposal.label == kept.label
                and cls._box_iou(proposal.bbox, kept.bbox) >= 0.82
                for kept, _ in deduplicated
            ):
                continue
            deduplicated.append(record)

        uppers = [
            record
            for record in deduplicated
            if record[0].label == "upper_clothing"
        ]
        lowers = [
            record
            for record in deduplicated
            if record[0].label == "lower_clothing"
        ]
        valid_pairs = [
            (upper, lower)
            for upper in uppers
            for lower in lowers
            if cls._valid_upper_lower_pair(
                upper,
                lower,
                height=height,
            )
        ]

        filtered: list[tuple[ForegroundProposal, float]] = []
        for record in deduplicated:
            proposal, _ = record
            if proposal.label == "full_clothing" and any(
                cls._full_region_covers_pair(proposal, upper[0], lower[0])
                for upper, lower in valid_pairs
            ):
                continue
            filtered.append(record)

        label_order = {
            "upper_clothing": 0,
            "lower_clothing": 1,
            "full_clothing": 2,
        }
        filtered.sort(
            key=lambda record: (
                label_order.get(record[0].label or "", 3),
                record[0].bbox[1],
                record[0].bbox[0],
            )
        )
        return [proposal for proposal, _ in filtered[:6]]

    @classmethod
    def _valid_upper_lower_pair(
        cls,
        upper: tuple[ForegroundProposal, float],
        lower: tuple[ForegroundProposal, float],
        *,
        height: int,
    ) -> bool:
        upper_box, lower_box = upper[0].bbox, lower[0].bbox
        upper_center_y = (upper_box[1] + upper_box[3]) / 2
        lower_center_y = (lower_box[1] + lower_box[3]) / 2
        horizontal_overlap = max(
            0,
            min(upper_box[2], lower_box[2]) - max(upper_box[0], lower_box[0]),
        )
        min_width = max(
            1,
            min(upper_box[2] - upper_box[0], lower_box[2] - lower_box[0]),
        )
        vertical_gap = lower_box[1] - upper_box[3]
        return (
            lower_center_y - upper_center_y >= height * 0.08
            and horizontal_overlap / min_width >= 0.25
            and vertical_gap <= height * 0.18
            and upper[1] + lower[1] >= 0.05
            and cls._box_iou(upper_box, lower_box) < 0.72
        )

    @classmethod
    def _full_region_covers_pair(
        cls,
        full: ForegroundProposal,
        upper: ForegroundProposal,
        lower: ForegroundProposal,
    ) -> bool:
        return (
            cls._box_coverage(full.bbox, upper.bbox) >= 0.45
            and cls._box_coverage(full.bbox, lower.bbox) >= 0.45
        )

    @staticmethod
    def _box_coverage(
        container: tuple[int, int, int, int],
        target: tuple[int, int, int, int],
    ) -> float:
        intersection = RembgAdapter._box_intersection(container, target)
        target_area = max(1, (target[2] - target[0]) * (target[3] - target[1]))
        return intersection / target_area

    @staticmethod
    def _box_iou(
        first: tuple[int, int, int, int],
        second: tuple[int, int, int, int],
    ) -> float:
        intersection = RembgAdapter._box_intersection(first, second)
        first_area = max(0, (first[2] - first[0]) * (first[3] - first[1]))
        second_area = max(0, (second[2] - second[0]) * (second[3] - second[1]))
        return intersection / max(first_area + second_area - intersection, 1)

    @staticmethod
    def _box_intersection(
        first: tuple[int, int, int, int],
        second: tuple[int, int, int, int],
    ) -> int:
        width = max(0, min(first[2], second[2]) - max(first[0], second[0]))
        height = max(0, min(first[3], second[3]) - max(first[1], second[1]))
        return width * height

    def warmup(self) -> None:
        self.segment(Image.new("RGB", (256, 256), "white"))
