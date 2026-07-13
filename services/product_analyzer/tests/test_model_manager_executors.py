from __future__ import annotations

import threading

from app.config import Settings
from app.model_manager import ModelManager


def test_background_coordinators_do_not_occupy_inference_workers():
    manager = ModelManager(Settings(background_workers=1))
    release = threading.Event()
    started = threading.Event()

    def block():
        started.set()
        return release.wait(timeout=2)

    background = [manager.submit_background(block) for _ in range(3)]
    try:
        assert started.wait(timeout=1)
        assert manager.submit(lambda: "fast").result(timeout=0.5) == "fast"
    finally:
        release.set()
        for future in background:
            future.result(timeout=1)
        manager.close()
