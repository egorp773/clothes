from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
from typing import Callable, TypeVar


T = TypeVar("T")


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

    async def _reserve(self) -> None:
        async with self._lock:
            if self._pending >= self._capacity:
                raise InferenceQueueFull("Inference queue is full")
            self._pending += 1
        try:
            await asyncio.wait_for(self._slots.acquire(), timeout=self._wait_timeout)
        except asyncio.TimeoutError as error:
            async with self._lock:
                self._pending -= 1
            raise InferenceQueueTimeout("Inference queue wait timed out") from error

    async def _release(self) -> None:
        async with self._lock:
            self._pending -= 1
        self._slots.release()

    async def _release_after(self, task: asyncio.Task[object]) -> None:
        try:
            await task
        except BaseException:
            pass
        finally:
            await self._release()

    async def run(
        self,
        operation: Callable[[], T],
        *,
        timeout: float | None = None,
    ) -> T:
        """Run blocking inference while retaining the slot until its thread ends.

        ``asyncio.to_thread`` cannot stop a running model when an HTTP timeout or
        client cancellation occurs.  Deferring the release prevents a second
        request from entering the model while that orphaned thread still runs.
        """
        await self._reserve()
        task = asyncio.create_task(asyncio.to_thread(operation))
        release_now = True
        try:
            if timeout is None:
                return await task
            return await asyncio.wait_for(asyncio.shield(task), timeout=timeout)
        except (asyncio.TimeoutError, asyncio.CancelledError):
            release_now = False
            asyncio.create_task(self._release_after(task))
            raise
        finally:
            if release_now:
                await self._release()

    @asynccontextmanager
    async def acquire(self):
        await self._reserve()
        try:
            yield
        finally:
            await self._release()

    @property
    def pending(self) -> int:
        return self._pending
