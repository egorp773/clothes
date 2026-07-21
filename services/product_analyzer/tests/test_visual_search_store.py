from __future__ import annotations

import json

import httpx
import numpy as np
import pytest

from app.config import Settings
from app.visual_search.store import (
    SupabaseVisualSearchStore,
    VisualSearchStoreError,
    parse_storage_media_reference,
)


def test_vector_literal_preserves_actual_vector_length():
    embedding = np.ones(768, dtype=np.float32)
    value = SupabaseVisualSearchStore.vector_literal(embedding)
    assert value.startswith("[") and value.endswith("]")
    assert len(value[1:-1].split(",")) == 768


def test_private_and_expired_storage_references_parse_on_configured_origin():
    private = parse_storage_media_reference(
        "storage://product-images/seller/listing/main.jpg",
        supabase_url="https://project.supabase.co",
    )
    assert private is not None
    assert private.bucket == "product-images"
    assert private.object_path == "seller/listing/main.jpg"

    expired = parse_storage_media_reference(
        "https://project.supabase.co/storage/v1/object/sign/outfit-images/"
        "seller%2Foutfit%2Fold.webp?token=expired",
        supabase_url="https://project.supabase.co",
    )
    assert expired is not None
    assert expired.bucket == "outfit-images"
    assert expired.object_path == "seller/outfit/old.webp"

    assert (
        parse_storage_media_reference(
            "https://foreign.supabase.co/storage/v1/object/sign/product-images/"
            "seller/listing/main.jpg?token=foreign",
            supabase_url="https://project.supabase.co",
        )
        is None
    )
    assert (
        parse_storage_media_reference(
            "storage://product-images/seller/../private.jpg",
            supabase_url="https://project.supabase.co",
        )
        is None
    )


def test_store_signs_private_media_with_service_role_and_fixed_ttl():
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        assert request.url.path == (
            "/storage/v1/object/sign/product-images/seller/listing/main.jpg"
        )
        assert request.headers["apikey"] == "service-role-test-key"
        assert request.headers["authorization"] == "Bearer service-role-test-key"
        assert json.loads(request.content) == {"expiresIn": 300}
        return httpx.Response(
            200,
            json={
                "signedURL": (
                    "/object/sign/product-images/seller/listing/main.jpg"
                    "?token=fresh"
                )
            },
        )

    store = SupabaseVisualSearchStore(
        Settings(
            _env_file=None,
            supabase_url="https://project.supabase.co",
            supabase_service_role_key="service-role-test-key",
        )
    )
    store._client.close()
    store._client = httpx.Client(transport=httpx.MockTransport(handler))
    try:
        resolved = store.resolve_media_download_url(
            "storage://product-images/seller/listing/main.jpg"
        )
    finally:
        store.close()

    assert resolved == (
        "https://project.supabase.co/storage/v1/object/sign/product-images/"
        "seller/listing/main.jpg?token=fresh"
    )
    assert len(requests) == 1


def test_store_rejects_signed_url_that_escapes_supabase_origin():
    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            json={"signedURL": "https://attacker.example/image.jpg?token=leaked"},
        )

    store = SupabaseVisualSearchStore(
        Settings(
            _env_file=None,
            supabase_url="https://project.supabase.co",
            supabase_service_role_key="service-role-test-key",
        )
    )
    store._client.close()
    store._client = httpx.Client(transport=httpx.MockTransport(handler))
    try:
        with pytest.raises(VisualSearchStoreError, match="unsafe"):
            store.resolve_media_download_url(
                "storage://outfit-images/seller/outfit/main.webp"
            )
    finally:
        store.close()
