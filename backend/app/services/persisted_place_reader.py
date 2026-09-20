"""Provider-free reads of persisted recommendation candidates and freshness."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from enum import Enum
from uuid import UUID

from sqlmodel import Session, select

from app.core.config import Settings, get_settings
from app.models import CityCategoryCache, Place, PlaceTag
from app.schemas import DiscoveryCategory


class CategoryFreshness(str, Enum):
    """Refresh state for one versioned city/category cache row."""

    FRESH = "fresh"
    STALE = "stale"
    EXPIRED = "expired"
    MISSING = "missing"


@dataclass(frozen=True, slots=True)
class PersistedCandidateSnapshot:
    places_by_category: dict[DiscoveryCategory, list[Place]]
    freshness: dict[DiscoveryCategory, CategoryFreshness]

    @property
    def refresh_categories(self) -> list[DiscoveryCategory]:
        return [
            category
            for category, state in self.freshness.items()
            if state is not CategoryFreshness.FRESH
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
            return PersistedCandidateSnapshot({}, {})

        category_by_value = {category.value: category for category in unique_categories}
        places_by_category = {category: [] for category in unique_categories}
        places = list(
            session.exec(
                select(Place)
                .where(
                    Place.city_id == city_id,
                    Place.moderation_status == "ACTIVE",
                )
                .order_by(Place.name)
            ).all()
        )
        place_by_id = {place.id: place for place in places}
        tags_by_place: dict[UUID, set[str]] = {place.id: set() for place in places}
        if place_by_id:
            tag_rows = session.exec(
                select(PlaceTag.place_id, PlaceTag.tag).where(
                    PlaceTag.place_id.in_(list(place_by_id)),
                    PlaceTag.tag.in_(list(category_by_value)),
                )
            ).all()
            for place_id, tag in tag_rows:
                tags_by_place.setdefault(place_id, set()).add(tag)

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
        freshness: dict[DiscoveryCategory, CategoryFreshness] = {}
        for category, key in keys.items():
            cache = cache_by_key.get(key)
            if cache is None:
                freshness[category] = CategoryFreshness.MISSING
            elif self._as_utc(cache.expires_at) > checked_at:
                freshness[category] = CategoryFreshness.FRESH
            elif self._as_utc(cache.last_fetched_at) + self._stale_ttl > checked_at:
                freshness[category] = CategoryFreshness.STALE
            else:
                freshness[category] = CategoryFreshness.EXPIRED

        return PersistedCandidateSnapshot(places_by_category, freshness)

    @staticmethod
    def _as_utc(value: datetime) -> datetime:
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)
