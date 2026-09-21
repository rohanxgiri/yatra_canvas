"""Request correlation regressions for HTTP and background Discover work."""

from __future__ import annotations

import asyncio
import logging
import re
import threading
from uuid import uuid4

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine

from app.core.request_context import RequestIdMiddleware, get_request_id
from app.models import City
from app.schemas import DiscoveryCategory
from app.services import place_image_service
from app.services.city_place_prefetch_service import PrefetchStage
from app.services.durable_place_refresh_service import DurablePlaceRefreshService


def _correlation_app() -> FastAPI:
    test_app = FastAPI()
    test_app.add_middleware(RequestIdMiddleware)

    @test_app.get("/context")
    async def context() -> dict[str, str | None]:
        await asyncio.sleep(0)
        return {"request_id": get_request_id()}

    return test_app


@pytest.mark.anyio
async def test_incoming_request_id_is_retained_and_returned() -> None:
    async with AsyncClient(
        transport=ASGITransport(app=_correlation_app()),
        base_url="http://test",
    ) as client:
        response = await client.get(
            "/context",
            headers={"X-Request-ID": "trip-flow_123:discover"},
        )

    assert response.status_code == 200
    assert response.headers["X-Request-ID"] == "trip-flow_123:discover"
    assert response.json()["request_id"] == "trip-flow_123:discover"


@pytest.mark.anyio
async def test_missing_or_unsafe_request_id_is_replaced() -> None:
    async with AsyncClient(
        transport=ASGITransport(app=_correlation_app()),
        base_url="http://test",
    ) as client:
        missing = await client.get("/context")
        unsafe = await client.get(
            "/context",
            headers={"X-Request-ID": "secret value\nnot-safe"},
        )

    pattern = re.compile(r"^[0-9a-f-]{36}$")
    assert pattern.fullmatch(missing.headers["X-Request-ID"])
    assert pattern.fullmatch(unsafe.headers["X-Request-ID"])
    assert unsafe.headers["X-Request-ID"] != "secret value\nnot-safe"


@pytest.mark.anyio
async def test_concurrent_requests_keep_separate_context() -> None:
    async with AsyncClient(
        transport=ASGITransport(app=_correlation_app()),
        base_url="http://test",
    ) as client:
        first, second = await asyncio.gather(
            client.get("/context", headers={"X-Request-ID": "flow-a"}),
            client.get("/context", headers={"X-Request-ID": "flow-b"}),
        )

    assert first.json()["request_id"] == "flow-a"
    assert second.json()["request_id"] == "flow-b"
    assert first.headers["X-Request-ID"] == "flow-a"
    assert second.headers["X-Request-ID"] == "flow-b"
    assert get_request_id() is None


@pytest.mark.anyio
async def test_request_logging_does_not_emit_secret_headers(caplog) -> None:
    secret = "Bearer do-not-log-this-token"
    caplog.set_level(logging.INFO, logger="app.core.request_context")

    async with AsyncClient(
        transport=ASGITransport(app=_correlation_app()),
        base_url="http://test",
    ) as client:
        response = await client.get(
            "/context",
            headers={
                "X-Request-ID": "safe-flow-id",
                "Authorization": secret,
            },
        )

    assert response.status_code == 200
    assert "request_id=safe-flow-id" in caplog.text
    assert secret not in caplog.text


@pytest.mark.anyio
async def test_background_refresh_receives_request_correlation() -> None:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)
    city_id = uuid4()
    with Session(engine) as session:
        session.add(
            City(
                id=city_id,
                name="Shillong",
                state="Meghalaya",
                country="India",
                latitude=25.5788,
                longitude=91.8933,
            )
        )
        session.commit()

    observed: list[str | None] = []
    completed = threading.Event()

    async def refresh(_session, _city, _category, _stage) -> None:
        observed.append(get_request_id())
        completed.set()

    service = DurablePlaceRefreshService(
        engine=engine,
        category_refresher=refresh,
        worker_id="correlation-worker",
    )
    service.request_refresh(
        city_id=city_id,
        categories=[DiscoveryCategory.HERITAGE],
        stage=PrefetchStage.INTERESTS_CONFIRMED,
        correlation_id="refresh-flow-123",
    )

    assert await asyncio.to_thread(completed.wait, 2)
    assert observed == ["refresh-flow-123"]
    engine.dispose()


@pytest.mark.anyio
async def test_background_image_job_receives_request_correlation(
    monkeypatch,
) -> None:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    observed: list[str | None] = []
    completed = asyncio.Event()

    async def resolve_many(_self, _session, _place_ids):
        observed.append(get_request_id())
        completed.set()
        return {}

    monkeypatch.setattr(
        place_image_service.PlaceImageResolver,
        "resolve_many",
        resolve_many,
    )
    place_image_service.schedule_place_image_enrichment(
        [uuid4()],
        engine=engine,
        correlation_id="image-flow-123",
    )

    await asyncio.wait_for(completed.wait(), timeout=2)
    assert observed == ["image-flow-123"]
    engine.dispose()
