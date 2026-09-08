"""Process-wide coordination for non-blocking staged trip prefetch."""

from __future__ import annotations

import asyncio
import logging
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from uuid import UUID

from app.schemas import DiscoveryCategory
from app.services.city_place_prefetch_service import PrefetchStage, PrefetchSummary

logger = logging.getLogger(__name__)


class PrefetchStatus(str, Enum):
    IDLE = "idle"
    FETCHING = "fetching"
    PARTIALLY_READY = "partially_ready"
    READY = "ready"
    FAILED = "failed"


@dataclass
class PrefetchState:
    city_id: UUID
    city_name: str
    status: PrefetchStatus = PrefetchStatus.IDLE
    started_at: datetime | None = None
    last_updated: datetime | None = None
    completed_stages: set[str] = field(default_factory=set)
    categories_loaded: set[str] = field(default_factory=set)
    poi_count: int = 0
    failed_stages: set[str] = field(default_factory=set)


PrefetchRunner = Callable[[list[DiscoveryCategory]], Awaitable[PrefetchSummary]]


def _run_async_worker(
    runner: PrefetchRunner,
    categories: list[DiscoveryCategory],
) -> PrefetchSummary:
    """Run one async provider pipeline inside a worker thread's event loop."""

    return asyncio.run(runner(categories))


class ProgressivePrefetchCoordinator:
    """Enqueue city/category work once and expose coarse, UI-safe state."""

    def __init__(self) -> None:
        self._states: dict[UUID, PrefetchState] = {}
        self._tasks: dict[tuple[UUID, str], asyncio.Task[None]] = {}
        self._stage_tasks: set[asyncio.Task[None]] = set()

    def enqueue(
        self,
        *,
        city_id: UUID,
        city_name: str,
        stage: PrefetchStage,
        categories: list[DiscoveryCategory],
        runner: PrefetchRunner | None = None,
        offload: bool = False,
    ) -> tuple[PrefetchState, list[str], list[str]]:
        now = datetime.now(timezone.utc)
        state = self._states.setdefault(
            city_id, PrefetchState(city_id=city_id, city_name=city_name)
        )
        state.city_name = city_name
        state.last_updated = now

        if not categories or runner is None:
            state.completed_stages.add(stage.value)
            state.status = (
                PrefetchStatus.READY
                if PrefetchStage.INTERESTS_CONFIRMED.value in state.completed_stages
                else PrefetchStatus.PARTIALLY_READY
            )
            logger.info(
                "PREFETCH_COMPLETE city=%s stage=%s provider_work=false",
                city_name,
                stage.value,
            )
            return state, [], []

        enqueued: list[DiscoveryCategory] = []
        reused: list[str] = []
        reused_tasks: set[asyncio.Task[None]] = set()
        for category in dict.fromkeys(categories):
            key = (city_id, category.value)
            task = self._tasks.get(key)
            if task is not None and not task.done():
                reused.append(category.value)
                reused_tasks.add(task)
            else:
                enqueued.append(category)

        if enqueued:
            state.started_at = state.started_at or now
            state.status = PrefetchStatus.FETCHING
            task = asyncio.create_task(
                self._run(
                    state=state,
                    stage=stage,
                    categories=enqueued,
                    runner=runner,
                    dependencies=reused_tasks,
                    offload=offload,
                )
            )
            for category in enqueued:
                self._tasks[(city_id, category.value)] = task
            logger.info(
                "PREFETCH_STARTED city=%s stage=%s enqueued=%s reused=%s",
                city_name,
                stage.value,
                [category.value for category in enqueued],
                reused,
            )
        elif reused:
            stage_task = asyncio.create_task(
                self._complete_reused_stage(state, stage, reused_tasks)
            )
            self._stage_tasks.add(stage_task)
            stage_task.add_done_callback(self._stage_tasks.discard)
            logger.info(
                "PREFETCH_JOINED_INFLIGHT city=%s stage=%s categories=%s",
                city_name,
                stage.value,
                reused,
            )
        return state, [category.value for category in enqueued], reused

    async def _run(
        self,
        *,
        state: PrefetchState,
        stage: PrefetchStage,
        categories: list[DiscoveryCategory],
        runner: PrefetchRunner,
        dependencies: set[asyncio.Task[None]],
        offload: bool,
    ) -> None:
        try:
            summary = (
                await asyncio.to_thread(_run_async_worker, runner, categories)
                if offload
                else await runner(categories)
            )
            if dependencies:
                await asyncio.gather(*dependencies)
            state.categories_loaded.update(summary.categories_enriched)
            state.completed_stages.add(stage.value)
            state.failed_stages.discard(stage.value)
            state.poi_count = max(state.poi_count, summary.poi_count)
            state.status = (
                PrefetchStatus.READY
                if PrefetchStage.INTERESTS_CONFIRMED.value in state.completed_stages
                else PrefetchStatus.PARTIALLY_READY
            )
            if summary.error:
                state.failed_stages.add(stage.value)
                state.status = PrefetchStatus.PARTIALLY_READY
            logger.info(
                "PREFETCH_COMPLETE city=%s stage=%s poi_count=%d categories=%s",
                state.city_name,
                stage.value,
                state.poi_count,
                sorted(state.categories_loaded),
            )
        except Exception as exc:
            state.failed_stages.add(stage.value)
            state.status = (
                PrefetchStatus.PARTIALLY_READY
                if state.categories_loaded
                else PrefetchStatus.FAILED
            )
            logger.warning(
                "PREFETCH_FAILED city=%s stage=%s error=%s",
                state.city_name,
                stage.value,
                exc,
            )
        finally:
            state.last_updated = datetime.now(timezone.utc)
            current = asyncio.current_task()
            for category in categories:
                key = (state.city_id, category.value)
                if self._tasks.get(key) is current:
                    self._tasks.pop(key, None)

    async def _complete_reused_stage(
        self,
        state: PrefetchState,
        stage: PrefetchStage,
        dependencies: set[asyncio.Task[None]],
    ) -> None:
        await asyncio.gather(*dependencies)
        state.completed_stages.add(stage.value)
        state.status = (
            PrefetchStatus.READY
            if stage == PrefetchStage.INTERESTS_CONFIRMED
            else PrefetchStatus.PARTIALLY_READY
        )
        state.last_updated = datetime.now(timezone.utc)

    def get_state(self, city_id: UUID) -> PrefetchState | None:
        return self._states.get(city_id)

    async def wait_for_city(self, city_id: UUID) -> None:
        tasks = {
            task
            for (task_city_id, _), task in self._tasks.items()
            if task_city_id == city_id and not task.done()
        }
        if tasks:
            await asyncio.gather(*tasks)

    async def join_active(
        self,
        city_id: UUID,
        categories: list[DiscoveryCategory],
    ) -> list[str]:
        """Await matching active work and return the categories that were joined."""

        joined: list[str] = []
        tasks: set[asyncio.Task[None]] = set()
        for category in dict.fromkeys(categories):
            task = self._tasks.get((city_id, category.value))
            if task is not None and not task.done():
                joined.append(category.value)
                tasks.add(task)
        if tasks:
            logger.info(
                "PREFETCH_JOINED_INFLIGHT city_id=%s categories=%s",
                city_id,
                joined,
            )
            await asyncio.gather(*tasks)
        return joined
