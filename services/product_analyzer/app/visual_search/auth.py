from __future__ import annotations

import threading
import time
from collections import defaultdict, deque

import httpx

from app.config import Settings
from app.visual_search.schemas import AuthenticatedUser


class AuthenticationError(RuntimeError):
    pass


class SupabaseJwtVerifier:
    def __init__(self, settings: Settings) -> None:
        self._url = settings.supabase_url.rstrip("/") if settings.supabase_url else None
        self._key = settings.supabase_service_role_key
        self._client = httpx.Client(timeout=httpx.Timeout(4.0, connect=2.0))

    def verify(self, authorization: str | None) -> AuthenticatedUser:
        if not authorization or not authorization.lower().startswith("bearer "):
            raise AuthenticationError("Missing Supabase bearer token")
        if not self._url or not self._key:
            raise AuthenticationError("Supabase authentication is not configured")
        token = authorization.split(" ", 1)[1].strip()
        try:
            response = self._client.get(
                f"{self._url}/auth/v1/user",
                headers={"apikey": self._key, "Authorization": f"Bearer {token}"},
            )
        except httpx.HTTPError as error:
            raise AuthenticationError("Supabase authentication is unavailable") from error
        if response.status_code != 200:
            raise AuthenticationError("Invalid or expired Supabase token")
        payload = response.json()
        user_id = payload.get("id")
        if not user_id:
            raise AuthenticationError("Supabase token has no user id")
        return AuthenticatedUser(id=str(user_id), raw=payload)

    def close(self) -> None:
        self._client.close()


class SlidingWindowRateLimiter:
    def __init__(self, limit: int, window_seconds: int) -> None:
        self.limit = max(1, limit)
        self.window_seconds = max(1, window_seconds)
        self._events: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def allow(self, key: str) -> bool:
        now = time.monotonic()
        cutoff = now - self.window_seconds
        with self._lock:
            events = self._events[key]
            while events and events[0] < cutoff:
                events.popleft()
            if len(events) >= self.limit:
                return False
            events.append(now)
            return True
