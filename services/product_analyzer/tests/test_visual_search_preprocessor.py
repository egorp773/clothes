from __future__ import annotations

from types import SimpleNamespace

from PIL import Image

from app.config import Settings
from app.visual_search.preprocessor import VisualSearchPreprocessor


class _SegmentationMustNotRun:
    def segment(self, image):
        raise AssertionError("query preparation must not run foreground removal")


def test_query_preparation_keeps_selected_crop_and_skips_segmentation():
    preprocessor = VisualSearchPreprocessor(
        Settings(visual_search_max_side=320),
        _SegmentationMustNotRun(),  # type: ignore[arg-type]
    )
    source = Image.new("RGB", (640, 480), (12, 34, 56))

    prepared = preprocessor.prepare_query(source)

    assert prepared.image.size == (320, 240)
    assert prepared.image.getpixel((100, 100)) == (12, 34, 56)
    assert prepared.timings_ms["segmentation"] == 0
    assert prepared.warning is None


class _Foreground:
    def segment(self, image):
        rgba = Image.new("RGBA", image.size, (0, 0, 0, 0))
        rgba.putpixel((10, 10), (200, 20, 30, 255))
        return SimpleNamespace(cutout=rgba, label="foreground")


def test_query_variants_keep_context_and_white_composite_foreground():
    preprocessor = VisualSearchPreprocessor(Settings(), _Foreground())  # type: ignore[arg-type]

    prepared = preprocessor.prepare_query_variants(
        Image.new("RGB", (40, 30), (12, 34, 56))
    )

    assert prepared.context.getpixel((0, 0)) == (12, 34, 56)
    assert prepared.foreground is not None
    assert prepared.foreground.getpixel((0, 0)) == (255, 255, 255)
    assert prepared.foreground.getpixel((10, 10)) == (200, 20, 30)
    assert prepared.warnings == []
