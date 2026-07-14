from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np
from PIL import Image


@dataclass(frozen=True)
class PhotoQuality:
    score: float
    sharpness: float
    exposure: float
    contrast: float
    resolution: float
    warnings: tuple[str, ...]


class PhotoQualityAnalyzer:
    """Cheap deterministic photo checks suitable for a 2 CPU worker."""

    version = "opencv_photo_quality_v1"

    def analyze(self, image: Image.Image) -> PhotoQuality:
        rgb = np.asarray(image.convert("RGB"))
        gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
        hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV)
        laplacian_variance = float(cv2.Laplacian(gray, cv2.CV_64F).var())
        sharpness = min(1.0, laplacian_variance / 420.0)
        values = hsv[..., 2]
        exposure = float(((values >= 30) & (values <= 242)).mean())
        contrast = min(1.0, float(gray.std()) / 62.0)
        resolution = min(1.0, min(image.size) / 900.0)
        score = (
            0.34 * sharpness
            + 0.28 * exposure
            + 0.18 * contrast
            + 0.20 * resolution
        )
        warnings: list[str] = []
        if sharpness < 0.25:
            warnings.append("blurry")
        if exposure < 0.72:
            warnings.append("poor_exposure")
        if contrast < 0.24:
            warnings.append("low_contrast")
        if resolution < 0.55:
            warnings.append("low_resolution")
        return PhotoQuality(
            score=round(max(0.0, min(1.0, score)), 4),
            sharpness=round(sharpness, 4),
            exposure=round(exposure, 4),
            contrast=round(contrast, 4),
            resolution=round(resolution, 4),
            warnings=tuple(warnings),
        )
