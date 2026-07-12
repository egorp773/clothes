from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np
from app.catalog import COLORS


COLOR_FAMILIES = {
    "black": "neutral",
    "white": "neutral",
    "gray": "neutral",
    "beige": "earth",
    "cream": "earth",
    "brown": "earth",
    "blue": "blue",
    "dark_blue": "blue",
    "light_blue": "blue",
    "green": "green",
    "olive": "green",
    "red": "red",
    "burgundy": "red",
    "pink": "red",
    "purple": "purple",
    "yellow": "yellow_orange",
    "orange": "yellow_orange",
}


@dataclass(frozen=True)
class ColorCandidate:
    color_id: str
    share: float
    confidence: float


class MaskedColorAnalyzer:
    source = "opencv_masked_lab_hsv_v1"

    def __init__(self, clusters: int = 6, min_secondary_share: float = 0.12) -> None:
        self.clusters = clusters
        self.min_secondary_share = min_secondary_share
        palette_rgb = np.array(list(COLORS.values()), dtype=np.uint8).reshape(-1, 1, 3)
        self._palette_ids = list(COLORS)
        self._palette_lab = cv2.cvtColor(palette_rgb, cv2.COLOR_RGB2LAB).reshape(-1, 3).astype(np.float32)

    def analyze(self, image_rgb: np.ndarray, mask: np.ndarray) -> list[ColorCandidate]:
        if image_rgb.shape[:2] != mask.shape[:2]:
            raise ValueError("Mask and image dimensions differ")
        mask = mask.astype(bool)
        if int(mask.sum()) < 64:
            return []

        hsv = cv2.cvtColor(image_rgb, cv2.COLOR_RGB2HSV)
        lab = cv2.cvtColor(image_rgb, cv2.COLOR_RGB2LAB)
        values = hsv[..., 2][mask]
        saturation = hsv[..., 1][mask]
        low, high = np.percentile(values, [8, 96])
        valid = mask.copy()
        valid[mask] = (values >= max(18, low)) & (values <= min(248, high))
        # Keep genuinely black/white fabric while dropping only extreme shadows/highlights.
        if int(valid.sum()) < max(64, int(mask.sum() * 0.45)):
            valid = mask

        pixels_lab = lab[valid].astype(np.float32)
        pixels_hsv = hsv[valid].astype(np.float32)
        if len(pixels_lab) > 12000:
            indices = np.linspace(0, len(pixels_lab) - 1, 12000, dtype=np.int64)
            pixels_lab = pixels_lab[indices]
            pixels_hsv = pixels_hsv[indices]
        unique_count = len(np.unique(pixels_lab.astype(np.uint8), axis=0))
        cluster_count = max(1, min(self.clusters, unique_count, len(pixels_lab) // 20))
        if cluster_count == 1:
            centers = np.mean(pixels_lab, axis=0, keepdims=True)
            labels = np.zeros(len(pixels_lab), dtype=np.int32)
        else:
            cv2.setRNGSeed(17)
            _, labels, centers = cv2.kmeans(
                pixels_lab,
                cluster_count,
                None,
                (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 0.5),
                2,
                cv2.KMEANS_PP_CENTERS,
            )
            labels = labels.reshape(-1)

        counts = np.bincount(labels, minlength=len(centers)).astype(np.float64)
        mapped: dict[str, float] = {}
        for index, center in enumerate(centers):
            cluster_hsv = pixels_hsv[labels == index]
            color_id = self._map_cluster(center, cluster_hsv)
            mapped[color_id] = mapped.get(color_id, 0.0) + counts[index]
        total = sum(mapped.values())
        ranked = sorted(mapped.items(), key=lambda item: item[1], reverse=True)
        merged = [
            ColorCandidate(
                color_id=color_id,
                share=count / total,
                confidence=min(0.97, 0.58 + (count / total) * 0.40),
            )
            for color_id, count in ranked
            if count / total >= (0.04 if not ranked or color_id == ranked[0][0] else self.min_secondary_share)
        ]
        prominent = [item for item in merged if item.share >= 0.12]
        families = {COLOR_FAMILIES.get(item.color_id, item.color_id) for item in prominent}
        # Shadows and highlights often map one fabric to black/gray/white or
        # several blue/red shades. Treat those as one family. "Multicolor" is
        # reserved for at least three genuinely distinct, visible families.
        if (
            len(prominent) >= 3
            and len(families) >= 3
            and prominent[0].share < 0.70
            and prominent[2].share >= 0.12
        ):
            merged.insert(
                0,
                ColorCandidate(
                    "multicolor",
                    sum(item.share for item in prominent[:4]),
                    0.84,
                ),
            )
        return merged[:5]

    def _map_cluster(self, center_lab: np.ndarray, cluster_hsv: np.ndarray) -> str:
        median_h, median_s, median_v = np.median(cluster_hsv, axis=0)
        if median_v <= 42 and median_s <= 75:
            return "black"
        if median_s <= 24:
            if median_v >= 232:
                return "white"
            if median_v <= 55:
                return "black"
            return "gray"
        distances = np.linalg.norm(self._palette_lab - center_lab[None, :], axis=1)
        return self._palette_ids[int(np.argmin(distances))]
