from __future__ import annotations

import logging

from app.config import get_settings
from app.model_manager import ModelManager
from rembg.sessions import sessions


logging.basicConfig(level=logging.INFO)
settings = get_settings()
models = ModelManager(settings)
try:
    # Bake both artifacts into the read-only runtime image. Feature flags
    # control RAM loading/inference, while a larger deployment can still opt
    # into the clothing parser through its runtime environment.
    for model_name in (
        settings.clothing_region_model_name,
        settings.background_removal_model_name,
    ):
        session = sessions.get(model_name)
        if session is None:
            raise RuntimeError(f"Unknown rembg model: {model_name}")
        session.download_models()
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
