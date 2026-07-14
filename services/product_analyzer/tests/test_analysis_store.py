from __future__ import annotations

from app.analysis_store import SupabaseAnalysisStore
from app.config import Settings


class _Response:
    def json(self):
        return [{"id": "current-job"}]


def test_create_pending_resets_stale_result_by_listing_and_image() -> None:
    store = SupabaseAnalysisStore(
        Settings(
            supabase_url="https://example.supabase.co",
            supabase_service_role_key="test-key",
        )
    )
    captured = {}

    def request(method, url, **kwargs):
        captured.update({"method": method, "url": url, **kwargs})
        return _Response()

    store._request = request
    try:
        job_id = store.create_pending(
            "new-job",
            "listing-id",
            "image-hash",
            "https://images/main.jpg",
        )
    finally:
        store.close()

    assert job_id == "current-job"
    assert captured["params"] == {"on_conflict": "listing_id,image_hash"}
    assert "resolution=merge-duplicates" in captured["headers"]["Prefer"]
    assert captured["json"]["status"] == "processing"
    assert captured["json"]["basic_result"] is None
    assert captured["json"]["enrichment_result"] is None
    assert captured["json"]["completed_at"] is None
