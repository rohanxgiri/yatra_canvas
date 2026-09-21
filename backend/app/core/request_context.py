"""Safe request correlation shared by HTTP handlers and background work."""

from __future__ import annotations

import logging
import re
import time
from collections.abc import Iterator
from contextlib import contextmanager
from contextvars import ContextVar, Token
from uuid import uuid4

from starlette.datastructures import Headers, MutableHeaders
from starlette.types import ASGIApp, Message, Receive, Scope, Send

logger = logging.getLogger(__name__)

REQUEST_ID_HEADER = "X-Request-ID"
_MAX_REQUEST_ID_LENGTH = 128
_SAFE_REQUEST_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
_request_id: ContextVar[str | None] = ContextVar("request_id", default=None)


def sanitize_request_id(value: str | None) -> str | None:
    """Return a safe opaque ID, never arbitrary header content."""

    if value is None:
        return None
    candidate = value.strip()
    if not candidate or len(candidate) > _MAX_REQUEST_ID_LENGTH:
        return None
    return candidate if _SAFE_REQUEST_ID.fullmatch(candidate) else None


def new_request_id() -> str:
    return str(uuid4())


def get_request_id() -> str | None:
    return _request_id.get()


def resolve_request_id(value: str | None = None) -> str:
    """Prefer an explicit safe ID, then current context, then generate one."""

    return sanitize_request_id(value) or get_request_id() or new_request_id()


@contextmanager
def request_id_scope(value: str | None = None) -> Iterator[str]:
    request_id = resolve_request_id(value)
    token: Token[str | None] = _request_id.set(request_id)
    try:
        yield request_id
    finally:
        _request_id.reset(token)


class RequestIdMiddleware:
    """Bind one sanitized correlation ID to each HTTP request and response."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(
        self,
        scope: Scope,
        receive: Receive,
        send: Send,
    ) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        headers = Headers(scope=scope)
        request_id = resolve_request_id(headers.get(REQUEST_ID_HEADER))
        token = _request_id.set(request_id)
        started = time.monotonic()
        status_code = 500

        async def send_with_request_id(message: Message) -> None:
            nonlocal status_code
            if message["type"] == "http.response.start":
                status_code = int(message["status"])
                response_headers = MutableHeaders(scope=message)
                response_headers[REQUEST_ID_HEADER] = request_id
            await send(message)

        try:
            await self.app(scope, receive, send_with_request_id)
        finally:
            logger.info(
                "HTTP_REQUEST request_id=%s method=%s path=%s status=%d elapsed_ms=%.1f",
                request_id,
                scope.get("method", ""),
                scope.get("path", ""),
                status_code,
                (time.monotonic() - started) * 1000,
            )
            _request_id.reset(token)
