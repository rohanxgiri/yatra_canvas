"""Progressive POI prefetch service for destination- and interest-triggered background discovery."""

from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass
from enum import Enum
from uuid import UUID

from sqlmodel import Session, select

from app.models.entities import City, CityCategoryCache, Place, PlaceTag
from app.schemas import DiscoveryCategory
from app.services.openstreetmap_discovery_service import OpenStreetMapDiscoveryService

logger = logging.getLogger(__name__)


class PrefetchStage(str, Enum):
    DESTINATION_CONFIRMED = "destination_confirmed"
    INTERESTS_CONFIRMED = "interests_confirmed"


# Default core categories for broad shallow prefetch
SHALLOW_PREFETCH_CATEGORIES: list[DiscoveryCategory] = [
    DiscoveryCategory.TOURISM,
    DiscoveryCategory.HERITAGE,
    DiscoveryCategory.FOOD,
    DiscoveryCategory.RELIGIOUS,
    DiscoveryCategory.CAFES,
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
            target_categories = SHALLOW_PREFETCH_CATEGORIES
            min_candidates = SHALLOW_TARGET_CANDIDATES
        else:
            target_categories = categories or SHALLOW_PREFETCH_CATEGORIES
            min_candidates = DEEP_TARGET_CANDIDATES

        unique_categories = list(dict.fromkeys(target_categories))
        skipped_sufficient: list[str] = []
        needed_categories: list[DiscoveryCategory] = []
        duplicate_prevented = 0

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
            coverage = self.get_category_coverage(session, city.id, category)
            if coverage >= min_candidates:
                skipped_sufficient.append(category.value)
                logger.info(
                    "Prefetch: coverage sufficient for city=%s category=%s (count=%d >= %d)",
                    city.name,
                    category.value,
                    coverage,
                    min_candidates,
                )
            else:
                needed_categories.append(category)

        if not needed_categories:
            return PrefetchSummary(
                city_id=city.id,
                city_name=city.name,
                stage=stage,
                categories_requested=[c.value for c in unique_categories],
                categories_skipped_sufficient=skipped_sufficient,
                categories_enriched=[],
                duplicate_refreshes_prevented=duplicate_prevented,
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
        try:
            logger.info(
                "Executing %s prefetch for city=%s categories=%s",
                stage.value,
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
            )
            enriched = [c.value for c in needed_categories]
        except Exception as exc:
            logger.warning("Prefetch encountered an error for city=%s: %s", city.name, exc)
        finally:
            async with self._lock:
                for key, fut in future_map.items():
                    if not fut.done():
                        fut.set_result(None)
                    self._in_flight.pop(key, None)

        return PrefetchSummary(
            city_id=city.id,
            city_name=city.name,
            stage=stage,
            categories_requested=[c.value for c in unique_categories],
            categories_skipped_sufficient=skipped_sufficient,
            categories_enriched=enriched,
            duplicate_refreshes_prevented=duplicate_prevented,
        )
