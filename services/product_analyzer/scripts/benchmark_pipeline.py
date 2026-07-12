"""Run reproducible, real-image latency measurements for the analyzer.

Usage from this directory:
  .venv\\Scripts\\python scripts\\benchmark_pipeline.py ../../outfit.jpeg ../../assets/products/graphic_hoodie.jpg
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
from pathlib import Path

import psutil
import torch
from PIL import Image

SERVICE_ROOT = Path(__file__).resolve().parents[1]
if str(SERVICE_ROOT) not in sys.path:
    sys.path.insert(0, str(SERVICE_ROOT))

from app.config import get_settings
from app.model_manager import ModelManager
from app.pipeline.analyzer_pipeline import AnalyzerPipeline


def wait_for_enrichment(pipeline: AnalyzerPipeline, image_hash: str, timeout: float = 90) -> tuple[str, int]:
    started = time.perf_counter()
    while time.perf_counter() - started < timeout:
        result = pipeline.get_cached(image_hash)
        if result and result.enrichment_status in {"completed", "failed"}:
            return result.enrichment_status, round((time.perf_counter() - started) * 1000)
        time.sleep(0.1)
    return "timeout", round((time.perf_counter() - started) * 1000)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("images", nargs="+", type=Path)
    args = parser.parse_args()
    settings = get_settings()
    process = psutil.Process()
    models = ModelManager(settings)
    pipeline = AnalyzerPipeline(settings, models)

    startup = time.perf_counter()
    models.load_enabled()
    models.warmup()
    startup_ms = round((time.perf_counter() - startup) * 1000)
    rows: list[dict[str, object]] = []
    for path in args.images:
        payload = path.read_bytes()
        decode_started = time.perf_counter()
        image = Image.open(path).convert("RGB")
        image.load()
        decode_ms = round((time.perf_counter() - decode_started) * 1000)
        image_hash = hashlib.sha256(payload).hexdigest()
        request_started = time.perf_counter()
        result = pipeline.analyze(image, image_hash, download_ms=0, decode_ms=decode_ms)
        basic_ms = round((time.perf_counter() - request_started) * 1000)
        status, enrichment_ms = wait_for_enrichment(pipeline, image_hash)
        final = pipeline.get_cached(image_hash)
        rows.append(
            {
                "image": str(path),
                "basic_response_ms": basic_ms,
                "enrichment_status": status,
                "enrichment_after_basic_ms": enrichment_ms,
                "timings_ms": final.timings_ms if final else result.timings_ms,
            }
        )
    print(json.dumps({
        "startup_and_warmup_ms": startup_ms,
        "ram_rss_mb": round(process.memory_info().rss / 1024 / 1024, 1),
        "vram_allocated_mb": round(torch.cuda.memory_allocated() / 1024 / 1024, 1) if torch.cuda.is_available() else 0,
        "cuda_available": torch.cuda.is_available(),
        "components": models.health(),
        "runs": rows,
    }, ensure_ascii=False, indent=2))
    models.close()


if __name__ == "__main__":
    main()
