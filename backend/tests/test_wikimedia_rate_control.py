from __future__ import annotations

import asyncio
from datetime import datetime, timezone
from uuid import uuid4

import httpx
import pytest
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.models import ProviderCooldown
from app.services.place_category_normalizer import NormalizedPlaceCategory
from app.services.place_image_provider import PlaceImageContext
from app.services.provider_rate_control import (
    WikimediaRateController,
    WikimediaRateLimitedError,
    _reset_wikimedia_rate_state_for_tests,
)
from app.services.wikimedia_image_provider import WikimediaImageProvider


def _engine():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)
    return engine


def _context(index: int) -> PlaceImageContext:
    return PlaceImageContext(
        place_id=uuid4(),
        name=f"Rate limited place {index}",
        raw_category="heritage",
        normalized_category=NormalizedPlaceCategory.LANDMARK,
        latitude=25.57,
        longitude=91.88,
        city="Shillong",
        state="Meghalaya",
        country="India",
        wikidata_id=None,
        sources=(),
    )


@pytest.fixture(autouse=True)
def reset_shared_rate_state():
    _reset_wikimedia_rate_state_for_tests()
    yield
    _reset_wikimedia_rate_state_for_tests()


@pytest.mark.anyio
async def test_sixty_ids_with_immediate_429_create_one_shared_cooldown() -> None:
    engine = _engine()
    request_count = 0

    def handler(_request: httpx.Request) -> httpx.Response:
        nonlocal request_count
        request_count += 1
        return httpx.Response(429, headers={"Retry-After": "120"})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        providers = [
            WikimediaImageProvider(
                client=client,
                rate_controller=WikimediaRateController(engine),
            )
            for _ in range(2)
        ]
        results = await asyncio.gather(
            *(
                providers[index % len(providers)].resolve(_context(index))
                for index in range(60)
            ),
            return_exceptions=True,
        )

    assert request_count == 1
    assert all(isinstance(result, WikimediaRateLimitedError) for result in results)
    with Session(engine) as session:
        cooldown = session.exec(
            select(ProviderCooldown).where(ProviderCooldown.provider_key == "wikimedia")
        ).one()
        remaining = cooldown.cooldown_until.replace(
            tzinfo=cooldown.cooldown_until.tzinfo or timezone.utc
        ) - datetime.now(timezone.utc)
        assert remaining.total_seconds() >= 115
        assert cooldown.retry_after_seconds == 120


@pytest.mark.anyio
async def test_new_batch_observes_durable_cooldown_without_http() -> None:
    engine = _engine()
    first_calls = 0

    def first_handler(_request: httpx.Request) -> httpx.Response:
        nonlocal first_calls
        first_calls += 1
        return httpx.Response(429, headers={"Retry-After": "90"})

    async with httpx.AsyncClient(
        transport=httpx.MockTransport(first_handler)
    ) as first_client:
        provider = WikimediaImageProvider(
            client=first_client,
            rate_controller=WikimediaRateController(engine),
        )
        with pytest.raises(WikimediaRateLimitedError):
            await provider.resolve(_context(1))

    assert first_calls == 1
    _reset_wikimedia_rate_state_for_tests()
    second_calls = 0

    def second_handler(_request: httpx.Request) -> httpx.Response:
        nonlocal second_calls
        second_calls += 1
        return httpx.Response(200, json={"query": {"pages": {}}})

    async with httpx.AsyncClient(
        transport=httpx.MockTransport(second_handler)
    ) as second_client:
        second_provider = WikimediaImageProvider(
            client=second_client,
            rate_controller=WikimediaRateController(engine),
        )
        with pytest.raises(WikimediaRateLimitedError):
            await second_provider.resolve(_context(2))

    assert second_calls == 0
