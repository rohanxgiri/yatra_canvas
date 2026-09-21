"""Shared Wikimedia request serialization and durable 429 cooldowns."""

from __future__ import annotations

import asyncio
import logging
import random
import threading
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
from math import ceil
from urllib.parse import urlparse
from weakref import WeakKeyDictionary

import httpx
from sqlalchemy import case, update
from sqlalchemy.engine import Engine
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlmodel import Session, select

from app.core.request_context import get_request_id
from app.models import ProviderCooldown

logger = logging.getLogger(__name__)

WIKIMEDIA_PROVIDER_KEY = "wikimedia"
_DEFAULT_RETRY_AFTER_SECONDS = 5
_memory_lock = threading.Lock()
_memory_cooldowns: dict[str, datetime] = {}
_limiter_lock = threading.Lock()
_loop_limiters: WeakKeyDictionary = WeakKeyDictionary()


class WikimediaRateLimitedError(RuntimeError):
    """Raised without HTTP I/O while the shared Wikimedia cooldown is active."""

    def __init__(self, retry_after_seconds: int, cooldown_until: datetime) -> None:
        super().__init__(
            f"Wikimedia image requests are cooling down for "
            f"{retry_after_seconds} seconds."
        )
        self.retry_after_seconds = retry_after_seconds
        self.cooldown_until = cooldown_until


class WikimediaRateController:
    """Serialize Wikimedia calls per process and persist provider-wide backoff."""

    def __init__(self, engine: Engine) -> None:
        self._engine = engine

    async def get(
        self,
        client: httpx.AsyncClient,
        url: str,
        **kwargs,
    ) -> httpx.Response:
        """Issue one request with a shared gate and one bounded transient retry."""

        async with self._limiter():
            self._raise_if_cooling_down()
            for attempt in range(2):
                try:
                    response = await client.get(url, **kwargs)
                except (httpx.TimeoutException, httpx.NetworkError):
                    if attempt == 0:
                        await asyncio.sleep(self._retry_delay(attempt))
                        continue
                    raise

                if response.status_code == 429:
                    retry_after = self._parse_retry_after(
                        response.headers.get("Retry-After")
                    )
                    cooldown_until = datetime.now(timezone.utc) + timedelta(
                        seconds=retry_after
                    )
                    self._record_cooldown(
                        host=urlparse(url).hostname or "wikimedia.org",
                        cooldown_until=cooldown_until,
                        retry_after_seconds=retry_after,
                    )
                    raise WikimediaRateLimitedError(retry_after, cooldown_until)

                if response.status_code >= 500 and attempt == 0:
                    await asyncio.sleep(self._retry_delay(attempt))
                    continue

                response.raise_for_status()
                return response

        raise RuntimeError("Wikimedia request loop terminated unexpectedly.")

    def _raise_if_cooling_down(self) -> None:
        now = datetime.now(timezone.utc)
        cooldown_until = self._memory_cooldown()
        if cooldown_until is not None and cooldown_until > now:
            remaining = max(1, ceil((cooldown_until - now).total_seconds()))
            raise WikimediaRateLimitedError(remaining, cooldown_until)
        durable_until = self._durable_cooldown()
        if durable_until is not None and durable_until > now:
            cooldown_until = durable_until
            self._set_memory_cooldown(durable_until)
            remaining = max(1, ceil((cooldown_until - now).total_seconds()))
            raise WikimediaRateLimitedError(remaining, cooldown_until)

    def _durable_cooldown(self) -> datetime | None:
        try:
            with Session(self._engine) as session:
                row = session.exec(
                    select(ProviderCooldown).where(
                        ProviderCooldown.provider_key == WIKIMEDIA_PROVIDER_KEY
                    )
                ).first()
                return self._as_utc(row.cooldown_until) if row is not None else None
        except SQLAlchemyError as exc:
            logger.warning(
                "PROVIDER_COOLDOWN_READ_FAILED request_id=%s provider=%s error=%s",
                get_request_id(),
                WIKIMEDIA_PROVIDER_KEY,
                type(exc).__name__,
            )
            return None

    def _record_cooldown(
        self,
        *,
        host: str,
        cooldown_until: datetime,
        retry_after_seconds: int,
    ) -> None:
        self._set_memory_cooldown(cooldown_until)
        now = datetime.now(timezone.utc)
        statement = (
            update(ProviderCooldown)
            .where(ProviderCooldown.provider_key == WIKIMEDIA_PROVIDER_KEY)
            .values(
                host=host,
                cooldown_until=case(
                    (
                        ProviderCooldown.cooldown_until > cooldown_until,
                        ProviderCooldown.cooldown_until,
                    ),
                    else_=cooldown_until,
                ),
                reason="http_429",
                retry_after_seconds=case(
                    (
                        ProviderCooldown.cooldown_until > cooldown_until,
                        ProviderCooldown.retry_after_seconds,
                    ),
                    else_=retry_after_seconds,
                ),
                updated_at=now,
            )
        )
        try:
            with Session(self._engine) as session:
                result = session.exec(statement)
                if result.rowcount == 0:
                    session.add(
                        ProviderCooldown(
                            provider_key=WIKIMEDIA_PROVIDER_KEY,
                            host=host,
                            cooldown_until=cooldown_until,
                            reason="http_429",
                            retry_after_seconds=retry_after_seconds,
                            updated_at=now,
                        )
                    )
                try:
                    session.commit()
                except IntegrityError:
                    session.rollback()
                    session.exec(statement)
                    session.commit()
        except SQLAlchemyError as exc:
            logger.warning(
                "PROVIDER_COOLDOWN_WRITE_FAILED request_id=%s provider=%s host=%s error=%s",
                get_request_id(),
                WIKIMEDIA_PROVIDER_KEY,
                host,
                type(exc).__name__,
            )
        logger.warning(
            "PROVIDER_COOLDOWN_SET request_id=%s provider=%s host=%s retry_after_seconds=%d",
            get_request_id(),
            WIKIMEDIA_PROVIDER_KEY,
            host,
            retry_after_seconds,
        )

    @staticmethod
    def _parse_retry_after(value: str | None) -> int:
        if value:
            try:
                return max(1, ceil(float(value.strip())))
            except ValueError:
                try:
                    parsed = parsedate_to_datetime(value)
                    if parsed.tzinfo is None:
                        parsed = parsed.replace(tzinfo=timezone.utc)
                    return max(
                        1,
                        ceil(
                            (
                                parsed.astimezone(timezone.utc)
                                - datetime.now(timezone.utc)
                            ).total_seconds()
                        ),
                    )
                except (TypeError, ValueError, OverflowError):
                    pass
        return _DEFAULT_RETRY_AFTER_SECONDS

    @staticmethod
    def _retry_delay(attempt: int) -> float:
        return min(0.75, (0.2 * (2**attempt)) + random.uniform(0.0, 0.1))

    @staticmethod
    def _as_utc(value: datetime) -> datetime:
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)

    @staticmethod
    def _limiter() -> asyncio.Semaphore:
        loop = asyncio.get_running_loop()
        with _limiter_lock:
            per_loop = _loop_limiters.setdefault(loop, {})
            return per_loop.setdefault(WIKIMEDIA_PROVIDER_KEY, asyncio.Semaphore(1))

    @staticmethod
    def _memory_cooldown() -> datetime | None:
        with _memory_lock:
            return _memory_cooldowns.get(WIKIMEDIA_PROVIDER_KEY)

    @staticmethod
    def _set_memory_cooldown(cooldown_until: datetime) -> None:
        with _memory_lock:
            existing = _memory_cooldowns.get(WIKIMEDIA_PROVIDER_KEY)
            if existing is None or cooldown_until > existing:
                _memory_cooldowns[WIKIMEDIA_PROVIDER_KEY] = cooldown_until


def _reset_wikimedia_rate_state_for_tests() -> None:
    """Clear process-local state; durable rows intentionally remain untouched."""

    with _memory_lock:
        _memory_cooldowns.clear()
    with _limiter_lock:
        _loop_limiters.clear()
