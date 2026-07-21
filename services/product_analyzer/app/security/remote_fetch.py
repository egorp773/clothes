from __future__ import annotations

import ipaddress
import socket
from collections.abc import Callable, Iterable
from urllib.parse import urljoin, urlsplit, urlunsplit

import httpx


class RemoteFetchError(ValueError):
    """Raised when a remote resource violates the analyzer egress policy."""


Resolver = Callable[..., list[tuple]]

_REDIRECT_STATUSES = {301, 302, 303, 307, 308}
_METADATA_HOSTS = {
    "metadata",
    "metadata.google.internal",
    "metadata.goog",
    "instance-data",
}


def parse_allowed_hosts(raw: str | None, *, supabase_url: str | None = None) -> set[str]:
    hosts = {
        _normalize_hostname(value)
        for value in (raw or "").split(",")
        if value.strip()
    }
    if supabase_url:
        hostname = urlsplit(supabase_url).hostname
        if hostname:
            hosts.add(_normalize_hostname(hostname))
    return hosts


def validate_remote_url(
    url: str,
    *,
    allowed_hosts: set[str] | None = None,
    allow_http: bool = False,
    resolver: Resolver | None = None,
) -> str:
    """Validate a URL and every currently resolved address before connecting.

    The caller must repeat this check for every redirect. A host allowlist is
    strongly recommended and is enabled by the analyzer configuration for
    Supabase-hosted product media.
    """

    try:
        parsed = urlsplit(url)
        port = parsed.port
    except ValueError as error:
        raise RemoteFetchError("Remote image URL is invalid") from error

    allowed_schemes = {"https"}
    if allow_http:
        allowed_schemes.add("http")
    if parsed.scheme.lower() not in allowed_schemes:
        raise RemoteFetchError("Remote image URL must use HTTPS")
    if not parsed.hostname:
        raise RemoteFetchError("Remote image URL has no hostname")
    if parsed.username is not None or parsed.password is not None:
        raise RemoteFetchError("Remote image URL must not contain credentials")
    if parsed.fragment:
        raise RemoteFetchError("Remote image URL must not contain a fragment")

    hostname = _normalize_hostname(parsed.hostname)
    if hostname in _METADATA_HOSTS or hostname.endswith(".localhost"):
        raise RemoteFetchError("Remote image hostname is forbidden")
    if allowed_hosts and hostname not in allowed_hosts:
        raise RemoteFetchError("Remote image hostname is not allowlisted")

    effective_port = port or (443 if parsed.scheme.lower() == "https" else 80)
    active_resolver = resolver or socket.getaddrinfo
    try:
        addresses = active_resolver(
            hostname,
            effective_port,
            family=socket.AF_UNSPEC,
            type=socket.SOCK_STREAM,
        )
    except (OSError, socket.gaierror) as error:
        raise RemoteFetchError("Remote image hostname could not be resolved") from error
    if not addresses:
        raise RemoteFetchError("Remote image hostname has no addresses")

    for address_info in addresses:
        sockaddr = address_info[4]
        if not sockaddr:
            raise RemoteFetchError("Remote image hostname resolved incorrectly")
        raw_address = str(sockaddr[0]).split("%", 1)[0]
        try:
            address = ipaddress.ip_address(raw_address)
        except ValueError as error:
            raise RemoteFetchError("Remote image hostname resolved incorrectly") from error
        if _is_forbidden_address(address):
            raise RemoteFetchError("Remote image hostname resolves to a forbidden network")

    netloc = hostname
    if ":" in hostname:
        netloc = f"[{hostname}]"
    if port is not None:
        netloc = f"{netloc}:{port}"
    return urlunsplit(
        (
            parsed.scheme.lower(),
            netloc,
            parsed.path or "/",
            parsed.query,
            "",
        )
    )


def download_limited(
    client: httpx.Client,
    url: str,
    *,
    max_bytes: int,
    accepted_content_types: Iterable[str],
    allowed_hosts: set[str] | None = None,
    allow_http: bool = False,
    max_redirects: int = 2,
) -> tuple[bytes, str, str]:
    """Download a bounded response after validating DNS and each redirect."""

    if max_bytes <= 0:
        raise RemoteFetchError("Remote image byte limit is invalid")
    accepted = {value.lower() for value in accepted_content_types}
    current = validate_remote_url(
        url,
        allowed_hosts=allowed_hosts,
        allow_http=allow_http,
    )

    for redirect_count in range(max(0, max_redirects) + 1):
        with client.stream(
            "GET",
            current,
            headers={"Accept": ", ".join(sorted(accepted))},
            follow_redirects=False,
        ) as response:
            if response.status_code in _REDIRECT_STATUSES:
                location = response.headers.get("location")
                if not location:
                    raise RemoteFetchError("Remote image redirect has no location")
                if redirect_count >= max_redirects:
                    raise RemoteFetchError("Remote image has too many redirects")
                current = validate_remote_url(
                    urljoin(current, location),
                    allowed_hosts=allowed_hosts,
                    allow_http=allow_http,
                )
                continue

            try:
                response.raise_for_status()
            except httpx.HTTPStatusError as error:
                raise RemoteFetchError(
                    f"Remote image returned HTTP {response.status_code}"
                ) from error

            content_type = (
                response.headers.get("content-type", "")
                .split(";", 1)[0]
                .strip()
                .lower()
            )
            if content_type not in accepted:
                raise RemoteFetchError(
                    f"Unsupported remote image MIME: {content_type or 'missing'}"
                )
            try:
                advertised_size = int(response.headers.get("content-length") or 0)
            except ValueError as error:
                raise RemoteFetchError("Remote image Content-Length is invalid") from error
            if advertised_size < 0 or advertised_size > max_bytes:
                raise RemoteFetchError("Remote image is too large")

            chunks: list[bytes] = []
            received = 0
            for chunk in response.iter_bytes():
                received += len(chunk)
                if received > max_bytes:
                    raise RemoteFetchError("Remote image is too large")
                chunks.append(chunk)
            return b"".join(chunks), content_type, current

    raise RemoteFetchError("Remote image redirect validation failed")


def _normalize_hostname(value: str) -> str:
    hostname = value.strip().rstrip(".").lower()
    if not hostname:
        raise RemoteFetchError("Remote image hostname is empty")
    try:
        return hostname.encode("idna").decode("ascii")
    except UnicodeError as error:
        raise RemoteFetchError("Remote image hostname is invalid") from error


def _is_forbidden_address(address: ipaddress.IPv4Address | ipaddress.IPv6Address) -> bool:
    if isinstance(address, ipaddress.IPv6Address) and address.ipv4_mapped:
        return _is_forbidden_address(address.ipv4_mapped)
    return (
        address.is_private
        or address.is_loopback
        or address.is_link_local
        or address.is_multicast
        or address.is_reserved
        or address.is_unspecified
        or not address.is_global
    )
