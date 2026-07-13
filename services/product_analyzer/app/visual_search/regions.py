from __future__ import annotations

import logging
import time
from dataclasses import dataclass, replace

from PIL import Image

from app.classification.fashion_siglip_adapter import FashionCandidate, FashionSiglipAdapter
from app.config import Settings
from app.segmentation.rembg_adapter import ForegroundProposal, RembgAdapter


LOGGER = logging.getLogger(__name__)


@dataclass(frozen=True)
class RegionDetectionResult:
    proposals: list[ForegroundProposal]
    timings_ms: dict[str, int]
    warnings: list[str]


class VisualSearchRegionDetector:
    """Fast region proposals with a guarded clothing-parser fallback.

    Generic foreground segmentation is enough for separated flat-lay items.
    The much slower clothing parser is reserved for an ambiguous full-body
    foreground and is skipped when FashionSigLIP already sees one clear item.
    """

    def __init__(
        self,
        settings: Settings,
        foregrounds: RembgAdapter,
        clothing: RembgAdapter,
        classification: FashionSiglipAdapter,
    ) -> None:
        self.settings = settings
        self.foregrounds = foregrounds
        self.clothing = clothing
        self.classification = classification

    def detect(self, image: Image.Image) -> RegionDetectionResult:
        started = time.perf_counter()
        stage_started = time.perf_counter()
        foregrounds = self.foregrounds.propose_regions(image)
        foreground_ms = self._elapsed_ms(stage_started)

        classification_ms = 0
        clothing_ms = 0
        warnings: list[str] = []
        proposals = foregrounds
        if self._looks_like_full_body(foregrounds, image.size):
            stage_started = time.perf_counter()
            clear_single_item = False
            try:
                candidates = self.classification.classify(image, top_k=2)
                clear_single_item = self._is_clear_single_item(candidates)
                if (
                    clear_single_item
                    and not self._has_confident_single_item(candidates)
                    and self._looks_like_wide_outfit(foregrounds[0], image.size)
                ):
                    # A wide, almost full-frame silhouette is typically a
                    # person/outfit. Whole-frame classification is often
                    # dominated by the jacket and returns jacket/coat as the
                    # top two candidates, hiding the trousers beneath it.
                    clear_single_item = False
            except Exception:
                LOGGER.warning(
                    "Unable to calibrate visual-search region fallback",
                    exc_info=True,
                )
            classification_ms += self._elapsed_ms(stage_started)
            if not clear_single_item:
                clothing: list[ForegroundProposal] = []
                if self.settings.visual_search_enable_clothing_parser:
                    stage_started = time.perf_counter()
                    try:
                        clothing = self.clothing.propose_clothing_regions(image)
                    except Exception:
                        # Region selection is an enhancement. A cold/missing
                        # parser must not make the subsequent search fail.
                        LOGGER.warning(
                            "Clothing region parser unavailable",
                            exc_info=True,
                        )
                        warnings.append("clothing_region_fallback_unavailable")
                    clothing_ms = self._elapsed_ms(stage_started)
                proposals = (
                    self._merge(foregrounds, clothing)
                    if clothing
                    else self._split_full_body(foregrounds[0], image.size)
                )

        if len(proposals) > 1 and any(not proposal.label for proposal in proposals):
            stage_started = time.perf_counter()
            proposals = self._label_unclassified(image, proposals)
            classification_ms += self._elapsed_ms(stage_started)

        return RegionDetectionResult(
            proposals=proposals[:6],
            timings_ms={
                "foreground_segmentation": foreground_ms,
                "classification": classification_ms,
                "clothing_segmentation": clothing_ms,
                "total": self._elapsed_ms(started),
            },
            warnings=warnings,
        )

    def _label_unclassified(
        self,
        image: Image.Image,
        proposals: list[ForegroundProposal],
    ) -> list[ForegroundProposal]:
        indices = [index for index, proposal in enumerate(proposals) if not proposal.label]
        crops = [image.crop(proposals[index].bbox) for index in indices]
        if not crops:
            return proposals
        try:
            candidate_batches = self.classification.classify_many(crops, top_k=2)
        except Exception:
            LOGGER.warning("Unable to label visual-search regions", exc_info=True)
            return proposals

        labelled = list(proposals)
        for index, candidates in zip(indices, candidate_batches):
            if not self._has_label_confidence(candidates):
                continue
            labelled[index] = replace(
                labelled[index],
                label=candidates[0].definition.item_type,
            )
        return labelled

    def _is_clear_single_item(self, candidates: list[FashionCandidate]) -> bool:
        if not candidates:
            return False
        if self._has_confident_single_item(candidates):
            return True
        # A tall standalone garment is commonly ambiguous only within its own
        # family (jeans/trousers, coat/jacket, dress/jumpsuit). Treat that as a
        # single-item signal: geometry alone must never cut a valid product in
        # half. A real outfit usually produces competing upper/lower families.
        return bool(
            len(candidates) > 1
            and candidates[0].confidence
            >= self.settings.visual_search_region_label_min_confidence
            and candidates[0].definition.category
            == candidates[1].definition.category
            and candidates[0].definition.subcategory
            == candidates[1].definition.subcategory
        )

    def _has_confident_single_item(
        self,
        candidates: list[FashionCandidate],
    ) -> bool:
        if not candidates:
            return False
        runner_up = candidates[1].confidence if len(candidates) > 1 else 0.0
        return (
            candidates[0].confidence
            >= self.settings.visual_search_region_single_item_confidence
            and candidates[0].confidence - runner_up
            >= self.settings.visual_search_region_single_item_margin
        )

    @staticmethod
    def _looks_like_wide_outfit(
        foreground: ForegroundProposal,
        image_size: tuple[int, int],
    ) -> bool:
        width, height = image_size
        left, top, right, bottom = foreground.bbox
        box_width = max(1, right - left)
        box_height = max(1, bottom - top)
        return (
            box_height / box_width <= 1.75
            and box_width / max(width, 1) >= 0.55
            and (box_width * box_height) / max(width * height, 1) >= 0.35
        )

    def _has_label_confidence(self, candidates: list[FashionCandidate]) -> bool:
        if not candidates:
            return False
        runner_up = candidates[1].confidence if len(candidates) > 1 else 0.0
        return (
            candidates[0].confidence
            >= self.settings.visual_search_region_label_min_confidence
            and candidates[0].confidence - runner_up
            >= self.settings.visual_search_region_label_min_margin
        )

    @staticmethod
    def _looks_like_full_body(
        foregrounds: list[ForegroundProposal],
        image_size: tuple[int, int],
    ) -> bool:
        if len(foregrounds) != 1:
            return False
        width, height = image_size
        if width <= 0 or height <= 0:
            return False
        left, top, right, bottom = foregrounds[0].bbox
        box_width = max(0, right - left)
        box_height = max(0, bottom - top)
        return (
            box_height / height >= 0.62
            and top / height <= 0.24
            and bottom / height >= 0.76
            and box_height / max(box_width, 1) >= 1.05
            and (box_width * box_height) / (width * height) >= 0.10
        )

    @staticmethod
    def _merge(
        foregrounds: list[ForegroundProposal],
        clothing: list[ForegroundProposal],
    ) -> list[ForegroundProposal]:
        if not clothing:
            return foregrounds
        combined = list(clothing)
        clothing_centers = [
            ((item.bbox[0] + item.bbox[2]) / 2, (item.bbox[1] + item.bbox[3]) / 2)
            for item in clothing
        ]
        for foreground in foregrounds:
            left, top, right, bottom = foreground.bbox
            contains_clothing = any(
                left <= center_x <= right and top <= center_y <= bottom
                for center_x, center_y in clothing_centers
            )
            if not contains_clothing:
                combined.append(foreground)
        return combined if len(combined) > 1 else (foregrounds or combined)

    @staticmethod
    def _split_full_body(
        foreground: ForegroundProposal,
        image_size: tuple[int, int],
    ) -> list[ForegroundProposal]:
        """Create stable upper/lower choices without a multi-gigabyte parser.

        The split is only reached after the full-body shape guard and an
        ambiguous FashionSigLIP result, so a clearly classified dress or a
        standalone item remains one region. Users can still refine either box
        manually in the client.
        """
        image_width, image_height = image_size
        left, top, right, bottom = foreground.bbox
        box_width = max(1, right - left)
        box_height = max(1, bottom - top)
        horizontal_padding = round(box_width * 0.05)
        split_left = max(0, left - horizontal_padding)
        split_right = min(image_width, right + horizontal_padding)
        upper_top = max(0, top + round(box_height * 0.06))
        upper_bottom = min(image_height, top + round(box_height * 0.60))
        lower_top = max(0, top + round(box_height * 0.50))
        lower_bottom = min(image_height, bottom)
        return [
            ForegroundProposal(
                bbox=(split_left, upper_top, split_right, upper_bottom),
                confidence=min(0.9, foreground.confidence * 0.94),
                label="upper_clothing",
            ),
            ForegroundProposal(
                bbox=(split_left, lower_top, split_right, lower_bottom),
                confidence=min(0.86, foreground.confidence * 0.90),
                label="lower_clothing",
            ),
        ]

    @staticmethod
    def _elapsed_ms(started: float) -> int:
        return round((time.perf_counter() - started) * 1000)
