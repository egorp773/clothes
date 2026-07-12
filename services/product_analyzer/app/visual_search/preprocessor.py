from __future__ import annotations

import time
from dataclasses import dataclass

from PIL import Image, ImageOps

from app.config import Settings
from app.segmentation.rembg_adapter import RembgAdapter


@dataclass(frozen=True)
class PreparedSearchImage:
    image: Image.Image
    timings_ms: dict[str, int]
    warning: str | None = None


class VisualSearchPreprocessor:
    def __init__(self, settings: Settings, segmentation: RembgAdapter) -> None:
        self.settings = settings
        self.segmentation = segmentation

    def prepare(self, image: Image.Image) -> PreparedSearchImage:
        started = time.perf_counter()
        normalized = ImageOps.exif_transpose(image).convert("RGB")
        normalized.thumbnail(
            (self.settings.visual_search_max_side, self.settings.visual_search_max_side),
            Image.Resampling.LANCZOS,
        )
        resize_ms = round((time.perf_counter() - started) * 1000)
        segmentation_started = time.perf_counter()
        segment = self.segmentation.segment(normalized)
        segmentation_ms = round((time.perf_counter() - segmentation_started) * 1000)
        warning = None
        if segment is None:
            prepared = normalized
            warning = "fast_segmentation_unavailable"
        else:
            rgba = segment.cutout.convert("RGBA")
            background = Image.new("RGBA", rgba.size, "white")
            prepared = Image.alpha_composite(background, rgba).convert("RGB")
            if segment.label == "multiple_foregrounds":
                warning = "multiple_items_dominant_foreground_used"
        return PreparedSearchImage(
            image=prepared,
            timings_ms={"resize": resize_ms, "segmentation": segmentation_ms},
            warning=warning,
        )
