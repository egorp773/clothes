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


@dataclass(frozen=True)
class PreparedQueryImages:
    context: Image.Image
    foreground: Image.Image | None
    timings_ms: dict[str, int]
    warnings: list[str]


class VisualSearchPreprocessor:
    def __init__(self, settings: Settings, segmentation: RembgAdapter) -> None:
        self.settings = settings
        self.segmentation = segmentation

    def prepare_query(self, image: Image.Image) -> PreparedSearchImage:
        """Normalize an already selected search crop without segmenting it again.

        Camera search performs object/garment region detection before this
        endpoint is called.  Running generic foreground removal a second time
        is both expensive and unsafe: connected garment parts (trouser legs,
        shoes, sleeves) can be mistaken for separate objects and only one part
        then reaches FashionSigLIP.  FashionSigLIP is trained on normal fashion
        photographs, so keeping the selected crop is the safer query path.

        Product indexing intentionally keeps ``prepare`` below for backwards
        compatibility with the embeddings already stored in pgvector.
        """
        started = time.perf_counter()
        normalized = self._normalize(image)
        resize_ms = round((time.perf_counter() - started) * 1000)
        return PreparedSearchImage(
            image=normalized,
            timings_ms={"resize": resize_ms, "segmentation": 0},
        )

    def prepare_query_variants(self, image: Image.Image) -> PreparedQueryImages:
        """Build a context view and a foreground-first view of a manual crop."""
        started = time.perf_counter()
        context = self._normalize(image)
        resize_ms = round((time.perf_counter() - started) * 1000)
        segmentation_started = time.perf_counter()
        segment = self.segmentation.segment(context)
        segmentation_ms = round((time.perf_counter() - segmentation_started) * 1000)
        if segment is None:
            return PreparedQueryImages(
                context=context,
                foreground=None,
                timings_ms={"resize": resize_ms, "segmentation": segmentation_ms},
                warnings=["query_foreground_unavailable"],
            )
        warnings = []
        if segment.label == "multiple_foregrounds":
            warnings.append("query_multiple_foregrounds_dominant_used")
        return PreparedQueryImages(
            context=context,
            foreground=self._white_composite(segment.cutout),
            timings_ms={"resize": resize_ms, "segmentation": segmentation_ms},
            warnings=warnings,
        )

    def prepare(self, image: Image.Image) -> PreparedSearchImage:
        started = time.perf_counter()
        normalized = self._normalize(image)
        resize_ms = round((time.perf_counter() - started) * 1000)
        segmentation_started = time.perf_counter()
        segment = self.segmentation.segment(normalized)
        segmentation_ms = round((time.perf_counter() - segmentation_started) * 1000)
        warning = None
        if segment is None:
            prepared = normalized
            warning = "fast_segmentation_unavailable"
        else:
            prepared = self._white_composite(segment.cutout)
            if segment.label == "multiple_foregrounds":
                warning = "multiple_items_dominant_foreground_used"
        return PreparedSearchImage(
            image=prepared,
            timings_ms={"resize": resize_ms, "segmentation": segmentation_ms},
            warning=warning,
        )

    def prepare_cutout(self, image: Image.Image) -> PreparedSearchImage:
        started = time.perf_counter()
        prepared = self._white_composite(ImageOps.exif_transpose(image))
        prepared.thumbnail(
            (self.settings.visual_search_max_side, self.settings.visual_search_max_side),
            Image.Resampling.LANCZOS,
        )
        return PreparedSearchImage(
            image=prepared,
            timings_ms={
                "resize": round((time.perf_counter() - started) * 1000),
                "segmentation": 0,
            },
        )

    def _normalize(self, image: Image.Image) -> Image.Image:
        normalized = ImageOps.exif_transpose(image).convert("RGB")
        normalized.thumbnail(
            (self.settings.visual_search_max_side, self.settings.visual_search_max_side),
            Image.Resampling.LANCZOS,
        )
        return normalized

    @staticmethod
    def _white_composite(image: Image.Image) -> Image.Image:
        rgba = image.convert("RGBA")
        background = Image.new("RGBA", rgba.size, "white")
        return Image.alpha_composite(background, rgba).convert("RGB")
