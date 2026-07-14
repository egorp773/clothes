from __future__ import annotations

import asyncio
from types import SimpleNamespace

import numpy as np
from PIL import Image

from app.color.masked_color_analyzer import ColorCandidate
from app.config import Settings
from app.enrichment.quality import PhotoQuality
from app.enrichment.service import ProductEnrichmentService, _ImageWork
from app.enrichment.store import EnrichmentJob
from app.enrichment.worker import ProductEnrichmentWorker


class _Classifier:
    embedding_dimension = 3

    def embed_and_classify_many(self, images, top_k=1):
        return [
            SimpleNamespace(
                embedding=np.asarray([1.0, index / 10, 0.0], dtype=np.float32),
                candidates=[],
            )
            for index, _ in enumerate(images)
        ]

    def score_text_options(self, embedding, options, temperature=12.0):
        first = next(iter(options))
        return {key: 0.8 if key == first else 0.02 for key in options}


class _Store:
    def __init__(self):
        self.image_updates = []
        self.visual_rows = []
        self.attributes = []
        self.product_update = None
        self.similarities = None

    def get_product(self, product_id):
        return {
            "id": product_id,
            "title": "White shirt",
            "description": "Cotton",
            "brand": "No brand",
            "normalized_category": "t_shirt",
        }

    def get_product_images(self, product_id, product):
        return [{"id": "image-1", "original_url": "https://img/1.jpg", "role": "main"}]

    def upload_cutout(self, product_id, image_id, payload):
        return "https://img/1-cutout.png"

    def update_product_image(self, image_id, payload):
        self.image_updates.append((image_id, payload))

    @staticmethod
    def vector_literal(value):
        return "[" + ",".join(str(float(item)) for item in value) + "]"

    def upsert_visual_embeddings(self, rows):
        self.visual_rows.extend(rows)

    def merge_attribute(self, *args, **kwargs):
        self.attributes.append((args, kwargs))

    def find_similar(self, product_id, embeddings, model_version):
        return [
            {
                "product_id": product_id,
                "similar_product_id": "product-2",
                "score": 0.8,
                "visual_score": 0.8,
                "attribute_score": 0.0,
                "model_version": model_version,
            }
        ]

    def replace_similarities(self, product_id, rows):
        self.similarities = rows

    def update_product(self, product_id, payload):
        self.product_update = payload


def test_enrichment_keeps_original_and_foreground_embeddings():
    settings = Settings(enrichment_embedding_batch_size=4)
    store = _Store()
    models = SimpleNamespace(classification=_Classifier(), background_removal=None)
    service = ProductEnrichmentService(settings, models, store)
    image = Image.new("RGB", (80, 100), "white")
    cutout = Image.new("RGBA", (60, 80), (255, 255, 255, 255))
    service._prepare_image = lambda row: _ImageWork(
        row=row,
        original=image,
        original_hash="a" * 64,
        quality=PhotoQuality(0.9, 0.9, 0.9, 0.9, 0.9, ()),
        cutout=cutout,
        cutout_png=b"png",
        foreground_hash="b" * 64,
        colors=[ColorCandidate("white", 1.0, 0.95)],
    )

    result = service.process(
        EnrichmentJob("job-1", "product-1", 0, service.pipeline_version)
    )

    image_payload = store.image_updates[0][1]
    assert image_payload["original_embedding"]
    assert image_payload["foreground_embedding"]
    assert {row["image_url"] for row in store.visual_rows} == {
        "https://img/1.jpg",
        "https://img/1-cutout.png",
    }
    assert result["original_embeddings"] == 1
    assert result["foreground_embeddings"] == 1
    assert store.product_update["enrichment_status"] == "completed"
    assert store.similarities[0]["similar_product_id"] == "product-2"


def test_worker_retries_failed_durable_job():
    job = EnrichmentJob("job-1", "product-1", 2, "v1")

    class Store:
        def __init__(self):
            self.claimed = False
            self.retry_call = None

        def claim(self, worker_id, lease_seconds):
            if self.claimed:
                return None
            self.claimed = True
            return job

        def retry(self, *args):
            self.retry_call = args
            worker.stop()

    class Gate:
        async def run(self, operation):
            return operation()

    store = Store()
    service = SimpleNamespace(process=lambda _: (_ for _ in ()).throw(RuntimeError("offline")))
    worker = ProductEnrichmentWorker(
        Settings(enrichment_poll_seconds=0.01, enrichment_retry_base_seconds=10),
        store,
        service,
        Gate(),
    )
    asyncio.run(worker.run())

    assert store.retry_call is not None
    assert store.retry_call[-1] == 40
