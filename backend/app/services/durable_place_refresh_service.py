"""Durable per-city/category provider refresh jobs with expiring leases."""

from __future__ import annotations

import asyncio
import logging
import os
import socket
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from enum import Enum
from uuid import UUID, uuid4

from sqlalchemy import and_, or_, update
from sqlalchemy.engine import Engine
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.core.request_context import request_id_scope, resolve_request_id
from app.models import City, PlaceRefreshJob
from app.schemas import DiscoveryCategory
from app.services.city_place_prefetch_service import (
    CityPlacePrefetchService,
    PrefetchStage,
)
from app.services.openstreetmap_discovery_service import OpenStreetMapDiscoveryService

logger = logging.getLogger(__name__)


class RefreshJobState(str, Enum):
    QUEUED = "queued"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"


CategoryRefresher = Callable[
    [Session, City, DiscoveryCategory, PrefetchStage], Awaitable[None]
]


@dataclass(frozen=True, slots=True)
class RefreshEnqueueResult:
    state: str
    queued_categories: list[str]
    reused_categories: list[str]


_background_tasks: set[asyncio.Task[bool]] = set()


class DurablePlaceRefreshService:
    """Queue and execute refreshes under an atomic database lease."""

    def __init__(
        self,
        *,
        engine: Engine,
        discovery: OpenStreetMapDiscoveryService | None = None,
        category_refresher: CategoryRefresher | None = None,
        worker_id: str | None = None,
        lease_duration: timedelta = timedelta(minutes=5),
    ) -> None:
        if discovery is None and category_refresher is None:
            raise ValueError("A discovery service or category refresher is required.")
        self._engine = engine
        self._discovery = discovery
        self._category_refresher = category_refresher or self._refresh_category
        self._worker_id = worker_id or (
            f"{socket.gethostname()}:{os.getpid()}:{uuid4().hex[:8]}"
        )
        self._lease_duration = lease_duration

    def request_refresh(
        self,
        *,
        city_id: UUID,
        categories: list[DiscoveryCategory],
        stage: PrefetchStage,
        schedule: bool = True,
        correlation_id: str | None = None,
    ) -> RefreshEnqueueResult:
        """Persist refresh intent and optionally dispatch non-blocking workers."""

        request_id = resolve_request_id(correlation_id)
        queued: list[str] = []
        reused: list[str] = []
        schedule_categories: list[DiscoveryCategory] = []
        any_active = False
        now = datetime.now(timezone.utc)

        for category in dict.fromkeys(categories):
            key = self._category_key(category)
            with Session(self._engine) as session:
                job = session.exec(
                    select(PlaceRefreshJob).where(
                        PlaceRefreshJob.city_id == city_id,
                        PlaceRefreshJob.versioned_category == key,
                    )
                ).first()
                if job is None:
                    job = PlaceRefreshJob(
                        city_id=city_id,
                        versioned_category=key,
                        state=RefreshJobState.QUEUED.value,
                        updated_at=now,
                    )
                    session.add(job)
                    try:
                        session.commit()
                        queued.append(category.value)
                    except IntegrityError:
                        session.rollback()
                        reused.append(category.value)
                    schedule_categories.append(category)
                    continue

                lease_expires_at = self._as_utc(job.lease_expires_at)
                active = (
                    job.state == RefreshJobState.RUNNING.value
                    and lease_expires_at is not None
                    and lease_expires_at > now
                )
                if active or job.state == RefreshJobState.QUEUED.value:
                    reused.append(category.value)
                    any_active = any_active or active
                    if not active:
                        schedule_categories.append(category)
                    continue

                job.state = RefreshJobState.QUEUED.value
                job.lease_owner = None
                job.lease_expires_at = None
                job.last_error = None
                job.updated_at = now
                session.add(job)
                session.commit()
                queued.append(category.value)
                schedule_categories.append(category)

        if schedule:
            for category in schedule_categories:
                task = asyncio.create_task(
                    asyncio.to_thread(
                        self._execute_job_in_thread,
                        city_id,
                        category,
                        stage,
                        request_id,
                    )
                )
                _background_tasks.add(task)
                task.add_done_callback(_background_tasks.discard)

        result = RefreshEnqueueResult(
            state="refreshing" if any_active and not queued else "queued",
            queued_categories=queued,
            reused_categories=reused,
        )
        logger.info(
            "PLACE_REFRESH_ENQUEUE request_id=%s city_id=%s refresh_state=%s "
            "queued=%s reused=%s",
            request_id,
            city_id,
            result.state,
            queued,
            reused,
        )
        return result

    def get_city_jobs(self, city_id: UUID) -> list[PlaceRefreshJob]:
        """Return detached durable refresh state for API observation."""

        with Session(self._engine) as session:
            rows = list(
                session.exec(
                    select(PlaceRefreshJob)
                    .where(PlaceRefreshJob.city_id == city_id)
                    .order_by(PlaceRefreshJob.versioned_category)
                ).all()
            )
            for row in rows:
                session.expunge(row)
            return rows

    async def execute_job(
        self,
        *,
        city_id: UUID,
        category: DiscoveryCategory,
        stage: PrefetchStage,
        correlation_id: str | None = None,
    ) -> bool:
        """Acquire one durable lease and run its provider refresh if owned."""

        with request_id_scope(correlation_id) as request_id:
            if not self._acquire(city_id, category, request_id=request_id):
                return False

            final_state = RefreshJobState.COMPLETED
            try:
                logger.info(
                    "PLACE_REFRESH_PROVIDER_START request_id=%s city_id=%s "
                    "category=%s worker_id=%s provider=place_discovery",
                    request_id,
                    city_id,
                    category.value,
                    self._worker_id,
                )
                with Session(self._engine) as session:
                    city = session.get(City, city_id)
                    if city is None:
                        raise RuntimeError("refresh city no longer exists")
                    await self._category_refresher(session, city, category, stage)
                self._finish(
                    city_id,
                    category,
                    RefreshJobState.COMPLETED,
                    request_id=request_id,
                )
            except Exception as exc:  # noqa: BLE001 - job failure must be recorded
                final_state = RefreshJobState.FAILED
                self._finish(
                    city_id,
                    category,
                    RefreshJobState.FAILED,
                    error_type=type(exc).__name__,
                    request_id=request_id,
                )
                logger.warning(
                    "PLACE_REFRESH_FAILED request_id=%s city_id=%s category=%s "
                    "worker_id=%s error_type=%s",
                    request_id,
                    city_id,
                    category.value,
                    self._worker_id,
                    type(exc).__name__,
                )
            logger.info(
                "PLACE_REFRESH_FINISHED request_id=%s city_id=%s category=%s "
                "worker_id=%s refresh_state=%s",
                request_id,
                city_id,
                category.value,
                self._worker_id,
                final_state.value,
            )
            return True

    async def _refresh_category(
        self,
        session: Session,
        city: City,
        category: DiscoveryCategory,
        stage: PrefetchStage,
    ) -> None:
        if self._discovery is None:
            raise RuntimeError("No discovery service is configured.")
        summary = await CityPlacePrefetchService(self._discovery).prefetch(
            session=session,
            city=city,
            stage=stage,
            categories=[category],
        )
        if summary.error or category.value not in summary.categories_enriched:
            raise RuntimeError(summary.error or "provider refresh produced no update")

    def _acquire(
        self,
        city_id: UUID,
        category: DiscoveryCategory,
        *,
        request_id: str,
    ) -> bool:
        now = datetime.now(timezone.utc)
        key = self._category_key(category)
        statement = (
            update(PlaceRefreshJob)
            .where(
                PlaceRefreshJob.city_id == city_id,
                PlaceRefreshJob.versioned_category == key,
                or_(
                    PlaceRefreshJob.state == RefreshJobState.QUEUED.value,
                    and_(
                        PlaceRefreshJob.state == RefreshJobState.RUNNING.value,
                        or_(
                            PlaceRefreshJob.lease_expires_at.is_(None),
                            PlaceRefreshJob.lease_expires_at <= now,
                        ),
                    ),
                ),
            )
            .values(
                state=RefreshJobState.RUNNING.value,
                lease_owner=self._worker_id,
                lease_expires_at=now + self._lease_duration,
                last_started_at=now,
                last_error=None,
                attempt_count=PlaceRefreshJob.attempt_count + 1,
                updated_at=now,
            )
        )
        with Session(self._engine) as session:
            result = session.exec(statement)
            session.commit()
            acquired = result.rowcount == 1
        if acquired:
            logger.info(
                "PLACE_REFRESH_LEASE request_id=%s city_id=%s category=%s worker_id=%s",
                request_id,
                city_id,
                category.value,
                self._worker_id,
            )
        return acquired

    def _finish(
        self,
        city_id: UUID,
        category: DiscoveryCategory,
        state: RefreshJobState,
        *,
        error_type: str | None = None,
        request_id: str,
    ) -> None:
        now = datetime.now(timezone.utc)
        values: dict[str, object] = {
            "state": state.value,
            "lease_owner": None,
            "lease_expires_at": None,
            "last_error": error_type,
            "updated_at": now,
        }
        if state is RefreshJobState.COMPLETED:
            values["last_completed_at"] = now
        statement = (
            update(PlaceRefreshJob)
            .where(
                PlaceRefreshJob.city_id == city_id,
                PlaceRefreshJob.versioned_category == self._category_key(category),
                PlaceRefreshJob.lease_owner == self._worker_id,
                PlaceRefreshJob.state == RefreshJobState.RUNNING.value,
            )
            .values(**values)
        )
        with Session(self._engine) as session:
            session.exec(statement)
            session.commit()

    def _execute_job_in_thread(
        self,
        city_id: UUID,
        category: DiscoveryCategory,
        stage: PrefetchStage,
        correlation_id: str,
    ) -> bool:
        return asyncio.run(
            self.execute_job(
                city_id=city_id,
                category=category,
                stage=stage,
                correlation_id=correlation_id,
            )
        )

    def _category_key(self, category: DiscoveryCategory) -> str:
        if self._discovery is None:
            return category.value
        return self._discovery.cache_key(category)

    @staticmethod
    def _as_utc(value: datetime | None) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)
