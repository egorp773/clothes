from __future__ import annotations

from app.config import Settings
from app.model_manager import ModelManager


class _Unavailable:
    available = False


class _RegionModel:
    available = True
    model_name = "test/regions"

    def __init__(self):
        self.load_calls = 0
        self.warmup_calls = 0

    def load(self):
        self.load_calls += 1

    def propose_clothing_regions(self, image):
        self.warmup_calls += 1
        return []


def test_region_model_is_loaded_and_warmed_before_first_user_request():
    manager = ModelManager(
        Settings(
            visual_search_enable_clothing_parser=True,
            visual_search_preload_region_model=True,
        )
    )
    region_model = _RegionModel()
    manager.fast_segmentation = _Unavailable()  # type: ignore[assignment]
    manager.classification = _Unavailable()  # type: ignore[assignment]
    manager.clothing_regions = region_model  # type: ignore[assignment]
    try:
        manager.load_enabled()
        manager.warmup()
    finally:
        manager.close()

    assert region_model.load_calls == 1
    assert region_model.warmup_calls == 1


def test_region_model_stays_cold_unless_enable_and_preload_are_both_set():
    for enable, preload in ((False, False), (False, True), (True, False)):
        manager = ModelManager(
            Settings(
                visual_search_enable_clothing_parser=enable,
                visual_search_preload_region_model=preload,
            )
        )
        region_model = _RegionModel()
        manager.fast_segmentation = _Unavailable()  # type: ignore[assignment]
        manager.classification = _Unavailable()  # type: ignore[assignment]
        manager.clothing_regions = region_model  # type: ignore[assignment]
        try:
            manager.load_enabled()
            manager.warmup()
        finally:
            manager.close()

        assert region_model.load_calls == 0
        assert region_model.warmup_calls == 0
