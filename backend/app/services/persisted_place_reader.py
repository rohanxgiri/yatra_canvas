"""Provider-free reads of persisted recommendation candidates and freshness."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from enum import Enum
from uuid import UUID

from sqlalchemy import and_
from sqlmodel import Session, select

from app.core.config import Settings, get_settings
from app.models import (
    City,
    CityCategoryCache,
    Place,
    PlaceImageCache,
    PlaceSource,
    PlaceTag,
)
from app.schemas import DiscoveryCategory
from app.schemas.place_image import PlaceImageRead
from app.services.place_image_service import image_read_from_cache


class CategoryFreshness(str, Enum):
    """Refresh state for one versioned city/category cache row."""

    FRESH = "fresh"
    STALE = "stale"
    EXPIRED = "expired"
    INSUFFICIENT = "insufficient"
    MISSING = "missing"


@dataclass(frozen=True, slots=True)
class CoverageStatus:
    """One canonical persisted coverage decision for a city category."""

    state: CategoryFreshness
    usable_count: int
    desired_count: int
    last_refreshed_at: datetime | None

    @property
    def is_usable(self) -> bool:
        return self.usable_count > 0

    @property
    def refresh_needed(self) -> bool:
        return self.state is not CategoryFreshness.FRESH


@dataclass(frozen=True, slots=True)
class PersistedCandidateSnapshot:
    city: City | None
    places_by_category: dict[DiscoveryCategory, list[Place]]
    coverage: dict[DiscoveryCategory, CoverageStatus]
    tags_by_place: dict[UUID, set[str]]
    place_sources: list[PlaceSource]
    images_by_place: dict[UUID, PlaceImageRead]
    image_refresh_ids: set[UUID]

    @property
    def freshness(self) -> dict[DiscoveryCategory, CategoryFreshness]:
        """Compatibility view for callers that need only the state."""

        return {category: status.state for category, status in self.coverage.items()}

    @property
    def refresh_categories(self) -> list[DiscoveryCategory]:
        return [
            category
            for category, status in self.coverage.items()
            if status.refresh_needed
        ]

    @property
    def stored_count(self) -> int:
        return len(
            {
                place.id
                for places in self.places_by_category.values()
                for place in places
            }
        )


class PersistedPlaceReader:
    """Read application-owned POIs without invoking any external provider."""

    def __init__(self, settings: Settings | None = None) -> None:
        self._settings = settings or get_settings()
        self._stale_ttl = timedelta(hours=self._settings.discovery_stale_usable_hours)

    def cache_key(self, category: DiscoveryCategory) -> str:
        version = self._settings.place_discovery_cache_version
        return category.value if version == 1 else f"v{version}:{category.value}"

    def read(
        self,
        *,
        session: Session,
        city_id: UUID,
        categories: list[DiscoveryCategory],
        now: datetime | None = None,
    ) -> PersistedCandidateSnapshot:
        unique_categories = list(dict.fromkeys(categories))
        if not unique_categories:
            return PersistedCandidateSnapshot(None, {}, {}, {}, [], {}, set())

        category_by_value = {category.value: category for category in unique_categories}
        places_by_category = {category: [] for category in unique_categories}
        # Tags and provider identities describe the same candidate set. Loading
        # them with the places avoids two extra sequential round trips to a
        # remote database. The dictionaries below collapse the small outer join
        # fan out without changing the snapshot contract.
        candidate_rows = session.exec(
            select(City, Place, PlaceTag.tag, PlaceSource, PlaceImageCache)
            .select_from(City)
            .outerjoin(
                Place,
                and_(
                    Place.city_id == City.id,
                    Place.moderation_status == "ACTIVE",
                ),
            )
            .outerjoin(
                PlaceTag,
                PlaceTag.place_id == Place.id,
            )
            .outerjoin(PlaceSource, PlaceSource.place_id == Place.id)
            .outerjoin(PlaceImageCache, PlaceImageCache.place_id == Place.id)
            .where(City.id == city_id)
            .order_by(Place.name)
        ).all()
        city: City | None = None
        place_by_id: dict[UUID, Place] = {}
        tags_by_place: dict[UUID, set[str]] = {}
        source_by_id: dict[UUID, PlaceSource] = {}
        image_row_by_place: dict[UUID, PlaceImageCache] = {}
        for row_city, place, tag, source, image_row in candidate_rows:
            city = row_city
            if place is None:
                continue
            place_by_id.setdefault(place.id, place)
            tags_by_place.setdefault(place.id, set())
            if tag is not None:
                tags_by_place[place.id].add(tag)
            if source is not None:
                source_by_id.setdefault(source.id, source)
            if image_row is not None:
                image_row_by_place.setdefault(image_row.place_id, image_row)
        places = list(place_by_id.values())

        for place in places:
            membership_values = set(tags_by_place.get(place.id, set()))
            membership_values.add(place.category.casefold())
            for value in membership_values:
                category = category_by_value.get(value)
                if category is not None:
                    places_by_category[category].append(place)

        keys = {category: self.cache_key(category) for category in unique_categories}
        cache_rows = session.exec(
            select(CityCategoryCache).where(
                CityCategoryCache.city_id == city_id,
                CityCategoryCache.category.in_(list(keys.values())),
            )
        ).all()
        cache_by_key = {row.category: row for row in cache_rows}
        checked_at = now or datetime.now(timezone.utc)
        image_refresh_ids = set(place_by_id)
        images_by_place: dict[UUID, PlaceImageRead] = {}
        for place_id, image_row in image_row_by_place.items():
            expired = self._as_utc(image_row.expires_at) <= checked_at
            if not expired:
                image_refresh_ids.discard(place_id)
            if not expired or image_row.status == "resolved":
                images_by_place[place_id] = image_read_from_cache(image_row)
        coverage: dict[DiscoveryCategory, CoverageStatus] = {}
        desired_count = self._settings.discovery_min_usable_candidates_per_category
        for category, key in keys.items():
            cache = cache_by_key.get(key)
            usable_count = len({place.id for place in places_by_category[category]})
            last_refreshed_at = (
                self._as_utc(cache.last_fetched_at) if cache is not None else None
            )
            if usable_count == 0:
                state = CategoryFreshness.MISSING
            elif cache is None:
                state = CategoryFreshness.INSUFFICIENT
            elif self._as_utc(cache.expires_at) > checked_at:
                state = CategoryFreshness.FRESH
            elif self._as_utc(cache.last_fetched_at) + self._stale_ttl > checked_at:
                state = CategoryFreshness.STALE
            else:
                state = CategoryFreshness.EXPIRED
            coverage[category] = CoverageStatus(
                state=state,
                usable_count=usable_count,
                desired_count=desired_count,
                last_refreshed_at=last_refreshed_at,
            )

        return PersistedCandidateSnapshot(
            city,
            places_by_category,
            coverage,
            tags_by_place,
            list(source_by_id.values()),
            images_by_place,
            image_refresh_ids,
        )

    @staticmethod
    def _as_utc(value: datetime) -> datetime:
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)
