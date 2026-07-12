from __future__ import annotations

import argparse
import json
import os
import time
from pathlib import Path

import httpx


def timed(client: httpx.Client, method: str, url: str, **kwargs):
    started = time.perf_counter()
    response = client.request(method, url, **kwargs)
    elapsed_ms = round((time.perf_counter() - started) * 1000)
    return response, elapsed_ms


def main() -> None:
    parser = argparse.ArgumentParser(description="Verify the public Space API")
    parser.add_argument(
        "--url",
        default="https://episarenko-clothes-product-analyzer.hf.space",
    )
    parser.add_argument("--image", type=Path)
    args = parser.parse_args()
    base_url = args.url.rstrip("/")
    token = os.environ.get("SUPABASE_ACCESS_TOKEN")
    report: dict[str, object] = {"url": base_url}
    with httpx.Client(timeout=60, follow_redirects=True) as client:
        for endpoint in ("health", "ready"):
            response, elapsed = timed(client, "GET", f"{base_url}/{endpoint}")
            response.raise_for_status()
            report[endpoint] = {"status": response.status_code, "elapsed_ms": elapsed}
        if args.image:
            unauthorized, elapsed = timed(
                client,
                "POST",
                f"{base_url}/v1/analyze",
                files={"files": (args.image.name, args.image.read_bytes(), "image/jpeg")},
            )
            if unauthorized.status_code != 401:
                raise RuntimeError("Analysis endpoint is not JWT protected")
            report["analysis_without_jwt"] = {
                "status": unauthorized.status_code,
                "elapsed_ms": elapsed,
            }
            if token:
                response, elapsed = timed(
                    client,
                    "POST",
                    f"{base_url}/v1/visual-search",
                    headers={"Authorization": f"Bearer {token}"},
                    files={"file": (args.image.name, args.image.read_bytes(), "image/jpeg")},
                )
                response.raise_for_status()
                report["visual_search"] = {
                    "status": response.status_code,
                    "elapsed_ms": elapsed,
                    "products": len(response.json().get("products", [])),
                }
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
