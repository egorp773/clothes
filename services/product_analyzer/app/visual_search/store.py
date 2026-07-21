from __future__ import annotations

import re
import time
from dataclasses import dataclass
from typing import Any
from urllib.parse import quote, unquote, urlsplit

import httpx
import numpy as np

from app.config import Settings


class VisualSearchStoreError(RuntimeError):
    pass


@dataclass(frozen=True)
class StorageMediaReference:
    bucket: str
    object_path: str


_MEDIA_BUCKETS = frozenset({"product-images", "outfit-images"})
_CANONICAL_LISTING_PATH = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/"
    r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[^/]+$",
    re.IGNORECASE,
)


def parse_storage_media_reference(
    value: str,
    *,
    supabase_url: str | None,
) -> StorageMediaReference | None:
    """Return a safe private-media object without trusting URL hosts.

    Persisted storage:// values and legacy Storage URLs on this deployment's
    exact Supabase origin are accepted. Arbitrary remote URLs remain external
    inputs and continue through the existing SSRF validation boundary.
    """

    normalized = str(value or "").strip()
    for bucket in _MEDIA_BUCKETS:
        prefix = f"storage://{bucket}/"
        if normalized.startswith(prefix):
            object_path = _safe_object_path(normalized[len(prefix) :])
            return (
                StorageMediaReference(bucket, object_path)
                if object_path is not None
                else None
            )

    parsed = urlsplit(normalized)
    if parsed.scheme.lower() in {"http", "https"}:
        if (
            not supabase_url
            or parsed.username is not None
            or parsed.password is not None
            or parsed.fragment
            or not _same_origin(parsed, urlsplit(supabase_url))
        ):
            return None
        for bucket in _MEDIA_BUCKETS:
            markers = (
                f"/storage/v1/object/public/{bucket}/",
                f"/storage/v1/object/sign/{bucket}/",
                f"/storage/v1/object/authenticated/{bucket}/",
                f"/storage/v1/object/{bucket}/",
                f"/storage/v1/render/image/public/{bucket}/",
                f"/storage/v1/render/image/sign/{bucket}/",
            )
            for marker in markers:
                marker_index = parsed.path.find(marker)
                if marker_index < 0:
                    continue
                object_path = _safe_object_path(
                    parsed.path[marker_index + len(marker) :]
                )
                return (
                    StorageMediaReference(bucket, object_path)
                    if object_path is not None
                    else None
                )
        return None

    if _CANONICAL_LISTING_PATH.fullmatch(normalized):
        object_path = _safe_object_path(normalized)
        if object_path is not None:
            return StorageMediaReference("product-images", object_path)
    return None


class SupabaseVisualSearchStore:
    def __init__(self, settings: Settings) -> None:
        self._url = settings.supabase_url.rstrip("/") if settings.supabase_url else None
        self._key = settings.supabase_service_role_key
        self._signed_url_seconds = settings.visual_search_signed_url_seconds
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
                    "cutout_image,outfit_images,"
                    "category,subcategory,item_type,primary_color,brand,gender,condition"
                ),
            },
        )
        rows = response.json()
        return dict(rows[0]) if rows else None

    def resolve_media_download_url(self, reference: str) -> str:
        """Resolve private Storage media for one short-lived indexing read."""

        normalized = str(reference or "").strip()
        media = parse_storage_media_reference(
            normalized,
            supabase_url=self._url,
        )
        if media is None:
            if normalized.startswith(("https://", "http://")):
                return normalized
            raise VisualSearchStoreError("Unsupported product media reference")

        self._require_enabled()
        encoded_path = "/".join(
            quote(segment, safe="") for segment in media.object_path.split("/")
        )
        response = self._request(
            "POST",
            f"{self._url}/storage/v1/object/sign/{media.bucket}/{encoded_path}",
            headers=self.headers,
            json={"expiresIn": self._signed_url_seconds},
        )
        try:
            payload = response.json()
        except ValueError as error:
            raise VisualSearchStoreError(
                "Supabase returned an invalid signed media response"
            ) from error
        if not isinstance(payload, dict):
            raise VisualSearchStoreError(
                "Supabase returned an invalid signed media response"
            )
        signed_value = str(
            payload.get("signedURL") or payload.get("signedUrl") or ""
        ).strip()
        return self._absolute_signed_url(signed_value, media)

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

    def _absolute_signed_url(
        self,
        value: str,
        media: StorageMediaReference,
    ) -> str:
        if not self._url or not value:
            raise VisualSearchStoreError("Supabase did not return a signed media URL")
        if value.startswith("/storage/v1/"):
            candidate = f"{self._url}{value}"
        elif value.startswith("/object/"):
            candidate = f"{self._url}/storage/v1{value}"
        elif value.startswith(("https://", "http://")):
            candidate = value
        else:
            raise VisualSearchStoreError("Supabase returned an invalid signed media URL")

        parsed = urlsplit(candidate)
        expected = urlsplit(self._url)
        expected_prefix = f"/storage/v1/object/sign/{media.bucket}/"
        returned_object_path = (
            _safe_object_path(parsed.path[len(expected_prefix) :])
            if parsed.path.startswith(expected_prefix)
            else None
        )
        if (
            not _same_origin(parsed, expected)
            or parsed.username is not None
            or parsed.password is not None
            or parsed.fragment
            or returned_object_path != media.object_path
        ):
            raise VisualSearchStoreError("Supabase returned an unsafe signed media URL")
        return candidate


def _safe_object_path(value: str) -> str | None:
    if re.search(r"%(?![0-9a-fA-F]{2})", value):
        return None
    try:
        decoded = unquote(value).strip()
    except (TypeError, UnicodeError):
        return None
    if not decoded or decoded.startswith("/") or decoded.endswith("/"):
        return None
    segments = decoded.split("/")
    if any(
        not segment
        or segment in {".", ".."}
        or any(ord(character) < 32 or ord(character) == 127 for character in segment)
        for segment in segments
    ):
        return None
    return decoded


def _same_origin(first, second) -> bool:
    def origin(value) -> tuple[str, str | None, int | None]:
        scheme = value.scheme.lower()
        default_port = 443 if scheme == "https" else 80 if scheme == "http" else None
        return (
            scheme,
            value.hostname.lower() if value.hostname else None,
            value.port or default_port,
        )

    try:
        return origin(first) == origin(second)
    except ValueError:
        return False
