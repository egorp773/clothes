from __future__ import annotations

import logging

from app.config import get_settings
from app.model_manager import ModelManager


logging.basicConfig(level=logging.INFO)
settings = get_settings()
models = ModelManager(settings)
try:
    models.load_enabled()
    health = models.health()
    missing = [
        name
        for name in ("fast_segmentation", "classification")
        if not health[name]["loaded"]
    ]
    if missing:
        raise RuntimeError(f"Required models did not preload: {', '.join(missing)}")
finally:
    models.close()
