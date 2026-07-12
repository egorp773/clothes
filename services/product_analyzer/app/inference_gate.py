from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager


class InferenceQueueFull(RuntimeError):
    pass


class InferenceQueueTimeout(RuntimeError):
    pass


class InferenceGate:
    """Bound concurrent inference and reject work beyond a small wait queue."""

    def __init__(self, concurrency: int, queue_size: int, wait_timeout: float) -> None:
        self._concurrency = max(1, concurrency)
        self._capacity = self._concurrency + max(0, queue_size)
        self._wait_timeout = max(0.1, wait_timeout)
        self._slots = asyncio.Semaphore(self._concurrency)
        self._pending = 0
        self._lock = asyncio.Lock()

    @asynccontextmanager
    async def acquire(self):
        async with self._lock:
            if self._pending >= self._capacity:
                raise InferenceQueueFull("Inference queue is full")
            self._pending += 1
        acquired = False
        try:
            try:
                await asyncio.wait_for(
                    self._slots.acquire(), timeout=self._wait_timeout
                )
                acquired = True
            except asyncio.TimeoutError as error:
                raise InferenceQueueTimeout("Inference queue wait timed out") from error
            yield
        finally:
            async with self._lock:
                self._pending -= 1
            if acquired:
                self._slots.release()

    @property
    def pending(self) -> int:
        return self._pending
