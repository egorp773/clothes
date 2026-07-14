from __future__ import annotations

import asyncio
import logging
import socket
import uuid

from app.config import Settings
from app.enrichment.service import ProductEnrichmentService
from app.enrichment.store import SupabaseEnrichmentStore
from app.inference_gate import InferenceGate


LOGGER = logging.getLogger(__name__)


class ProductEnrichmentWorker:
    def __init__(
        self,
        settings: Settings,
        store: SupabaseEnrichmentStore,
        service: ProductEnrichmentService,
        inference_gate: InferenceGate,
    ) -> None:
        self.settings = settings
        self.store = store
        self.service = service
        self.inference_gate = inference_gate
        self.worker_id = f"{socket.gethostname()}:{uuid.uuid4().hex[:10]}"
        self._wake = asyncio.Event()
        self._stopping = False

    def wake(self) -> None:
        self._wake.set()

    def stop(self) -> None:
        self._stopping = True
        self._wake.set()

    async def run(self) -> None:
        while not self._stopping:
            job = await asyncio.to_thread(
                self.store.claim,
                self.worker_id,
                self.settings.enrichment_lease_seconds,
            )
            if job is None:
                self._wake.clear()
                try:
                    await asyncio.wait_for(
                        self._wake.wait(),
                        timeout=self.settings.enrichment_poll_seconds,
                    )
                except asyncio.TimeoutError:
                    pass
                continue
            try:
                # Do not time out a Python inference thread: it cannot be
                # cancelled safely and must retain the shared gate slot.
                result = await self.inference_gate.run(
                    lambda: self.service.process(job)
                )
                await asyncio.to_thread(
                    self.store.complete, job, self.worker_id, result
                )
            except asyncio.CancelledError:
                raise
            except Exception as error:
                delay = min(
                    3600,
                    self.settings.enrichment_retry_base_seconds
                    * (2 ** min(job.attempt_count, 6)),
                )
                LOGGER.exception(
                    "Enrichment job %s for product %s failed",
                    job.id,
                    job.product_id,
                )
                await asyncio.to_thread(
                    self.store.retry,
                    job,
                    self.worker_id,
                    f"{type(error).__name__}: {error}",
                    delay,
                )
