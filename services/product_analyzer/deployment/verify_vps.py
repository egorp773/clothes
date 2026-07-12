from __future__ import annotations

import argparse
import hashlib
import json
import mimetypes
import os
import secrets
import time
import uuid
from pathlib import Path

import httpx


def main() -> None:
    parser = argparse.ArgumentParser(description="End-to-end VPS API smoke test")
    parser.add_argument("--url", required=True)
    parser.add_argument("--image", type=Path)
    args = parser.parse_args()

    supabase_url = os.environ["SUPABASE_URL"].rstrip("/")
    service_key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    base_url = args.url.rstrip("/")
    image: bytes | None = args.image.read_bytes() if args.image else None
    image_name = args.image.name if args.image else "supabase-product.jpg"
    mime = mimetypes.guess_type(image_name)[0] or "image/jpeg"
    admin_headers = {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
    }
    email = f"clothes-deploy-{uuid.uuid4().hex}@example.invalid"
    password = secrets.token_urlsafe(24)
    user_id: str | None = None
    job_id: str | None = None
    job_existed = False
    report: dict[str, object] = {}

    with httpx.Client(timeout=120, follow_redirects=True) as client:
        try:
            created = client.post(
                f"{supabase_url}/auth/v1/admin/users",
                headers=admin_headers,
                json={"email": email, "password": password, "email_confirm": True},
            )
            created.raise_for_status()
            user_id = str(created.json()["id"])
            signed_in = client.post(
                f"{supabase_url}/auth/v1/token",
                params={"grant_type": "password"},
                headers={"apikey": service_key},
                json={"email": email, "password": password},
            )
            signed_in.raise_for_status()
            access_token = str(signed_in.json()["access_token"])
            auth_headers = {"Authorization": f"Bearer {access_token}"}

            product_response = client.get(
                f"{supabase_url}/rest/v1/products",
                headers=admin_headers,
                params={
                    "select": "id,main_image,images",
                    "status": "eq.published",
                    "limit": "1",
                },
            )
            product_response.raise_for_status()
            products = product_response.json()
            if not products:
                raise RuntimeError("No published product is available for the job test")
            listing_id = str(products[0]["id"])
            if image is None:
                image_url = products[0].get("main_image")
                if not image_url and products[0].get("images"):
                    image_url = products[0]["images"][0]
                if not image_url:
                    raise RuntimeError("Published product has no image")
                downloaded = client.get(str(image_url))
                downloaded.raise_for_status()
                image = downloaded.content
                mime = downloaded.headers.get("content-type", mime).split(";", 1)[0]
            assert image is not None
            image_hash = hashlib.sha256(image).hexdigest()
            job_id = str(uuid.uuid5(uuid.NAMESPACE_URL, f"{listing_id}:{image_hash}"))
            existing_job = client.get(
                f"{supabase_url}/rest/v1/listing_analysis_jobs",
                headers=admin_headers,
                params={"id": f"eq.{job_id}", "select": "id"},
            )
            existing_job.raise_for_status()
            job_existed = bool(existing_job.json())

            started = time.perf_counter()
            analyzed = client.post(
                f"{base_url}/v1/analyze",
                headers=auth_headers,
                data={"listing_id": listing_id},
                files={"files": (image_name, image, mime)},
            )
            analyzed.raise_for_status()
            analysis = analyzed.json()
            report["analysis"] = {
                "status": analyzed.status_code,
                "elapsed_ms": round((time.perf_counter() - started) * 1000),
                "category": analysis.get("category"),
            }

            stored_job = client.get(
                f"{supabase_url}/rest/v1/listing_analysis_jobs",
                headers=admin_headers,
                params={"id": f"eq.{job_id}", "select": "id,status,basic_result"},
            )
            stored_job.raise_for_status()
            jobs = stored_job.json()
            report["supabase_job"] = {
                "stored": bool(jobs),
                "status": jobs[0].get("status") if jobs else None,
                "has_basic_result": bool(jobs and jobs[0].get("basic_result")),
            }

            started = time.perf_counter()
            searched = client.post(
                f"{base_url}/v1/visual-search",
                headers=auth_headers,
                files={"file": (image_name, image, mime)},
            )
            searched.raise_for_status()
            search = searched.json()
            report["visual_search"] = {
                "status": searched.status_code,
                "elapsed_ms": round((time.perf_counter() - started) * 1000),
                "products": len(search.get("products", [])),
                "candidates": search.get("candidate_count"),
            }
        finally:
            if job_id and not job_existed:
                client.delete(
                    f"{supabase_url}/rest/v1/listing_analysis_jobs",
                    headers=admin_headers,
                    params={"id": f"eq.{job_id}"},
                )
            if user_id:
                client.delete(
                    f"{supabase_url}/auth/v1/admin/users/{user_id}",
                    headers=admin_headers,
                )

    print(json.dumps(report, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
