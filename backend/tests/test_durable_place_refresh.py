"""Durable, cross-worker category refresh coordination regressions."""

from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.models import City, CityCategoryCache, Place, PlaceRefreshJob, PlaceTag
from app.schemas import DiscoveryCategory
from app.services.city_place_prefetch_service import PrefetchStage
from app.services.durable_place_refresh_service import (
    DurablePlaceRefreshService,
    RefreshJobState,
)


@pytest.fixture
def refresh_db():
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
    yield engine, city_id
    SQLModel.metadata.drop_all(engine)
    engine.dispose()


def _job(engine, city_id, category: DiscoveryCategory) -> PlaceRefreshJob:
    with Session(engine) as session:
        row = session.exec(
            select(PlaceRefreshJob).where(
                PlaceRefreshJob.city_id == city_id,
                PlaceRefreshJob.versioned_category == category.value,
            )
        ).one()
        session.expunge(row)
        return row


@pytest.mark.anyio
async def test_same_city_category_executes_provider_once_across_workers(
    refresh_db,
) -> None:
    engine, city_id = refresh_db
    calls: list[DiscoveryCategory] = []
    entered = asyncio.Event()
    release = asyncio.Event()

    async def refresh(_session, _city, category, _stage):
        calls.append(category)
        entered.set()
        await release.wait()

    worker_a = DurablePlaceRefreshService(
        engine=engine,
        category_refresher=refresh,
        worker_id="worker-a",
    )
    worker_b = DurablePlaceRefreshService(
        engine=engine,
        category_refresher=refresh,
        worker_id="worker-b",
    )
    worker_a.request_refresh(
        city_id=city_id,
        categories=[DiscoveryCategory.CAFES],
        stage=PrefetchStage.INTERESTS_CONFIRMED,
        schedule=False,
    )

    first = asyncio.create_task(
        worker_a.execute_job(
            city_id=city_id,
            category=DiscoveryCategory.CAFES,
            stage=PrefetchStage.INTERESTS_CONFIRMED,
        )
    )
    await entered.wait()
    second = asyncio.create_task(
        worker_b.execute_job(
            city_id=city_id,
            category=DiscoveryCategory.CAFES,
            stage=PrefetchStage.INTERESTS_CONFIRMED,
        )
    )
    await asyncio.sleep(0)
    release.set()

    assert await first is True
    assert await second is False
    assert calls == [DiscoveryCategory.CAFES]
    assert (
        _job(engine, city_id, DiscoveryCategory.CAFES).state
        == RefreshJobState.COMPLETED
    )


@pytest.mark.anyio
async def test_overlapping_category_sets_coalesce_per_category(refresh_db) -> None:
    engine, city_id = refresh_db
    calls: list[DiscoveryCategory] = []

    async def refresh(_session, _city, category, _stage):
        calls.append(category)

    worker_a = DurablePlaceRefreshService(
        engine=engine,
        category_refresher=refresh,
        worker_id="worker-a",
    )
    worker_b = DurablePlaceRefreshService(
        engine=engine,
        category_refresher=refresh,
        worker_id="worker-b",
    )
    first = worker_a.request_refresh(
        city_id=city_id,
        categories=[DiscoveryCategory.FOOD, DiscoveryCategory.CAFES],
        stage=PrefetchStage.INTERESTS_CONFIRMED,
        schedule=False,
    )
    second = worker_b.request_refresh(
        city_id=city_id,
        categories=[DiscoveryCategory.CAFES, DiscoveryCategory.MARKETS],
        stage=PrefetchStage.INTERESTS_CONFIRMED,
        schedule=False,
    )

    assert set(first.queued_categories) == {"food", "cafes"}
    assert second.reused_categories == ["cafes"]
    assert second.queued_categories == ["markets"]

    await asyncio.gather(
        worker_a.execute_job(
            city_id=city_id,
            category=DiscoveryCategory.FOOD,
            stage=PrefetchStage.INTERESTS_CONFIRMED,
        ),
        worker_a.execute_job(
            city_id=city_id,
            category=DiscoveryCategory.CAFES,
            stage=PrefetchStage.INTERESTS_CONFIRMED,
        ),
        worker_b.execute_job(
            city_id=city_id,
            category=DiscoveryCategory.CAFES,
            stage=PrefetchStage.INTERESTS_CONFIRMED,
        ),
        worker_b.execute_job(
            city_id=city_id,
            category=DiscoveryCategory.MARKETS,
            stage=PrefetchStage.INTERESTS_CONFIRMED,
        ),
    )

    assert calls.count(DiscoveryCategory.FOOD) == 1
    assert calls.count(DiscoveryCategory.CAFES) == 1
    assert calls.count(DiscoveryCategory.MARKETS) == 1


@pytest.mark.anyio
async def test_active_lease_is_observed_without_waiting(refresh_db) -> None:
    engine, city_id = refresh_db
    calls = 0

    async def refresh(*_args):
        nonlocal calls
        calls += 1

    service = DurablePlaceRefreshService(
        engine=engine,
        category_refresher=refresh,
        worker_id="observer",
    )
    service.request_refresh(
        city_id=city_id,
        categories=[DiscoveryCategory.NATURE],
        stage=PrefetchStage.INTERESTS_CONFIRMED,
        schedule=False,
    )
    with Session(engine) as session:
        row = session.exec(select(PlaceRefreshJob)).one()
        row.state = RefreshJobState.RUNNING
        row.lease_owner = "other-worker"
        row.lease_expires_at = datetime.now(timezone.utc) + timedelta(minutes=5)
        session.add(row)
        session.commit()

    result = service.request_refresh(
        city_id=city_id,
        categories=[DiscoveryCategory.NATURE],
        stage=PrefetchStage.INTERESTS_CONFIRMED,
        schedule=False,
    )

    assert result.state == "refreshing"
    assert result.reused_categories == ["nature"]
    assert calls == 0


@pytest.mark.anyio
async def test_expired_lease_can_be_recovered(refresh_db) -> None:
    engine, city_id = refresh_db
    calls: list[DiscoveryCategory] = []

    async def refresh(_session, _city, category, _stage):
        calls.append(category)

    service = DurablePlaceRefreshService(
        engine=engine,
        category_refresher=refresh,
        worker_id="recovery-worker",
    )
    service.request_refresh(
        city_id=city_id,
        categories=[DiscoveryCategory.HERITAGE],
        stage=PrefetchStage.INTERESTS_CONFIRMED,
        schedule=False,
    )
    with Session(engine) as session:
        row = session.exec(select(PlaceRefreshJob)).one()
        row.state = RefreshJobState.RUNNING
        row.lease_owner = "crashed-worker"
        row.lease_expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
        session.add(row)
        session.commit()

    acquired = await service.execute_job(
        city_id=city_id,
        category=DiscoveryCategory.HERITAGE,
        stage=PrefetchStage.INTERESTS_CONFIRMED,
    )

    assert acquired is True
    assert calls == [DiscoveryCategory.HERITAGE]
    row = _job(engine, city_id, DiscoveryCategory.HERITAGE)
    assert row.state == RefreshJobState.COMPLETED
    assert row.attempt_count == 1


@pytest.mark.anyio
async def test_provider_failure_records_error_and_keeps_stored_places(
    refresh_db,
) -> None:
    engine, city_id = refresh_db
    with Session(engine) as session:
        place = Place(
            city_id=city_id,
            name="Old but useful market",
            category="markets",
            latitude=25.58,
            longitude=91.89,
        )
        session.add(place)
        session.flush()
        session.add(PlaceTag(place_id=place.id, tag="markets"))
        session.commit()

    async def refresh(*_args):
        raise RuntimeError("all providers unavailable")

    service = DurablePlaceRefreshService(
        engine=engine,
        category_refresher=refresh,
        worker_id="failure-worker",
    )
    service.request_refresh(
        city_id=city_id,
        categories=[DiscoveryCategory.MARKETS],
        stage=PrefetchStage.INTERESTS_CONFIRMED,
        schedule=False,
    )

    assert (
        await service.execute_job(
            city_id=city_id,
            category=DiscoveryCategory.MARKETS,
            stage=PrefetchStage.INTERESTS_CONFIRMED,
        )
        is True
    )
    row = _job(engine, city_id, DiscoveryCategory.MARKETS)
    assert row.state == RefreshJobState.FAILED
    assert row.last_error == "RuntimeError"
    with Session(engine) as session:
        assert session.exec(
            select(Place).where(Place.city_id == city_id)
        ).one().name == ("Old but useful market")


@pytest.mark.anyio
async def test_successful_refresh_completes_job_and_updates_freshness(
    refresh_db,
) -> None:
    engine, city_id = refresh_db
    old_time = datetime.now(timezone.utc) - timedelta(days=10)
    with Session(engine) as session:
        session.add(
            CityCategoryCache(
                city_id=city_id,
                category="religious",
                last_fetched_at=old_time,
                expires_at=old_time + timedelta(days=1),
            )
        )
        session.commit()

    async def refresh(session, city, category, _stage):
        row = session.exec(
            select(CityCategoryCache).where(
                CityCategoryCache.city_id == city.id,
                CityCategoryCache.category == category.value,
            )
        ).one()
        now = datetime.now(timezone.utc)
        row.last_fetched_at = now
        row.expires_at = now + timedelta(days=1)
        session.add(row)
        session.commit()

    service = DurablePlaceRefreshService(
        engine=engine,
        category_refresher=refresh,
        worker_id="success-worker",
    )
    service.request_refresh(
        city_id=city_id,
        categories=[DiscoveryCategory.RELIGIOUS],
        stage=PrefetchStage.INTERESTS_CONFIRMED,
        schedule=False,
    )

    assert (
        await service.execute_job(
            city_id=city_id,
            category=DiscoveryCategory.RELIGIOUS,
            stage=PrefetchStage.INTERESTS_CONFIRMED,
        )
        is True
    )
    job = _job(engine, city_id, DiscoveryCategory.RELIGIOUS)
    assert job.state == RefreshJobState.COMPLETED
    assert job.last_completed_at is not None
    with Session(engine) as session:
        cache = session.exec(select(CityCategoryCache)).one()
        assert cache.last_fetched_at.replace(tzinfo=timezone.utc) > old_time
