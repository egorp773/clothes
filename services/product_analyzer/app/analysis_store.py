from __future__ import annotations

import logging
import time
from datetime import datetime, timezone
from typing import Any

import httpx

from app.config import Settings
from app.schemas import AnalysisResponse


LOGGER = logging.getLogger(__name__)


class SupabaseAnalysisStore:
    """Durable job/result store shared by API workers.

    It is intentionally disabled without a service-role key: falling back to
    an in-process cache must not accidentally bypass Supabase RLS.
    """

    def __init__(self, settings: Settings) -> None:
        self._url = settings.supabase_url.rstrip("/") if settings.supabase_url else None
        self._key = settings.supabase_service_role_key
        self._client = httpx.Client(timeout=httpx.Timeout(4.0, connect=2.5))

    @property
    def enabled(self) -> bool:
        return bool(self._url and self._key)

    @property
    def _headers(self) -> dict[str, str]:
        return {
            "apikey": self._key or "",
            "Authorization": f"Bearer {self._key or ''}",
            "Content-Type": "application/json",
        }

    def create_pending(
        self,
        job_id: str,
        listing_id: str,
        image_hash: str,
        main_image_url: str | None,
    ) -> str | None:
        if not self.enabled:
            return None
        payload = {
            "id": job_id,
            "listing_id": listing_id,
            "image_hash": image_hash,
            "main_image_url": main_image_url,
            "status": "processing",
            "basic_result": None,
            "enrichment_result": None,
            "timings_ms": {},
            "error": None,
            "attempt_count": 0,
            "lease_until": None,
            "completed_at": None,
        }
        return self._upsert(payload)

    def save_basic(self, job_id: str, result: AnalysisResponse) -> None:
        if not self.enabled:
            return
        payload: dict[str, Any] = {
            "basic_result": result.model_dump(mode="json"),
            "timings_ms": result.timings_ms,
        }
        # A completed content-hash cache hit has no background task to update
        # the freshly reset durable row, so persist its terminal state here.
        if result.enrichment_status == "completed":
            payload.update(
                {
                    "status": "completed",
                    "enrichment_result": result.model_dump(mode="json"),
                    "completed_at": datetime.now(timezone.utc).isoformat(),
                }
            )
        self._patch({"id": f"eq.{job_id}"}, payload)

    def save_result(self, result: AnalysisResponse) -> None:
        if not self.enabled or not result.analysis_id:
            return
        status = (
            "completed"
            if result.enrichment_status == "completed"
            else "failed"
            if result.enrichment_status == "failed"
            else "processing"
        )
        payload: dict[str, Any] = {
            "status": status,
            "enrichment_result": result.model_dump(mode="json"),
            "timings_ms": result.timings_ms,
            "completed_at": (
                datetime.now(timezone.utc).isoformat()
                if status == "completed"
                else None
            ),
        }
        # Pipeline cache keys are content hashes. Persist the enrichment into
        # every listing job that references this image, including jobs created
        # by other API worker processes.
        self._patch({"image_hash": f"eq.{result.analysis_id}"}, payload)

    def get_result(self, analysis_id: str) -> AnalysisResponse | None:
        context = self.get_context(analysis_id)
        return context[1] if context else None

    def get_listing_id(self, analysis_id: str) -> str | None:
        if not self.enabled:
            return None
        try:
            response = self._request(
                "GET",
                f"{self._url}/rest/v1/listing_analysis_jobs",
                params={
                    "id": f"eq.{analysis_id}",
                    "select": "listing_id",
                    "limit": "1",
                },
                headers=self._headers,
            )
            rows = response.json()
            if not rows or not rows[0].get("listing_id"):
                return None
            return str(rows[0]["listing_id"])
        except Exception:
            LOGGER.exception("Unable to load analysis owner context %s", analysis_id)
            return None

    def get_context(self, analysis_id: str) -> tuple[str, AnalysisResponse] | None:
        if not self.enabled:
            return None
        try:
            response = self._request(
                "GET",
                f"{self._url}/rest/v1/listing_analysis_jobs",
                params={
                    "id": f"eq.{analysis_id}",
                    "select": "id,image_hash,status,basic_result,enrichment_result",
                },
                headers=self._headers,
            )
            rows = response.json()
            if not rows:
                return None
            row = rows[0]
            payload = row.get("enrichment_result") or row.get("basic_result")
            if not payload:
                return None
            result = AnalysisResponse.model_validate(payload)
            result.analysis_id = row["id"]
            result.enrichment_status = row["status"]
            return row["image_hash"], result
        except Exception:
            LOGGER.exception("Unable to load analysis result %s", analysis_id)
            return None

    def _upsert(self, payload: dict[str, Any]) -> str | None:
        try:
            response = self._request(
                "POST",
                f"{self._url}/rest/v1/listing_analysis_jobs",
                params={"on_conflict": "listing_id,image_hash"},
                headers={
                    **self._headers,
                    "Prefer": "resolution=merge-duplicates,return=representation",
                },
                json=payload,
            )
            rows = response.json()
            return str(rows[0]["id"]) if rows else str(payload["id"])
        except Exception:
            LOGGER.exception("Unable to create analysis job %s", payload.get("id"))
            return None

    def _patch(self, filters: dict[str, str], payload: dict[str, Any]) -> None:
        try:
            self._request(
                "PATCH",
                f"{self._url}/rest/v1/listing_analysis_jobs",
                params=filters,
                headers={**self._headers, "Prefer": "return=minimal"},
                json=payload,
            )
        except Exception:
            LOGGER.exception("Unable to update analysis job with %s", filters)

    def _request(self, method: str, url: str, **kwargs) -> httpx.Response:
        last_error: Exception | None = None
        for attempt in range(3):
            try:
                response = self._client.request(method, url, **kwargs)
                response.raise_for_status()
                return response
            except (httpx.TimeoutException, httpx.NetworkError) as error:
                last_error = error
                if attempt < 2:
                    time.sleep(0.15 * (2**attempt))
        assert last_error is not None
        raise last_error

    def close(self) -> None:
        self._client.close()
