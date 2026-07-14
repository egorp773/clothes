from __future__ import annotations

from concurrent.futures import Future
from types import SimpleNamespace

import numpy as np
from PIL import Image

from app.catalog import CATEGORIES
from app.classification.fashion_siglip_adapter import FashionCandidate
from app.config import Settings
from app.pipeline.analyzer_pipeline import AnalyzerPipeline
from app.segmentation.grounded_sam_adapter import SegmentedGarment


def _candidate(item_type: str, confidence: float) -> FashionCandidate:
    definition = next(item for item in CATEGORIES if item.item_type == item_type)
    return FashionCandidate(definition=definition, confidence=confidence)


class _FastSegmentation:
    def __init__(self, segments: list[SegmentedGarment]) -> None:
        self.segments = segments

    def segment_many(self, image):
        return self.segments

    @staticmethod
    def is_acceptable(segment):
        return segment is not None


class _FallbackSegmentation:
    def __init__(self) -> None:
        self.calls = 0

    def segment_many(self, image):
        self.calls += 1
        return []


class _Classification:
    def __init__(self) -> None:
        self.batch_calls = 0
        self.single_calls = 0
        self.attribute_calls = 0

    def embed_and_classify_many(self, images):
        self.batch_calls += 1
        assert len(images) == 2
        return [
            SimpleNamespace(
                embedding=np.array([1.0, 0.0], dtype=np.float32),
                candidates=[
                    _candidate("jeans", 0.82),
                    _candidate("trousers", 0.11),
                ],
            ),
            SimpleNamespace(
                embedding=np.array([0.0, 1.0], dtype=np.float32),
                candidates=[
                    _candidate("shirt", 0.78),
                    _candidate("tshirt", 0.12),
                ],
            ),
        ]

    def embed_and_classify(self, image):
        self.single_calls += 1
        return SimpleNamespace(
            embedding=np.array([1.0, 0.0], dtype=np.float32),
            candidates=[_candidate("jeans", 0.82)],
        )

    def score_text_options(self, embedding, options, *, temperature=12.0):
        self.attribute_calls += 1
        return {
            key: 0.72 if index == 0 else 0.04
            for index, key in enumerate(options)
        }


class _Models:
    def __init__(self, segments):
        self.fast_segmentation = _FastSegmentation(segments)
        self.segmentation = _FallbackSegmentation()
        self.classification = _Classification()
        self.ocr = SimpleNamespace(available=False)
        self.vlm = SimpleNamespace(available=False)

    @staticmethod
    def submit(operation, /, *args, **kwargs):
        future = Future()
        try:
            future.set_result(operation(*args, **kwargs))
        except Exception as error:
            future.set_exception(error)
        return future

    @staticmethod
    def submit_background(operation, /, *args, **kwargs):
        return _Models.submit(operation, *args, **kwargs)

    @staticmethod
    def await_result(future, timeout_seconds, stage):
        return future.result(timeout=timeout_seconds)


def test_multi_item_pipeline_batches_classification_and_skips_sam():
    first_mask = np.zeros((100, 100), dtype=bool)
    first_mask[10:90, 5:45] = True
    second_mask = np.zeros((100, 100), dtype=bool)
    second_mask[20:85, 60:95] = True
    image = Image.new("RGB", (100, 100), (30, 60, 100))
    segments = [
        SegmentedGarment(
            mask=first_mask,
            cutout=image.crop((5, 10, 45, 90)).convert("RGBA"),
            bbox=(5, 10, 45, 90),
            label="foreground",
            confidence=0.9,
        ),
        SegmentedGarment(
            mask=second_mask,
            cutout=image.crop((60, 20, 95, 85)).convert("RGBA"),
            bbox=(60, 20, 95, 85),
            label="foreground",
            confidence=0.88,
        ),
    ]
    models = _Models(segments)
    pipeline = AnalyzerPipeline(
        Settings(enable_paddleocr=False, enable_qwen=False),
        models,
    )

    result = pipeline.analyze(image, "multi-image")

    assert result.item_type.value == "jeans"
    assert [item.item_type for item in result.category_top_k[:2]] == [
        "jeans",
        "shirt",
    ]
    assert "multiple_items_detected:2" in result.warnings
    assert models.classification.batch_calls == 1
    assert models.classification.single_calls == 0
    assert models.classification.attribute_calls == 4
    assert models.segmentation.calls == 0
    assert result.material.value == "cotton"
    assert result.material.source == "fashion_siglip_visual_attributes_v1"
    assert result.enrichment_status == "completed"
