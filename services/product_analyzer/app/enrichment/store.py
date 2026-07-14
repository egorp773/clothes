from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Any

import httpx
import numpy as np

from app.config import Settings


class EnrichmentStoreError(RuntimeError):
    pass


@dataclass(frozen=True)
class EnrichmentJob:
    id: str
    product_id: str
    attempt_count: int
    pipeline_version: str


class SupabaseEnrichmentStore:
    """Service-role store for durable product enrichment work."""

    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._url = settings.supabase_url.rstrip("/") if settings.supabase_url else None
        self._key = settings.supabase_service_role_key
        self._client = httpx.Client(
            follow_redirects=True,
            timeout=httpx.Timeout(20.0, connect=3.0),
        )

    @property
    def enabled(self) -> bool:
        return bool(self._url and self._key)

    @property
    def headers(self) -> dict[str, str]:
        return {
            "apikey": self._key or "",
            "Authorization": f"Bearer {self._key or ''}",
            "Content-Type": "application/json",
        }

    def claim(self, worker_id: str, lease_seconds: int) -> EnrichmentJob | None:
        response = self._request(
            "POST",
            f"{self._url}/rest/v1/rpc/claim_product_enrichment_job",
            headers=self.headers,
            json={
                "p_worker_id": worker_id,
                "p_lease_seconds": lease_seconds,
            },
        )
        payload = response.json()
        row = payload[0] if isinstance(payload, list) and payload else payload
        if not isinstance(row, dict) or not row.get("id"):
            return None
        return EnrichmentJob(
            id=str(row["id"]),
            product_id=str(row["product_id"]),
            attempt_count=int(row.get("attempt_count") or 0),
            pipeline_version=str(
                row.get("pipeline_version") or "publication-enrichment-v1"
            ),
        )

    def complete(
        self,
        job: EnrichmentJob,
        worker_id: str,
        result: dict[str, Any],
    ) -> None:
        self._request(
            "POST",
            f"{self._url}/rest/v1/rpc/complete_product_enrichment_job",
            headers=self.headers,
            json={
                "p_job_id": job.id,
                "p_worker_id": worker_id,
                "p_result": result,
            },
        )

    def retry(
        self,
        job: EnrichmentJob,
        worker_id: str,
        error: str,
        delay_seconds: int,
    ) -> None:
        self._request(
            "POST",
            f"{self._url}/rest/v1/rpc/retry_product_enrichment_job",
            headers=self.headers,
            json={
                "p_job_id": job.id,
                "p_worker_id": worker_id,
                "p_error": error[:1000],
                "p_retry_delay_seconds": delay_seconds,
            },
        )

    def get_product(self, product_id: str) -> dict[str, Any]:
        response = self._request(
            "GET",
            f"{self._url}/rest/v1/products",
            headers=self.headers,
            params={
                "id": f"eq.{product_id}",
                "select": (
                    "id,status,is_hidden,title,description,brand,normalized_brand,"
                "normalized_category,category,subcategory,item_type,audience,gender,"
                    "primary_color,secondary_colors,material,pattern,fit,style,"
                    "sleeve_length,closure,condition,size,"
                    "main_image,image,original_image,images"
                ),
            },
        )
        rows = response.json()
        if not rows:
            raise EnrichmentStoreError(f"Product {product_id} does not exist")
        return dict(rows[0])

    def get_product_images(
        self,
        product_id: str,
        product: dict[str, Any],
    ) -> list[dict[str, Any]]:
        rows = self._load_product_images(product_id)
        if rows:
            return rows[: self.settings.enrichment_max_images]

        # Additive migration backfills these rows. This fallback keeps a
        # legacy listing processable if it was published during deployment.
        candidates = [
            product.get("original_image"),
            product.get("main_image"),
            product.get("image"),
            *(product.get("images") or []),
        ]
        urls: list[str] = []
        for candidate in candidates:
            url = str(candidate or "").strip()
            if url.startswith(("https://", "http://")) and url not in urls:
                urls.append(url)
            if len(urls) >= self.settings.enrichment_max_images:
                break
        if not urls:
            return []
        payload = [
            {
                "product_id": product_id,
                "original_url": url,
                "role": "main" if position == 0 else "gallery",
                "position": position,
            }
            for position, url in enumerate(urls)
        ]
        self._request(
            "POST",
            f"{self._url}/rest/v1/product_images",
            headers={
                **self.headers,
                "Prefer": "resolution=ignore-duplicates,return=minimal",
            },
            params={"on_conflict": "product_id,original_url"},
            json=payload,
        )
        return self._load_product_images(product_id)[: self.settings.enrichment_max_images]

    def _load_product_images(self, product_id: str) -> list[dict[str, Any]]:
        response = self._request(
            "GET",
            f"{self._url}/rest/v1/product_images",
            headers=self.headers,
            params={
                "product_id": f"eq.{product_id}",
                "is_active": "eq.true",
                "select": (
                    "id,product_id,original_url,no_background_url,role,position,"
                    "original_image_hash,foreground_image_hash"
                ),
                "order": "position.asc",
            },
        )
        return [dict(row) for row in response.json()]

    def download_image(self, url: str, max_bytes: int) -> tuple[bytes, str]:
        if not url.startswith(("https://", "http://")):
            raise EnrichmentStoreError("Product image URL must use HTTP(S)")
        with self._client.stream("GET", url, headers={"Accept": "image/*"}) as response:
            response.raise_for_status()
            content_type = response.headers.get("content-type", "").split(";", 1)[0]
            if content_type not in {"image/jpeg", "image/png", "image/webp"}:
                raise EnrichmentStoreError(f"Unsupported image MIME: {content_type}")
            advertised = int(response.headers.get("content-length") or 0)
            if advertised > max_bytes:
                raise EnrichmentStoreError("Product image is too large")
            chunks: list[bytes] = []
            size = 0
            for chunk in response.iter_bytes():
                size += len(chunk)
                if size > max_bytes:
                    raise EnrichmentStoreError("Product image is too large")
                chunks.append(chunk)
        return b"".join(chunks), content_type

    def upload_cutout(self, product_id: str, image_id: str, png: bytes) -> str:
        path = f"enrichment/{product_id}/{image_id}.png"
        self._request(
            "POST",
            f"{self._url}/storage/v1/object/{self.settings.enrichment_cutout_bucket}/{path}",
            headers={
                "apikey": self._key or "",
                "Authorization": f"Bearer {self._key or ''}",
                "Content-Type": "image/png",
                "Cache-Control": "31536000",
                "x-upsert": "true",
            },
            content=png,
        )
        return (
            f"{self._url}/storage/v1/object/public/"
            f"{self.settings.enrichment_cutout_bucket}/{path}"
        )

    def update_product_image(self, image_id: str, payload: dict[str, Any]) -> None:
        self._request(
            "PATCH",
            f"{self._url}/rest/v1/product_images",
            headers={**self.headers, "Prefer": "return=minimal"},
            params={"id": f"eq.{image_id}"},
            json=payload,
        )

    def merge_attribute(
        self,
        product_id: str,
        key: str,
        value: Any,
        confidence: float,
        model_version: str,
        *,
        source: str = "visual",
    ) -> None:
        # The DB trigger compares source/user_confirmed priorities atomically.
        # A concurrent seller edit therefore wins even between this call and
        # the transaction commit.
        self._request(
            "POST",
            f"{self._url}/rest/v1/product_attributes",
            headers={
                **self.headers,
                "Prefer": "resolution=merge-duplicates,return=minimal",
            },
            params={"on_conflict": "product_id,attribute_key"},
            json={
                "product_id": product_id,
                "attribute_key": key,
                "value": value,
                "source": source,
                "confidence": round(max(0.0, min(1.0, confidence)), 4),
                "user_confirmed": False,
                "model_version": model_version,
            },
        )

    @staticmethod
    def vector_literal(embedding: np.ndarray) -> str:
        return "[" + ",".join(f"{float(value):.8f}" for value in embedding) + "]"

    def upsert_visual_embeddings(
        self,
        rows: list[dict[str, Any]],
    ) -> None:
        """Add or refresh views without deleting legacy embeddings."""
        if rows:
            self._request(
                "POST",
                f"{self._url}/rest/v1/product_visual_embeddings",
                headers={
                    **self.headers,
                    "Prefer": "resolution=merge-duplicates,return=minimal",
                },
                params={"on_conflict": "product_id,image_url,model_version"},
                json=rows,
            )

    def find_similar(
        self,
        product_id: str,
        embeddings: list[np.ndarray],
        model_version: str,
        *,
        limit: int = 24,
    ) -> list[dict[str, Any]]:
        """Collapse multi-view retrieval using the best angle per product."""
        best: dict[str, dict[str, Any]] = {}
        for embedding in embeddings:
            response = self._request(
                "POST",
                f"{self._url}/rest/v1/rpc/search_product_visual_candidates",
                headers=self.headers,
                json={
                    "p_query_embedding": self.vector_literal(embedding),
                    "p_model_version": model_version,
                    "p_match_count": max(limit * 2, 40),
                    "p_category": None,
                    "p_related_subcategories": None,
                    "p_min_price": None,
                    "p_max_price": None,
                    "p_sizes": None,
                    "p_brands": None,
                    "p_conditions": None,
                    "p_colors": None,
                },
            )
            for row in response.json():
                candidate_id = str(row.get("product_id") or "")
                if not candidate_id or candidate_id == product_id:
                    continue
                score = float(row.get("visual_similarity") or 0.0)
                previous = best.get(candidate_id)
                if previous is None or score > float(previous["score"]):
                    best[candidate_id] = {
                        "product_id": product_id,
                        "similar_product_id": candidate_id,
                        "score": round(max(0.0, min(1.0, score)), 6),
                        "model_version": model_version,
                    }
        return sorted(best.values(), key=lambda row: row["score"], reverse=True)[
            :limit
        ]

    def replace_similarities(
        self,
        product_id: str,
        rows: list[dict[str, Any]],
    ) -> None:
        self._request(
            "DELETE",
            f"{self._url}/rest/v1/product_similarities",
            headers={**self.headers, "Prefer": "return=minimal"},
            params={"product_id": f"eq.{product_id}"},
        )
        if rows:
            self._request(
                "POST",
                f"{self._url}/rest/v1/product_similarities",
                headers={
                    **self.headers,
                    "Prefer": "resolution=merge-duplicates,return=minimal",
                },
                params={"on_conflict": "product_id,similar_product_id"},
                json=rows,
            )

    def update_product(self, product_id: str, payload: dict[str, Any]) -> None:
        self._request(
            "PATCH",
            f"{self._url}/rest/v1/products",
            headers={**self.headers, "Prefer": "return=minimal"},
            params={"id": f"eq.{product_id}"},
            json=payload,
        )

    @staticmethod
    def _quote(value: str) -> str:
        return '"' + value.replace('"', '\\"') + '"'

    def _request(self, method: str, url: str, **kwargs) -> httpx.Response:
        if not self.enabled:
            raise EnrichmentStoreError("Supabase enrichment store is not configured")
        last_error: Exception | None = None
        for attempt in range(3):
            try:
                response = self._client.request(method, url, **kwargs)
                response.raise_for_status()
                return response
            except (httpx.TimeoutException, httpx.NetworkError) as error:
                last_error = error
                if attempt < 2:
                    time.sleep(0.2 * (2**attempt))
            except httpx.HTTPStatusError as error:
                detail = error.response.text[:500]
                raise EnrichmentStoreError(
                    f"Supabase {error.response.status_code}: {detail}"
                ) from error
        raise EnrichmentStoreError(str(last_error)) from last_error

    def close(self) -> None:
        self._client.close()
