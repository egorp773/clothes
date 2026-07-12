from __future__ import annotations

import json
import os
import secrets
import sys
from pathlib import Path

import httpx


REPO_ROOT = Path(__file__).resolve().parents[3]
supabase_url = os.environ["SUPABASE_URL"].rstrip("/")
service_key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
anon_key = os.environ["SUPABASE_ANON_KEY"]
analyzer_url = os.environ.get("ANALYZER_URL", "http://127.0.0.1:8090").rstrip("/")
email = f"visual-smoke-{secrets.token_hex(6)}@example.test"
password = secrets.token_urlsafe(18) + "A1!"
admin_headers = {"apikey": service_key, "Authorization": f"Bearer {service_key}"}
user_id = None

try:
    with httpx.Client(timeout=30) as client:
        created = client.post(
            f"{supabase_url}/auth/v1/admin/users",
            headers=admin_headers,
            json={"email": email, "password": password, "email_confirm": True},
        )
        created.raise_for_status()
        user_id = created.json()["id"]
        signed_in = client.post(
            f"{supabase_url}/auth/v1/token?grant_type=password",
            headers={"apikey": service_key},
            json={"email": email, "password": password},
        )
        signed_in.raise_for_status()
        token = signed_in.json()["access_token"]
        verified = client.get(
            f"{supabase_url}/auth/v1/user",
            headers={"apikey": service_key, "Authorization": f"Bearer {token}"},
        )
        direct_vectors = client.get(
            f"{supabase_url}/rest/v1/product_visual_embeddings?select=id&limit=1",
            headers={"apikey": anon_key, "Authorization": f"Bearer {token}"},
        )
        image_path = Path(
            os.environ.get(
                "SMOKE_IMAGE_PATH",
                str(REPO_ROOT / "assets" / "products" / "graphic_hoodie.jpg"),
            )
        )
        unauthorized = client.post(
            f"{analyzer_url}/v1/visual-search",
            files={"file": (image_path.name, image_path.read_bytes(), "image/jpeg")},
        )
        searched = client.post(
            f"{analyzer_url}/v1/visual-search",
            headers={"Authorization": f"Bearer {token}"},
            files={"file": (image_path.name, image_path.read_bytes(), "image/jpeg")},
            data={"filters": "{}"},
        )
        if searched.status_code != 200:
            raise RuntimeError(
                f"direct_auth={verified.status_code} endpoint={searched.status_code} "
                f"detail={searched.text[:300]}"
            )
        payload = searched.json()
        top_products = payload.get("products", [])[:10]
        print(
            json.dumps(
                {
                    "unauthorized_status": unauthorized.status_code,
                    "authorized_status": searched.status_code,
                    "direct_vector_table_status": direct_vectors.status_code,
                    "products": len(payload.get("products", [])),
                    "candidate_count": payload.get("candidate_count"),
                    "top_brands": [row.get("brand") for row in top_products],
                    "top_item_types": [row.get("item_type") for row in top_products],
                    "timings_ms": payload.get("timings_ms"),
                },
                ensure_ascii=False,
            )
        )
        if unauthorized.status_code != 401:
            raise SystemExit("Visual search unexpectedly accepts anonymous requests")
        if direct_vectors.status_code < 400:
            raise SystemExit("Authenticated client unexpectedly reads vector table")
finally:
    if user_id:
        httpx.delete(
            f"{supabase_url}/auth/v1/admin/users/{user_id}",
            headers=admin_headers,
            timeout=15,
        )
