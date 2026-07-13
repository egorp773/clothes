from __future__ import annotations

import numpy as np
import torch
from PIL import Image

from app.catalog import CATEGORIES
from app.classification.fashion_siglip_adapter import FashionSiglipAdapter
from app.config import Settings


class _Processor:
    def __init__(self) -> None:
        self.image_calls = 0

    def __call__(self, *, images, return_tensors):
        assert return_tensors == "pt"
        self.image_calls += 1
        features = []
        for image in images:
            red, green, _ = np.asarray(image)[0, 0]
            features.append([float(red > green), float(green > red)])
        return {"pixel_values": torch.tensor(features, dtype=torch.float32)}


class _Model:
    def __init__(self) -> None:
        self.image_calls = 0

    def get_image_features(self, pixel_values, *, normalize):
        assert normalize is True
        self.image_calls += 1
        return pixel_values


def test_classify_many_uses_one_image_tower_batch():
    adapter = FashionSiglipAdapter(Settings(classification_top_k=1))
    adapter._loaded = True
    adapter._processor = _Processor()
    adapter._model = _Model()
    adapter._prompt_slices = [
        (index, index + 1) for index in range(len(CATEGORIES))
    ]
    prompt_embeddings = torch.full((len(CATEGORIES), 2), -1.0)
    prompt_embeddings[0] = torch.tensor([1.0, 0.0])
    prompt_embeddings[1] = torch.tensor([0.0, 1.0])
    adapter._prompt_embeddings = prompt_embeddings

    batches = adapter.classify_many(
        [
            Image.new("RGB", (16, 16), (255, 0, 0)),
            Image.new("RGB", (16, 16), (0, 255, 0)),
        ]
    )

    assert [batch[0].definition for batch in batches] == [CATEGORIES[0], CATEGORIES[1]]
    assert adapter._processor.image_calls == 1
    assert adapter._model.image_calls == 1
