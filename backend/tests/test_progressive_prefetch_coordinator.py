"""Staged background prefetch coordination tests."""

import asyncio
import threading
import time
from uuid import uuid4

import pytest

from app.schemas import DiscoveryCategory
from app.services.city_place_prefetch_service import PrefetchStage, PrefetchSummary
from app.services.progressive_prefetch_coordinator import (
    PrefetchStatus,
    ProgressivePrefetchCoordinator,
)


@pytest.mark.anyio
async def test_enqueue_returns_immediately_and_reuses_in_flight_pipeline() -> None:
    coordinator = ProgressivePrefetchCoordinator()
    city_id = uuid4()
    release = asyncio.Event()
    calls = 0

    async def runner(categories: list[DiscoveryCategory]) -> PrefetchSummary:
        nonlocal calls
        calls += 1
        await release.wait()
        return PrefetchSummary(
            city_id=city_id,
            city_name="Jaipur",
            stage=PrefetchStage.DESTINATION_CONFIRMED,
            categories_requested=[category.value for category in categories],
            categories_skipped_sufficient=[],
            categories_enriched=[category.value for category in categories],
            duplicate_refreshes_prevented=0,
            poi_count=42,
        )

    categories = [DiscoveryCategory.TOURISM, DiscoveryCategory.FOOD]
    state, enqueued, reused = coordinator.enqueue(
        city_id=city_id,
        city_name="Jaipur",
        stage=PrefetchStage.DESTINATION_CONFIRMED,
        categories=categories,
        runner=runner,
    )
    _, second_enqueued, second_reused = coordinator.enqueue(
        city_id=city_id,
        city_name="Jaipur",
        stage=PrefetchStage.DESTINATION_CONFIRMED,
        categories=categories,
        runner=runner,
    )

    assert state.status == PrefetchStatus.FETCHING
    assert enqueued == ["tourism", "food"]
    assert reused == []
    assert second_enqueued == []
    assert second_reused == ["tourism", "food"]
    await asyncio.sleep(0)
    assert calls == 1

    release.set()
    await coordinator.wait_for_city(city_id)
    completed = coordinator.get_state(city_id)
    assert completed is not None
    assert completed.status == PrefetchStatus.PARTIALLY_READY
    assert completed.poi_count == 42


@pytest.mark.anyio
async def test_city_state_is_isolated_and_failure_is_non_fatal() -> None:
    coordinator = ProgressivePrefetchCoordinator()
    jaipur_id = uuid4()
    udaipur_id = uuid4()

    async def failing(_: list[DiscoveryCategory]) -> PrefetchSummary:
        raise RuntimeError("provider unavailable")

    coordinator.enqueue(
        city_id=jaipur_id,
        city_name="Jaipur",
        stage=PrefetchStage.DESTINATION_CONFIRMED,
        categories=[DiscoveryCategory.HERITAGE],
        runner=failing,
    )
    udaipur, _, _ = coordinator.enqueue(
        city_id=udaipur_id,
        city_name="Udaipur",
        stage=PrefetchStage.DATES_CONFIRMED,
        categories=[],
    )
    await coordinator.wait_for_city(jaipur_id)

    jaipur = coordinator.get_state(jaipur_id)
    assert jaipur is not None
    assert jaipur.status == PrefetchStatus.FAILED
    assert jaipur.failed_stages == {"destination_confirmed"}
    assert udaipur.city_id == udaipur_id
    assert udaipur.completed_stages == {"dates_confirmed"}
    assert udaipur.categories_loaded == set()


@pytest.mark.anyio
async def test_offloaded_prefetch_does_not_block_request_event_loop() -> None:
    coordinator = ProgressivePrefetchCoordinator()
    city_id = uuid4()
    started = threading.Event()
    release = threading.Event()

    async def blocking_runner(
        categories: list[DiscoveryCategory],
    ) -> PrefetchSummary:
        started.set()
        release.wait(timeout=2)
        return PrefetchSummary(
            city_id=city_id,
            city_name="Jaisalmer",
            stage=PrefetchStage.DESTINATION_CONFIRMED,
            categories_requested=[category.value for category in categories],
            categories_skipped_sufficient=[],
            categories_enriched=[category.value for category in categories],
            duplicate_refreshes_prevented=0,
        )

    coordinator.enqueue(
        city_id=city_id,
        city_name="Jaisalmer",
        stage=PrefetchStage.DESTINATION_CONFIRMED,
        categories=[DiscoveryCategory.TOURISM],
        runner=blocking_runner,
        offload=True,
    )
    assert await asyncio.to_thread(started.wait, 1)

    before = time.monotonic()
    await asyncio.sleep(0.01)
    assert time.monotonic() - before < 0.25

    release.set()
    await coordinator.wait_for_city(city_id)


@pytest.mark.anyio
async def test_foreground_joins_matching_in_flight_prefetch() -> None:
    coordinator = ProgressivePrefetchCoordinator()
    city_id = uuid4()
    release = asyncio.Event()

    async def runner(categories: list[DiscoveryCategory]) -> PrefetchSummary:
        await release.wait()
        return PrefetchSummary(
            city_id=city_id,
            city_name="Jaipur",
            stage=PrefetchStage.DESTINATION_CONFIRMED,
            categories_requested=[category.value for category in categories],
            categories_skipped_sufficient=[],
            categories_enriched=[category.value for category in categories],
            duplicate_refreshes_prevented=0,
        )

    coordinator.enqueue(
        city_id=city_id,
        city_name="Jaipur",
        stage=PrefetchStage.DESTINATION_CONFIRMED,
        categories=[DiscoveryCategory.FOOD, DiscoveryCategory.TOURISM],
        runner=runner,
    )
    await asyncio.sleep(0)
    joined_task = asyncio.create_task(
        coordinator.join_active(city_id, [DiscoveryCategory.FOOD])
    )
    await asyncio.sleep(0)
    assert not joined_task.done()

    release.set()
    assert await joined_task == ["food"]
