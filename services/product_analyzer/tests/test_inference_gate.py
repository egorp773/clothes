from __future__ import annotations

import asyncio
import threading

import pytest

from app.inference_gate import InferenceGate


def test_timed_out_thread_keeps_the_only_inference_slot() -> None:
    async def scenario() -> None:
        gate = InferenceGate(concurrency=1, queue_size=1, wait_timeout=1.0)
        release_first = threading.Event()

        with pytest.raises(asyncio.TimeoutError):
            await gate.run(
                lambda: release_first.wait(timeout=2.0),
                timeout=0.02,
            )

        assert gate.pending == 1
        second = asyncio.create_task(gate.run(lambda: "second", timeout=1.0))
        await asyncio.sleep(0.03)
        assert not second.done()

        release_first.set()
        assert await second == "second"
        assert gate.pending == 0

    asyncio.run(scenario())
