from __future__ import annotations

import sys
from types import SimpleNamespace

import numpy as np
from PIL import Image

from app.config import Settings
from app.segmentation.rembg_adapter import RembgAdapter


def test_region_proposals_keep_separate_significant_foregrounds(monkeypatch):
    rgba = np.zeros((100, 100, 4), dtype=np.uint8)
    rgba[:, :, :3] = 120
    rgba[12:48, 8:38, 3] = 255
    rgba[54:94, 58:92, 3] = 255

    adapter = RembgAdapter(Settings())
    adapter._loaded = True
    adapter._session = object()
    monkeypatch.setitem(
        sys.modules,
        "rembg",
        SimpleNamespace(remove=lambda image, session: Image.fromarray(rgba, "RGBA")),
    )

    proposals = adapter.propose_regions(Image.new("RGB", (100, 100), "white"))

    assert len(proposals) == 2
    assert all(proposal.confidence >= 0.62 for proposal in proposals)
    assert proposals[0].bbox != proposals[1].bbox


def test_clothing_regions_split_upper_and_lower_garments():
    upper = np.zeros((100, 80), dtype=np.uint8)
    lower = np.zeros((100, 80), dtype=np.uint8)
    full = np.zeros((100, 80), dtype=np.uint8)
    upper[12:48, 18:63] = 255
    lower[50:94, 23:58] = 255

    adapter = RembgAdapter(Settings(), model_name="u2net_cloth_seg")
    adapter._loaded = True
    adapter._session = SimpleNamespace(
        predict=lambda _: [
            Image.fromarray(upper, "L"),
            Image.fromarray(lower, "L"),
            Image.fromarray(full, "L"),
        ]
    )

    proposals = adapter.propose_clothing_regions(Image.new("RGB", (80, 100), "white"))

    assert [proposal.label for proposal in proposals] == [
        "upper_clothing",
        "lower_clothing",
    ]


def test_clothing_regions_keep_same_class_components_separate():
    upper = np.zeros((100, 100), dtype=np.uint8)
    upper[10:48, 8:42] = 255
    upper[52:92, 58:94] = 255
    empty = np.zeros_like(upper)

    adapter = RembgAdapter(Settings(), model_name="u2net_cloth_seg")
    adapter._loaded = True
    adapter._session = SimpleNamespace(
        predict=lambda _: [
            Image.fromarray(upper, "L"),
            Image.fromarray(empty, "L"),
            Image.fromarray(empty, "L"),
        ]
    )

    proposals = adapter.propose_clothing_regions(Image.new("RGB", (100, 100), "white"))

    assert len(proposals) == 2
    assert all(proposal.label == "upper_clothing" for proposal in proposals)
    assert proposals[0].bbox != proposals[1].bbox
