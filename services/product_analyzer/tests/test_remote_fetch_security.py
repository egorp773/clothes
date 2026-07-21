import socket

import httpx
import pytest

from app.security import remote_fetch
from app.security.remote_fetch import (
    RemoteFetchError,
    download_limited,
    validate_remote_url,
)


def _resolved(address: str):
    family = socket.AF_INET6 if ":" in address else socket.AF_INET
    return [(family, socket.SOCK_STREAM, 6, "", (address, 443))]


@pytest.mark.parametrize(
    "address",
    [
        "127.0.0.1",
        "10.0.0.1",
        "169.254.169.254",
        "224.0.0.1",
        "192.0.2.1",
        "::1",
        "fe80::1",
    ],
)
def test_remote_fetch_rejects_non_global_addresses(address):
    with pytest.raises(RemoteFetchError, match="forbidden network"):
        validate_remote_url(
            "https://images.example.test/file.jpg",
            resolver=lambda *args, **kwargs: _resolved(address),
        )


def test_remote_fetch_enforces_exact_host_allowlist():
    with pytest.raises(RemoteFetchError, match="not allowlisted"):
        validate_remote_url(
            "https://attacker.example/file.jpg",
            allowed_hosts={"storage.example"},
            resolver=lambda *args, **kwargs: _resolved("93.184.216.34"),
        )


def test_remote_fetch_revalidates_redirect_target(monkeypatch):
    def resolver(host, *args, **kwargs):
        if host == "images.example":
            return _resolved("93.184.216.34")
        return _resolved("127.0.0.1")

    monkeypatch.setattr(remote_fetch.socket, "getaddrinfo", resolver)

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            302,
            headers={"Location": "http://169.254.169.254/latest/meta-data"},
            request=request,
        )

    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(RemoteFetchError):
            download_limited(
                client,
                "https://images.example/start",
                max_bytes=1024,
                accepted_content_types={"image/jpeg"},
                allow_http=True,
            )


def test_remote_fetch_stops_stream_over_limit(monkeypatch):
    monkeypatch.setattr(
        remote_fetch.socket,
        "getaddrinfo",
        lambda *args, **kwargs: _resolved("93.184.216.34"),
    )

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"Content-Type": "image/png"},
            content=b"x" * 9,
            request=request,
        )

    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(RemoteFetchError, match="too large"):
            download_limited(
                client,
                "https://images.example/file.png",
                max_bytes=8,
                accepted_content_types={"image/png"},
            )
