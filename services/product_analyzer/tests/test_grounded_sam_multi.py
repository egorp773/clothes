from __future__ import annotations

import sys
from types import ModuleType

import numpy as np
import torch
from PIL import Image

from app.config import Settings
from app.segmentation.grounded_sam_adapter import GroundedSamAdapter


class _Predictor:
    def __init__(self) -> None:
        self.box_count = 0

    def set_image(self, image) -> None:
        assert image.shape == (100, 100, 3)

    def predict(self, *, point_coords, point_labels, box, multimask_output):
        assert point_coords is None
        assert point_labels is None
        assert multimask_output is False
        self.box_count = len(box)
        masks = np.zeros((len(box), 1, 100, 100), dtype=np.uint8)
        masks[0, 0, 8:42, 8:42] = 1
        masks[1, 0, 58:92, 58:92] = 1
        return masks, np.asarray([0.92, 0.88]), None


def test_grounded_sam_caps_detector_boxes_and_returns_distinct_masks(monkeypatch):
    transforms = ModuleType("grounding_dino.groundingdino.datasets.transforms")
    transforms.RandomResize = lambda *args, **kwargs: object()
    transforms.ToTensor = lambda *args, **kwargs: object()
    transforms.Normalize = lambda *args, **kwargs: object()
    transforms.Compose = lambda operations: (
        lambda image, target: (torch.zeros((3, 8, 8)), target)
    )
    datasets = ModuleType("grounding_dino.groundingdino.datasets")
    datasets.transforms = transforms
    monkeypatch.setitem(sys.modules, "grounding_dino", ModuleType("grounding_dino"))
    monkeypatch.setitem(
        sys.modules,
        "grounding_dino.groundingdino",
        ModuleType("grounding_dino.groundingdino"),
    )
    monkeypatch.setitem(sys.modules, datasets.__name__, datasets)
    monkeypatch.setitem(sys.modules, transforms.__name__, transforms)

    adapter = GroundedSamAdapter(Settings(grounded_sam_max_boxes=2))
    adapter._device = "cpu"
    adapter._predict = lambda **kwargs: (
        torch.tensor(
            [
                [0.05, 0.05, 0.45, 0.45],
                [0.55, 0.55, 0.95, 0.95],
                [0.04, 0.04, 0.46, 0.46],
            ]
        ),
        torch.tensor([0.91, 0.87, 0.80]),
        ["shirt", "trousers", "clothing"],
    )
    adapter._box_convert = lambda *, boxes, in_fmt, out_fmt: boxes
    adapter._nms = lambda boxes, scores, threshold: torch.tensor([0, 1, 2])
    adapter._sam_predictor = _Predictor()

    segments = adapter._segment_many_locked(
        Image.new("RGB", (100, 100), "white"),
        max_items=2,
    )

    assert adapter._sam_predictor.box_count == 2
    assert [segment.label for segment in segments] == ["shirt", "trousers"]
    assert [segment.bbox for segment in segments] == [
        (8, 8, 42, 42),
        (58, 58, 92, 92),
    ]
