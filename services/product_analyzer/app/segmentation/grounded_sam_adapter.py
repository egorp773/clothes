from __future__ import annotations

import logging
import sys
import threading
from dataclasses import dataclass
import numpy as np
from PIL import Image

from app.config import Settings


LOGGER = logging.getLogger(__name__)


@dataclass(frozen=True)
class SegmentedGarment:
    mask: np.ndarray
    cutout: Image.Image
    bbox: tuple[int, int, int, int]
    label: str
    confidence: float


class GroundedSamAdapter:
    """UI-free adaptation of the official grounded_sam2_local_demo.py."""

    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._lock = threading.Lock()
        self._loaded = False
        self._load_error: str | None = None
        self._device = "cpu"
        self._sam_predictor = None
        self._grounding_model = None
        self._predict = None
        self._box_convert = None
        self._nms = None

    @property
    def model_name(self) -> str:
        return "Grounding DINO SwinT + SAM 2.1 Hiera Large"

    @property
    def available(self) -> bool:
        return (
            self.settings.enable_grounded_sam
            and self.settings.grounded_sam_repo.exists()
            and self.settings.sam_checkpoint.exists()
            and self.settings.grounding_dino_checkpoint.exists()
        )

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
                self._load_error = (
                    "Grounded-SAM-2 repository/checkpoints are missing; run "
                    "python scripts/setup_models.py"
                )
                raise RuntimeError(self._load_error)
            repo = str(self.settings.grounded_sam_repo.resolve())
            if repo not in sys.path:
                sys.path.insert(0, repo)
            try:
                import torch
                from grounding_dino.groundingdino.util.inference import (
                    load_model,
                    predict,
                )
                from sam2.build_sam import build_sam2
                from sam2.sam2_image_predictor import SAM2ImagePredictor
                from torchvision.ops import box_convert, nms

                self._device = "cuda" if torch.cuda.is_available() else "cpu"
                sam = build_sam2(
                    self.settings.sam_config,
                    str(self.settings.sam_checkpoint),
                    device=self._device,
                )
                self._sam_predictor = SAM2ImagePredictor(sam)
                self._grounding_model = load_model(
                    model_config_path=str(
                        self.settings.grounded_sam_repo
                        / self.settings.grounding_dino_config
                    ),
                    model_checkpoint_path=str(
                        self.settings.grounding_dino_checkpoint
                    ),
                    device=self._device,
                )
                self._predict = predict
                self._box_convert = box_convert
                self._nms = nms
                self._loaded = True
                self._load_error = None
                LOGGER.info("Loaded %s on %s", self.model_name, self._device)
            except Exception as error:
                self._load_error = f"{type(error).__name__}: {error}"
                LOGGER.exception("Unable to load Grounded-SAM-2")
                raise

    def segment(self, image: Image.Image) -> SegmentedGarment | None:
        segments = self.segment_many(image, max_items=1)
        return segments[0] if segments else None

    def segment_many(
        self,
        image: Image.Image,
        *,
        max_items: int | None = None,
    ) -> list[SegmentedGarment]:
        self.load()
        with self._lock:
            return self._segment_many_locked(
                image.convert("RGB"),
                max_items=max_items or self.settings.max_detected_garments,
            )

    def _segment_many_locked(
        self,
        image: Image.Image,
        *,
        max_items: int,
    ) -> list[SegmentedGarment]:
        from grounding_dino.groundingdino.datasets import transforms as transforms

        rgb = np.asarray(image)
        transform = transforms.Compose(
            [
                transforms.RandomResize([800], max_size=1333),
                transforms.ToTensor(),
                transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
            ]
        )
        tensor, _ = transform(image, None)
        boxes, confidences, labels = self._predict(
            model=self._grounding_model,
            image=tensor,
            caption=self.settings.grounded_sam_prompt.lower().strip() + " ",
            box_threshold=self.settings.grounding_dino_box_threshold,
            text_threshold=self.settings.grounding_dino_text_threshold,
            device=self._device,
        )
        if len(boxes) == 0:
            return []

        height, width = rgb.shape[:2]
        boxes = boxes * boxes.new_tensor([width, height, width, height])
        xyxy = self._box_convert(boxes=boxes, in_fmt="cxcywh", out_fmt="xyxy")
        # The broad clothing prompt intentionally produces synonymous boxes
        # ("clothing", "shirt", "top") for the same item.  Feeding every box
        # to SAM is both slow and likely to duplicate one garment, so suppress
        # overlaps and cap the expensive mask batch first.
        keep = self._nms(
            xyxy,
            confidences,
            self.settings.grounding_dino_nms_threshold,
        )[: max(1, self.settings.grounded_sam_max_boxes)]
        xyxy = xyxy[keep]
        confidences = confidences[keep]
        kept_indices = [int(index) for index in keep.detach().cpu()]
        labels = [labels[index] for index in kept_indices]
        input_boxes = xyxy.detach().cpu().numpy()
        self._sam_predictor.set_image(rgb)
        masks, sam_scores, _ = self._sam_predictor.predict(
            point_coords=None,
            point_labels=None,
            box=input_boxes,
            multimask_output=False,
        )
        if masks.ndim == 4:
            masks = masks.squeeze(1)
        dino_scores = confidences.detach().cpu().numpy()
        sam_scores = np.asarray(sam_scores).reshape(-1)

        ranked: list[tuple[float, int, np.ndarray]] = []
        frame_area = float(width * height)
        for index, (box, mask) in enumerate(zip(input_boxes, masks)):
            x1, y1, x2, y2 = box
            boolean_mask = mask.astype(bool)
            area_share = float(boolean_mask.sum()) / frame_area
            if not boolean_mask.any():
                continue
            center_x = (x1 + x2) / (2 * width)
            center_y = (y1 + y2) / (2 * height)
            centrality = max(0.0, 1.0 - ((center_x - 0.5) ** 2 + (center_y - 0.5) ** 2))
            area_quality = 1.0 if 0.04 <= area_share <= 0.82 else 0.45
            score = (
                float(dino_scores[index]) * 0.55
                + float(sam_scores[index]) * 0.25
                + centrality * 0.12
                + area_quality * 0.08
            )
            ranked.append((score, index, boolean_mask))
        ranked.sort(key=lambda item: item[0], reverse=True)

        segments: list[SegmentedGarment] = []
        accepted_masks: list[np.ndarray] = []
        for score, index, mask in ranked:
            # Box NMS happens before SAM; this mask-level guard handles nested
            # detector boxes that still resolve to effectively the same shape.
            if any(self._mask_iou(mask, accepted) >= 0.72 for accepted in accepted_masks):
                continue
            ys, xs = np.where(mask)
            bbox = (
                int(xs.min()),
                int(ys.min()),
                int(xs.max()) + 1,
                int(ys.max()) + 1,
            )
            rgba = np.dstack([rgb, (mask.astype(np.uint8) * 255)])
            cutout = Image.fromarray(rgba, mode="RGBA").crop(bbox)
            segments.append(
                SegmentedGarment(
                    mask=mask,
                    cutout=cutout,
                    bbox=bbox,
                    label=str(labels[index]),
                    confidence=min(1.0, max(0.0, score)),
                )
            )
            accepted_masks.append(mask)
            if len(segments) >= max(1, max_items):
                break
        return segments

    @staticmethod
    def _mask_iou(first: np.ndarray, second: np.ndarray) -> float:
        intersection = int(np.logical_and(first, second).sum())
        if not intersection:
            return 0.0
        union = int(np.logical_or(first, second).sum())
        return intersection / max(union, 1)
