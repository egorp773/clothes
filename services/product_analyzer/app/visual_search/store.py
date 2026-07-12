from __future__ import annotations

import time
from typing import Any

import httpx
import numpy as np

from app.config import Settings


class VisualSearchStoreError(RuntimeError):
    pass


class SupabaseVisualSearchStore:
    def __init__(self, settings: Settings) -> None:
        self._url = settings.supabase_url.rstrip("/") if settings.supabase_url else None
        self._key = settings.supabase_service_role_key
        self._client = httpx.Client(
            timeout=httpx.Timeout(settings.visual_search_download_timeout_seconds, connect=2.5)
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

    @staticmethod
    def vector_literal(embedding: np.ndarray) -> str:
        return "[" + ",".join(f"{float(value):.8f}" for value in embedding) + "]"

    def retrieve(
        self,
        embedding: np.ndarray,
        *,
        model_version: str,
        match_count: int,
        category: str | None,
        related_subcategories: list[str] | None,
        filters: dict[str, Any],
    ) -> list[dict[str, Any]]:
        self._require_enabled()
        payload = {
            "p_query_embedding": self.vector_literal(embedding),
            "p_model_version": model_version,
            "p_match_count": match_count,
            "p_category": category,
            "p_related_subcategories": related_subcategories,
            "p_min_price": filters.get("min_price"),
            "p_max_price": filters.get("max_price"),
            "p_sizes": filters.get("sizes") or None,
            "p_brands": filters.get("brands") or None,
            "p_conditions": filters.get("conditions") or None,
            "p_colors": filters.get("colors") or None,
        }
        response = self._request(
            "POST",
            f"{self._url}/rest/v1/rpc/search_product_visual_candidates",
            headers=self.headers,
            json=payload,
        )
        rows = response.json()
        return [dict(row) for row in rows]

    def get_product(self, product_id: str) -> dict[str, Any] | None:
        self._require_enabled()
        response = self._request(
            "GET",
            f"{self._url}/rest/v1/products",
            headers=self.headers,
            params={
                "id": f"eq.{product_id}",
                "select": (
                    "id,seller_id,status,is_hidden,main_image,image,original_image,images,"
                    "category,subcategory,item_type,primary_color,brand,gender,condition"
                ),
            },
        )
        rows = response.json()
        return dict(rows[0]) if rows else None

    def replace_embeddings(
        self,
        product_id: str,
        model_version: str,
        rows: list[dict[str, Any]],
    ) -> bool:
        self._require_enabled()
        existing_response = self._request(
            "GET",
            f"{self._url}/rest/v1/product_visual_embeddings",
            headers=self.headers,
            params={
                "product_id": f"eq.{product_id}",
                "model_version": f"eq.{model_version}",
                "select": (
                    "image_url,image_hash,view_type,detected_category,"
                    "detected_subcategory,detected_item_type,detected_category_confidence"
                ),
            },
        )
        existing = sorted(existing_response.json(), key=lambda row: row["image_url"])
        desired_identity = sorted(
            [
                {
                    "image_url": row["image_url"],
                    "image_hash": row["image_hash"],
                    "view_type": row["view_type"],
                    "detected_category": row.get("detected_category"),
                    "detected_subcategory": row.get("detected_subcategory"),
                    "detected_item_type": row.get("detected_item_type"),
                    "detected_category_confidence": row.get("detected_category_confidence"),
                }
                for row in rows
            ],
            key=lambda row: row["image_url"],
        )
        if existing == desired_identity:
            return True
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
        self._request(
            "DELETE",
            f"{self._url}/rest/v1/product_visual_embeddings",
            headers={**self.headers, "Prefer": "return=minimal"},
            params={
                "product_id": f"eq.{product_id}",
                "model_version": f"eq.{model_version}",
                "image_url": "not.in.(" + ",".join(self._quote(row["image_url"]) for row in rows) + ")"
                if rows
                else "not.is.null",
            },
        )
        return False

    def list_published_products(self, offset: int, limit: int) -> list[dict[str, Any]]:
        self._require_enabled()
        response = self._request(
            "GET",
            f"{self._url}/rest/v1/products",
            headers={**self.headers, "Range-Unit": "items", "Range": f"{offset}-{offset + limit - 1}"},
            params={
                "status": "eq.published",
                "is_hidden": "eq.false",
                "select": "id",
                "order": "published_at.desc.nullslast",
            },
        )
        return [dict(row) for row in response.json()]

    def index_stats(self, model_version: str) -> dict[str, int]:
        self._require_enabled()
        response = self._request(
            "GET",
            f"{self._url}/rest/v1/product_visual_embeddings",
            headers={**self.headers, "Prefer": "count=exact"},
            params={"model_version": f"eq.{model_version}", "select": "id", "limit": "1"},
        )
        content_range = response.headers.get("content-range", "*/0")
        count = int(content_range.rsplit("/", 1)[-1])
        return {"embedding_count": count}

    @staticmethod
    def _quote(value: str) -> str:
        return '"' + value.replace('"', '\\"') + '"'

    def _require_enabled(self) -> None:
        if not self.enabled:
            raise VisualSearchStoreError("Supabase visual search is not configured")

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
            except httpx.HTTPStatusError as error:
                detail = error.response.text[:500]
                raise VisualSearchStoreError(
                    f"Supabase {error.response.status_code}: {detail}"
                ) from error
        raise VisualSearchStoreError(str(last_error)) from last_error

    def close(self) -> None:
        self._client.close()
