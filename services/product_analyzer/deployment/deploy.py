from __future__ import annotations

import json
import os
import secrets
import subprocess
import sys
import time
import uuid
from pathlib import Path
from typing import Any

import httpx
from huggingface_hub import CommitOperationAdd, HfApi, hf_hub_download


DEPLOYMENT_ROOT = Path(__file__).resolve().parent
SERVICE_ROOT = DEPLOYMENT_ROOT.parent
REPOSITORY_ROOT = DEPLOYMENT_ROOT.parents[2]
SPACE_NAME = "clothes-product-analyzer"


def _supabase_json(*args: str) -> Any:
    process = subprocess.run(
        ["supabase", *args, "--output", "json"],
        cwd=REPOSITORY_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if process.returncode:
        raise RuntimeError("Supabase CLI command failed; no secret output was shown")
    try:
        return json.loads(process.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError("Supabase CLI returned invalid JSON") from error


def _supabase_credentials() -> tuple[str, str, str]:
    projects = _supabase_json("projects", "list")
    linked = [project for project in projects if project.get("linked")]
    if len(linked) != 1:
        raise RuntimeError("Expected exactly one linked Supabase project")
    project_ref = str(linked[0]["ref"])
    keys = _supabase_json("projects", "api-keys", "--project-ref", project_ref)
    by_name = {str(item.get("name")): str(item.get("api_key")) for item in keys}
    service_key = by_name.get("service_role")
    anon_key = by_name.get("anon")
    if not service_key or not anon_key:
        raise RuntimeError("Supabase legacy anon/service_role keys were not found")
    return f"https://{project_ref}.supabase.co", service_key, anon_key


def _operations(secret_values: tuple[str, ...]) -> list[CommitOperationAdd]:
    files: list[tuple[str, Path]] = []
    for name in (
        "README.md",
        "Dockerfile",
        "requirements-space.txt",
        ".dockerignore",
        "deploy.py",
        "verify_space.py",
    ):
        files.append((name, DEPLOYMENT_ROOT / name))
    for path in sorted((DEPLOYMENT_ROOT / "scripts").glob("*")):
        if path.is_file():
            files.append((f"scripts/{path.name}", path))
    for path in sorted((SERVICE_ROOT / "app").rglob("*.py")):
        relative = path.relative_to(SERVICE_ROOT).as_posix()
        files.append((relative, path))

    for remote_path, local_path in files:
        payload = local_path.read_bytes()
        if any(secret.encode() in payload for secret in secret_values):
            raise RuntimeError(f"Refusing to upload a secret found in {remote_path}")
    return [
        CommitOperationAdd(path_in_repo=remote, path_or_fileobj=str(local))
        for remote, local in files
    ]


def _wait_for_runtime(api: HfApi, repo_id: str, timeout_seconds: int = 3600) -> str:
    deadline = time.monotonic() + timeout_seconds
    last_stage = "unknown"
    while time.monotonic() < deadline:
        runtime = api.get_space_runtime(repo_id=repo_id)
        last_stage = str(runtime.stage).split(".")[-1]
        if last_stage == "RUNNING":
            return last_stage
        if last_stage in {"BUILD_ERROR", "RUNTIME_ERROR", "CONFIG_ERROR"}:
            raise RuntimeError(f"Space entered terminal stage {last_stage}")
        time.sleep(15)
    raise TimeoutError(f"Space did not start; last stage was {last_stage}")


def _wait_until_ready(base_url: str, timeout_seconds: int = 1800) -> int:
    started = time.perf_counter()
    deadline = time.monotonic() + timeout_seconds
    with httpx.Client(timeout=15, follow_redirects=True) as client:
        while time.monotonic() < deadline:
            try:
                response = client.get(f"{base_url}/ready")
                if response.status_code == 200 and response.json().get("ready") is True:
                    return round((time.perf_counter() - started) * 1000)
            except (httpx.HTTPError, ValueError):
                pass
            time.sleep(10)
    raise TimeoutError("Space did not become ready")


def _headers(key: str) -> dict[str, str]:
    return {"apikey": key, "Authorization": f"Bearer {key}"}


def _create_smoke_user(
    client: httpx.Client,
    supabase_url: str,
    service_key: str,
    anon_key: str,
) -> tuple[str, str]:
    email = f"space-smoke-{uuid.uuid4().hex}@example.com"
    password = secrets.token_urlsafe(32)
    response = client.post(
        f"{supabase_url}/auth/v1/admin/users",
        headers=_headers(service_key),
        json={"email": email, "password": password, "email_confirm": True},
    )
    response.raise_for_status()
    user_id = str(response.json()["id"])
    token_response = client.post(
        f"{supabase_url}/auth/v1/token",
        params={"grant_type": "password"},
        headers={"apikey": anon_key},
        json={"email": email, "password": password},
    )
    token_response.raise_for_status()
    return user_id, str(token_response.json()["access_token"])


def _timed(client: httpx.Client, method: str, url: str, **kwargs):
    started = time.perf_counter()
    response = client.request(method, url, **kwargs)
    return response, round((time.perf_counter() - started) * 1000)


def _smoke(
    base_url: str,
    supabase_url: str,
    service_key: str,
    anon_key: str,
) -> dict[str, Any]:
    image_path = REPOSITORY_ROOT / "outfit.jpeg"
    if not image_path.is_file():
        raise RuntimeError("Smoke test image outfit.jpeg is missing")
    image = image_path.read_bytes()
    report: dict[str, Any] = {}
    user_id: str | None = None
    job_id: str | None = None
    with httpx.Client(timeout=90, follow_redirects=True) as client:
        try:
            user_id, access_token = _create_smoke_user(
                client, supabase_url, service_key, anon_key
            )
            auth = {"Authorization": f"Bearer {access_token}"}
            for endpoint in ("health", "ready"):
                response, elapsed = _timed(client, "GET", f"{base_url}/{endpoint}")
                response.raise_for_status()
                report[endpoint] = {"status": response.status_code, "elapsed_ms": elapsed}

            response, elapsed = _timed(
                client,
                "POST",
                f"{base_url}/v1/analyze",
                files={"files": ("outfit.jpeg", image, "image/jpeg")},
            )
            if response.status_code != 401:
                raise RuntimeError("Analysis endpoint accepted a request without JWT")
            report["analysis_without_jwt"] = {
                "status": response.status_code,
                "elapsed_ms": elapsed,
            }

            product_response = client.get(
                f"{supabase_url}/rest/v1/products",
                headers=_headers(service_key),
                params={"select": "id", "limit": "1"},
            )
            product_response.raise_for_status()
            products = product_response.json()
            if not products:
                raise RuntimeError("Supabase has no product for persistence smoke test")
            listing_id = str(products[0]["id"])

            response, cold_ms = _timed(
                client,
                "POST",
                f"{base_url}/v1/analyze",
                headers=auth,
                data={"listing_id": listing_id},
                files={"files": ("outfit.jpeg", image, "image/jpeg")},
            )
            response.raise_for_status()
            job_id = str(response.json()["analysis_id"])
            report["analysis_cold"] = {
                "status": response.status_code,
                "elapsed_ms": cold_ms,
                "model_timings_ms": response.json().get("timings_ms", {}),
            }

            response, warm_ms = _timed(
                client,
                "POST",
                f"{base_url}/v1/analyze",
                headers=auth,
                data={"listing_id": listing_id},
                files={"files": ("outfit.jpeg", image, "image/jpeg")},
            )
            response.raise_for_status()
            report["analysis_warm"] = {
                "status": response.status_code,
                "elapsed_ms": warm_ms,
                "model_timings_ms": response.json().get("timings_ms", {}),
            }

            response, read_ms = _timed(
                client,
                "GET",
                f"{base_url}/v1/analyze/{job_id}",
                headers=auth,
            )
            response.raise_for_status()
            report["supabase_job_read"] = {
                "status": response.status_code,
                "elapsed_ms": read_ms,
            }

            persisted = client.get(
                f"{supabase_url}/rest/v1/listing_analysis_jobs",
                headers=_headers(service_key),
                params={"id": f"eq.{job_id}", "select": "id,basic_result"},
            )
            persisted.raise_for_status()
            rows = persisted.json()
            if not rows or not rows[0].get("basic_result"):
                raise RuntimeError("Analysis job/result was not persisted in Supabase")
            report["supabase_persistence"] = {"write": True, "read": True}

            response, visual_ms = _timed(
                client,
                "POST",
                f"{base_url}/v1/visual-search",
                headers=auth,
                files={"file": ("outfit.jpeg", image, "image/jpeg")},
            )
            response.raise_for_status()
            visual = response.json()
            report["visual_search"] = {
                "status": response.status_code,
                "elapsed_ms": visual_ms,
                "products": len(visual.get("products", [])),
                "model_timings_ms": visual.get("timings_ms", {}),
            }
        finally:
            if job_id:
                client.delete(
                    f"{supabase_url}/rest/v1/listing_analysis_jobs",
                    headers={**_headers(service_key), "Prefer": "return=minimal"},
                    params={"id": f"eq.{job_id}"},
                )
            if user_id:
                client.delete(
                    f"{supabase_url}/auth/v1/admin/users/{user_id}",
                    headers=_headers(service_key),
                )
    return report


def _verify_public_files(
    api: HfApi,
    repo_id: str,
    secret_values: tuple[str, ...],
) -> int:
    info = api.space_info(repo_id=repo_id, files_metadata=True)
    checked = 0
    for sibling in info.siblings or []:
        filename = sibling.rfilename
        if not filename or filename.startswith(".git"):
            continue
        path = hf_hub_download(repo_id, filename, repo_type="space")
        payload = Path(path).read_bytes()
        if any(secret.encode() in payload for secret in secret_values):
            raise RuntimeError(f"Deployment secret found in public file {filename}")
        checked += 1
    return checked


def _set_edge_secret(name: str, value: str) -> None:
    process = subprocess.run(
        ["supabase", "secrets", "set", f"{name}={value}"],
        cwd=REPOSITORY_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if process.returncode:
        raise RuntimeError(f"Could not synchronize Supabase secret {name}")


def main() -> None:
    started = time.perf_counter()
    supabase_url, service_key, anon_key = _supabase_credentials()
    analyzer_service_secret = os.environ.get("ANALYZER_SERVICE_SECRET", "").strip()
    if len(analyzer_service_secret) < 32:
        raise RuntimeError(
            "Set ANALYZER_SERVICE_SECRET to at least 32 random characters"
        )
    api = HfApi()
    account = str(api.whoami()["name"])
    repo_id = f"{account}/{SPACE_NAME}"
    base_url = f"https://{account}-{SPACE_NAME}.hf.space"

    api.create_repo(
        repo_id=repo_id,
        repo_type="space",
        space_sdk="docker",
        private=False,
        exist_ok=True,
    )
    api.add_space_secret(repo_id, "SUPABASE_URL", supabase_url)
    api.add_space_secret(repo_id, "SUPABASE_SERVICE_ROLE_KEY", service_key)
    api.add_space_secret(
        repo_id,
        "ANALYZER_SERVICE_SECRET",
        analyzer_service_secret,
    )
    _set_edge_secret("PRODUCT_ANALYZER_SHARED_SECRET", analyzer_service_secret)
    variables = {
        "PORT": "7860",
        "ENABLE_QWEN": "false",
        "ENABLE_PADDLEOCR": "false",
        "ENABLE_GROUNDED_SAM": "false",
        "PRELOAD_SLOW_MODELS": "false",
        "REQUIRE_ANALYSIS_AUTH": "true",
        "INFERENCE_MAX_CONCURRENCY": "1",
        "INFERENCE_QUEUE_SIZE": "4",
        "CORS_ORIGIN_REGEX": r"(?!)",
    }
    for key, value in variables.items():
        api.add_space_variable(repo_id, key, value)
    api.create_commit(
        repo_id=repo_id,
        repo_type="space",
        operations=_operations((service_key, anon_key, analyzer_service_secret)),
        commit_message="Deploy CPU FastAPI analyzer and visual search",
    )
    try:
        api.request_space_hardware(repo_id=repo_id, hardware="cpu-basic")
    except Exception:
        # A free Space is already cpu-basic; requesting the same flavor is not
        # supported by every huggingface_hub version.
        pass

    build_stage = _wait_for_runtime(api, repo_id)
    readiness_ms = _wait_until_ready(base_url)
    smoke = _smoke(base_url, supabase_url, service_key, anon_key)
    public_file_count = _verify_public_files(
        api,
        repo_id,
        (service_key, anon_key, analyzer_service_secret),
    )
    report = {
        "repo_id": repo_id,
        "space_url": base_url,
        "health_url": f"{base_url}/health",
        "ready_url": f"{base_url}/ready",
        "build_stage": build_stage,
        "readiness_ms": readiness_ms,
        "public_files_scanned": public_file_count,
        "service_role_in_public_files": False,
        "disabled": [
            "Qwen",
            "PaddleOCR",
            "Grounded-SAM",
            "Grounding DINO",
            "CUDA",
            "bitsandbytes",
        ],
        "smoke": smoke,
        "deployment_elapsed_ms": round((time.perf_counter() - started) * 1000),
    }
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"Deployment failed: {type(error).__name__}: {error}", file=sys.stderr)
        raise SystemExit(1)
