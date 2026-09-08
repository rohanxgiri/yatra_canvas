"""Progressive POI prefetch service for destination- and interest-triggered background discovery."""

from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass
from datetime import datetime, timezone
from enum import Enum
from uuid import UUID

from sqlalchemy import func
from sqlmodel import Session, select

from app.models.entities import City, CityCategoryCache, Place, PlaceTag
from app.schemas import DiscoveryCategory
from app.services.openstreetmap_discovery_service import OpenStreetMapDiscoveryService

logger = logging.getLogger(__name__)


class PrefetchStage(str, Enum):
    DESTINATION_CONFIRMED = "destination_confirmed"
    DATES_CONFIRMED = "dates_confirmed"
    INTERESTS_CONFIRMED = "interests_confirmed"
    START_LOCATION_CONFIRMED = "start_location_confirmed"


# Default core categories for broad shallow prefetch
SHALLOW_PREFETCH_CATEGORIES: list[DiscoveryCategory] = [
    DiscoveryCategory.TOURISM,
    DiscoveryCategory.HERITAGE,
    DiscoveryCategory.FOOD,
    DiscoveryCategory.RELIGIOUS,
    DiscoveryCategory.CAFES,
    DiscoveryCategory.MARKETS,
    DiscoveryCategory.NATURE,
]

SHALLOW_TARGET_CANDIDATES = 15
DEEP_TARGET_CANDIDATES = 35


@dataclass
class PrefetchSummary:
    city_id: UUID
    city_name: str
    stage: PrefetchStage
    categories_requested: list[str]
    categories_skipped_sufficient: list[str]
    categories_enriched: list[str]
    duplicate_refreshes_prevented: int
    poi_count: int = 0
    error: str | None = None


class CityPlacePrefetchService:
    """Manages progressive POI prefetch without blocking user navigation."""

    def __init__(self, discovery_service: OpenStreetMapDiscoveryService) -> None:
        self._discovery = discovery_service
        # In-flight lock map: (city_id, category_value) -> asyncio.Task
        self._in_flight: dict[tuple[UUID, str], asyncio.Future[None]] = {}
        self._lock = asyncio.Lock()

    def get_category_coverage(
        self,
        session: Session,
        city_id: UUID,
        category: DiscoveryCategory,
    ) -> int:
        """Count existing stored places for this city and category."""
        return len(
            session.exec(
                select(Place.id)
                .join(PlaceTag, PlaceTag.place_id == Place.id)
                .where(
                    Place.city_id == city_id,
                    PlaceTag.tag == category.value,
                )
            ).all()
        )

    async def prefetch(
        self,
        *,
        session: Session,
        city: City,
        stage: PrefetchStage,
        categories: list[DiscoveryCategory] | None = None,
    ) -> PrefetchSummary:
        """Execute non-blocking progressive prefetch based on current trip creation stage."""
        if stage == PrefetchStage.DESTINATION_CONFIRMED:
            target_categories = categories or SHALLOW_PREFETCH_CATEGORIES
            min_candidates = SHALLOW_TARGET_CANDIDATES
        else:
            target_categories = categories or SHALLOW_PREFETCH_CATEGORIES
            min_candidates = DEEP_TARGET_CANDIDATES

        unique_categories = list(dict.fromkeys(target_categories))
        skipped_sufficient: list[str] = []
        needed_categories: list[DiscoveryCategory] = []
        duplicate_prevented = 0

        category_values = [category.value for category in unique_categories]
        coverage_rows = session.exec(
            select(PlaceTag.tag, func.count(func.distinct(Place.id)))
            .join(Place, Place.id == PlaceTag.place_id)
            .where(
                Place.city_id == city.id,
                PlaceTag.tag.in_(category_values),
            )
            .group_by(PlaceTag.tag)
        ).all()
        coverage_by_category = {tag: int(count) for tag, count in coverage_rows}
        cache_keys = {
            category: self._discovery.cache_key(category)
            for category in unique_categories
        }
        cache_rows = session.exec(
            select(CityCategoryCache).where(
                CityCategoryCache.city_id == city.id,
                CityCategoryCache.category.in_(list(cache_keys.values())),
            )
        ).all()
        cache_by_key = {cache.category: cache for cache in cache_rows}

        # Step 1: Coverage & In-flight check
        for category in unique_categories:
            key = (city.id, category.value)
            # Check in-flight
            async with self._lock:
                if key in self._in_flight and not self._in_flight[key].done():
                    duplicate_prevented += 1
                    logger.info(
                        "Prefetch: refresh already in-flight for city=%s category=%s",
                        city.name,
                        category.value,
                    )
                    continue

            # Check coverage
            coverage = coverage_by_category.get(category.value, 0)
            cache = cache_by_key.get(cache_keys[category])
            expires_at = cache.expires_at if cache is not None else None
            if expires_at is not None and expires_at.tzinfo is None:
                expires_at = expires_at.replace(tzinfo=timezone.utc)
            is_fresh = expires_at is not None and expires_at > datetime.now(
                timezone.utc
            )
            has_sufficient_coverage = (
                coverage > 0
                if stage == PrefetchStage.DESTINATION_CONFIRMED
                else coverage >= min_candidates
            )
            if has_sufficient_coverage and is_fresh:
                skipped_sufficient.append(category.value)
                logger.info(
                    "PREFETCH_CACHE_HIT city_id=%s category=%s count=%d stage=%s",
                    city.id,
                    category.value,
                    coverage,
                    stage.value,
                )
            else:
                needed_categories.append(category)
                logger.info(
                    "PREFETCH_CACHE_MISS city_id=%s category=%s count=%d fresh=%s stage=%s",
                    city.id,
                    category.value,
                    coverage,
                    is_fresh,
                    stage.value,
                )

        if not needed_categories:
            poi_count = len(
                session.exec(select(Place.id).where(Place.city_id == city.id)).all()
            )
            return PrefetchSummary(
                city_id=city.id,
                city_name=city.name,
                stage=stage,
                categories_requested=[c.value for c in unique_categories],
                categories_skipped_sufficient=skipped_sufficient,
                categories_enriched=[],
                duplicate_refreshes_prevented=duplicate_prevented,
                poi_count=poi_count,
            )

        # Step 2: Register in-flight tasks and trigger discovery
        loop = asyncio.get_running_loop()
        future_map: dict[tuple[UUID, str], asyncio.Future[None]] = {}
        async with self._lock:
            for cat in needed_categories:
                fut: asyncio.Future[None] = loop.create_future()
                self._in_flight[(city.id, cat.value)] = fut
                future_map[(city.id, cat.value)] = fut

        enriched: list[str] = []
        error: str | None = None
        try:
            logger.info(
                "PREFETCH_STARTED stage=%s city_id=%s city=%s categories=%s",
                stage.value,
                city.id,
                city.name,
                [c.value for c in needed_categories],
            )
            # Custom shallow limits if destination_confirmed
            custom_limits = (
                {c: SHALLOW_TARGET_CANDIDATES for c in needed_categories}
                if stage == PrefetchStage.DESTINATION_CONFIRMED
                else None
            )

            await self._discovery.discover_many(
                session=session,
                city=city,
                categories=needed_categories,
                custom_category_limits=custom_limits,
                prefer_stale=False,
                include_overpass=(
                    stage != PrefetchStage.DESTINATION_CONFIRMED
                    or not self._discovery.has_fast_prefetch_provider
                ),
            )
            enriched = [c.value for c in needed_categories]
        except Exception as exc:
            error = str(exc)
            logger.warning(
                "PREFETCH_FAILED city_id=%s city=%s error=%s",
                city.id,
                city.name,
                exc,
            )
        finally:
            async with self._lock:
                for key, fut in future_map.items():
                    if not fut.done():
                        fut.set_result(None)
                    self._in_flight.pop(key, None)

        poi_count = len(
            session.exec(select(Place.id).where(Place.city_id == city.id)).all()
        )
        return PrefetchSummary(
            city_id=city.id,
            city_name=city.name,
            stage=stage,
            categories_requested=[c.value for c in unique_categories],
            categories_skipped_sufficient=skipped_sufficient,
            categories_enriched=enriched,
            duplicate_refreshes_prevented=duplicate_prevented,
            poi_count=poi_count,
            error=error,
        )
