from __future__ import annotations

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

