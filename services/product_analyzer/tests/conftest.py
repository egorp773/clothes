from __future__ import annotations

import numpy as np
import pytest


@pytest.fixture
def garment_image_factory():
    def create(
        garment_rgb: tuple[int, int, int],
        background_rgb: tuple[int, int, int] = (245, 245, 245),
        logo_rgb: tuple[int, int, int] | None = None,
    ) -> tuple[np.ndarray, np.ndarray]:
        image = np.full((240, 180, 3), background_rgb, dtype=np.uint8)
        mask = np.zeros((240, 180), dtype=bool)
        mask[35:215, 35:145] = True
        image[mask] = garment_rgb
        if logo_rgb is not None:
            image[90:108, 80:100] = logo_rgb
        return image, mask

    return create
