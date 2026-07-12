from __future__ import annotations

import numpy as np

from app.visual_search.store import SupabaseVisualSearchStore


def test_vector_literal_preserves_actual_vector_length():
    embedding = np.ones(768, dtype=np.float32)
    value = SupabaseVisualSearchStore.vector_literal(embedding)
    assert value.startswith("[") and value.endswith("]")
    assert len(value[1:-1].split(",")) == 768
