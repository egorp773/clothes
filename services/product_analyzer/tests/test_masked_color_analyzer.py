from __future__ import annotations

import numpy as np
import pytest

from app.color.masked_color_analyzer import MaskedColorAnalyzer


@pytest.mark.parametrize(
    ("rgb", "expected"),
    [
        ((15, 16, 18), "black"),
        ((21, 38, 74), "dark_blue"),
        ((248, 248, 245), "white"),
        # White fabric photographed away from the key light is commonly in
        # the low 210s even though it remains neutral and visually white.
        ((218, 220, 216), "white"),
        ((190, 192, 195), "gray"),
        ((203, 205, 208), "gray"),
        ((125, 126, 130), "gray"),
    ],
)
def test_neutral_and_dark_colors(garment_image_factory, rgb, expected):
    image, mask = garment_image_factory(rgb, background_rgb=(230, 80, 40))
    result = MaskedColorAnalyzer().analyze(image, mask)
    assert result[0].color_id == expected


def test_small_contrast_logo_does_not_replace_primary(garment_image_factory):
    image, mask = garment_image_factory((25, 42, 78), logo_rgb=(245, 245, 245))
    result = MaskedColorAnalyzer().analyze(image, mask)
    assert result[0].color_id == "dark_blue"


def test_two_color_garment_reports_secondary(garment_image_factory):
    image, mask = garment_image_factory((20, 20, 20))
    image[120:215, 35:145] = (235, 235, 232)
    result = MaskedColorAnalyzer().analyze(image, mask)
    ids = [item.color_id for item in result]
    assert "black" in ids
    assert "white" in ids or "gray" in ids


def test_shadowed_white_garment_stays_white(garment_image_factory):
    image, mask = garment_image_factory(
        (218, 220, 216),
        background_rgb=(54, 82, 108),
    )
    image[35:100, 35:145] = (188, 190, 187)
    image[180:215, 35:145] = (239, 240, 236)

    result = MaskedColorAnalyzer().analyze(image, mask)

    assert result[0].color_id == "white"
    assert result[0].confidence >= 0.75
    assert result[0].color_id != "multicolor"


def test_white_background_leak_does_not_replace_real_gray():
    image = np.full((240, 180, 3), (246, 246, 244), dtype=np.uint8)
    mask = np.zeros((240, 180), dtype=bool)
    # Simulate a slightly oversized segmentation mask around the garment.
    mask[30:220, 30:150] = True
    image[45:205, 45:135] = (188, 190, 193)

    result = MaskedColorAnalyzer().analyze(image, mask)

    assert result[0].color_id == "gray"


def test_shades_and_neutral_highlights_are_not_multicolor(garment_image_factory):
    image, mask = garment_image_factory((23, 42, 77))
    image[95:150, 35:145] = (53, 103, 183)
    image[150:215, 35:145] = (139, 196, 232)
    result = MaskedColorAnalyzer().analyze(image, mask)
    assert result[0].color_id != "multicolor"


def test_three_distinct_color_families_are_multicolor(garment_image_factory):
    image, mask = garment_image_factory((214, 69, 69))
    image[95:155, 35:145] = (58, 140, 91)
    image[155:215, 35:145] = (53, 103, 183)
    result = MaskedColorAnalyzer().analyze(image, mask)
    assert result[0].color_id == "multicolor"
    assert len(result[1:]) >= 3
