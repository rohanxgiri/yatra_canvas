"""Cache and persist OpenStreetMap POIs as canonical place candidates."""

import logging
from datetime import datetime, timedelta, timezone
from uuid import UUID

from sqlmodel import Session, select

from app.core.config import Settings
from app.models import City, CityCategoryCache, Place, PlaceSource, PlaceTag
from app.schemas import DiscoveryCategory
from app.services.openstreetmap_places_service import (
    OpenStreetMapNearbyPlace,
    OpenStreetMapPlacesError,
    OpenStreetMapPlacesService,
    OpenStreetMapPlacesUnavailableError,
)
from app.services.audiala_places_provider import AudialaPlacesProvider

logger = logging.getLogger(__name__)


class OpenStreetMapDiscoveryService:
    def __init__(
        self,
        settings: Settings,
        provider: OpenStreetMapPlacesService,
        audiala_provider: AudialaPlacesProvider | None = None,
    ) -> None:
        self._settings = settings
        self._cache_ttl = timedelta(hours=settings.place_discovery_cache_ttl_hours)
        self._provider = provider
        self._audiala_provider = audiala_provider

    async def discover(
        self,
        *,
        session: Session,
        city: City,
        category: DiscoveryCategory,
    ) -> list[Place]:
        results = await self.discover_many(
            session=session,
            city=city,
            categories=[category],
        )
        return results.get(category, [])

    async def discover_many(
        self,
        *,
        session: Session,
        city: City,
        categories: list[DiscoveryCategory],
    ) -> dict[DiscoveryCategory, list[Place]]:
        """Refresh uncached categories together with independent quotas and failure isolation."""

        unique_categories = list(dict.fromkeys(categories))
        if not unique_categories:
            return {}

        now = datetime.now(timezone.utc)
        results: dict[DiscoveryCategory, list[Place]] = {}
        pending: list[DiscoveryCategory] = []
        caches: dict[DiscoveryCategory, CityCategoryCache | None] = {}
        for category in unique_categories:
            cache = session.exec(
                select(CityCategoryCache).where(
                    CityCategoryCache.city_id == city.id,
                    CityCategoryCache.category == category.value,
                )
            ).first()
            caches[category] = cache
            if cache is not None and self._as_utc(cache.expires_at) > now:
                results[category] = self._stored_places(session, city.id, category)
            else:
                pending.append(category)

        if not pending:
            return results

        category_radii = {
            category: self._settings.overpass_radius_for_category(category)
            for category in pending
        }
        category_limits = {
            category: self._settings.overpass_limit_for_category(category)
            for category in pending
        }

        logger.info(
            "Starting discovery for city=%s (lat=%.4f, lon=%.4f): categories=%s radii=%s limits=%s",
            city.name,
            city.latitude,
            city.longitude,
            [c.value for c in pending],
            {c.value: category_radii[c] for c in pending},
            {c.value: category_limits[c] for c in pending},
        )

        nearby_by_category: dict[DiscoveryCategory, list[OpenStreetMapNearbyPlace]] = {}
        try:
            search_many = getattr(
                self._provider,
                "search_nearby_places_for_categories",
                None,
            )
            if len(pending) > 1 and callable(search_many):
                nearby_by_category = await search_many(  # type: ignore[misc]
                    latitude=city.latitude,
                    longitude=city.longitude,
                    categories=pending,
                    category_radii=category_radii,
                    category_limits=category_limits,
                )
            else:
                for category in pending:
                    try:
                        try:
                            nearby_by_category[category] = (
                                await self._provider.search_nearby_places(
                                    latitude=city.latitude,
                                    longitude=city.longitude,
                                    category=category,
                                    radius_meters=category_radii[category],
                                    limit=category_limits[category],
                                )
                            )
                        except TypeError:
                            nearby_by_category[category] = (
                                await self._provider.search_nearby_places(
                                    latitude=city.latitude,
                                    longitude=city.longitude,
                                    category=category,
                                )
                            )
                    except OpenStreetMapPlacesError as exc:
                        logger.warning(
                            "Provider discovery failed for category=%s in city=%s: %s",
                            category.value,
                            city.name,
                            exc,
                        )
        except OpenStreetMapPlacesError as exc:
            logger.warning(
                "Provider discovery batch failed for city=%s: %s",
                city.name,
                exc,
            )

        raw_total_candidates = sum(len(places) for places in nearby_by_category.values())
        logger.info(
            "Provider discovery returned %d raw candidates across %d categories for city=%s",
            raw_total_candidates,
            len(nearby_by_category),
            city.name,
        )

        audiala_by_category: dict[DiscoveryCategory, list[OpenStreetMapNearbyPlace]] = {}
        if self._audiala_provider is not None:
            try:
                audiala_by_category = await self._audiala_provider.search_nearby_places_for_categories(
                    latitude=city.latitude,
                    longitude=city.longitude,
                    categories=pending,
                    category_radii=category_radii,
                    category_limits=category_limits,
                )
                aud_total = sum(len(p) for p in audiala_by_category.values())
                logger.info(
                    "Audiala secondary discovery returned %d candidates across %d categories for city=%s",
                    aud_total,
                    len(audiala_by_category),
                    city.name,
                )
            except Exception as exc:
                logger.warning(
                    "Audiala provider discovery failed for city=%s: %s",
                    city.name,
                    exc,
                )

        failed_categories: list[DiscoveryCategory] = []
        for category in pending:
            osm_places = nearby_by_category.get(category, [])
            aud_places = audiala_by_category.get(category, [])
            
            if category in nearby_by_category or category in audiala_by_category:
                if osm_places:
                    self._persist_category(
                        session=session,
                        city=city,
                        category=category,
                        nearby_places=osm_places,
                        fetched_at=now,
                        source_name="openstreetmap",
                        licence_identifier="ODbL-1.0",
                    )
                if aud_places:
                    # Filter out Audiala places that already exist from other sources (e.g., OSM) to avoid duplicates
                    existing_external_ids = self._existing_external_ids(session, city.id, aud_places)
                    # Include OSM places already persisted in this iteration
                    existing_external_ids.update(p.external_place_id for p in osm_places)
                    filtered_aud_places = [p for p in aud_places if p.external_place_id not in existing_external_ids]
                    if filtered_aud_places:
                        self._persist_category(
                            session=session,
                            city=city,
                            category=category,
                            nearby_places=filtered_aud_places,
                            fetched_at=now,
                            source_name="audiala",
                            licence_identifier="CC BY 4.0",
                        )

                cache = caches.get(category)
                if cache is None:
                    cache = CityCategoryCache(
                        city_id=city.id,
                        category=category.value,
                        last_fetched_at=now,
                        expires_at=now + self._cache_ttl,
                    )
                    session.add(cache)
                else:
                    cache.last_fetched_at = now
                    cache.expires_at = now + self._cache_ttl
            else:
                failed_categories.append(category)

        session.commit()

        # Handle failed categories with stale DB fallback or empty
        if failed_categories:
            has_any_success = bool(nearby_by_category) or bool(audiala_by_category)
            has_any_stale = False
            for category in failed_categories:
                stale_places = self._stored_places(session, city.id, category)
                results[category] = stale_places
                if stale_places:
                    has_any_stale = True
                    logger.info(
                        "Falling back to %d stale places for failed category=%s in city=%s",
                        len(stale_places),
                        category.value,
                        city.name,
                    )
                else:
                    logger.warning(
                        "No stale places available for failed category=%s in city=%s",
                        category.value,
                        city.name,
                    )

            if not has_any_success and not has_any_stale:
                raise OpenStreetMapPlacesUnavailableError(
                    f"OpenStreetMap discovery failed for all pending categories in {city.name}."
                )

        for category in pending:
            if category not in failed_categories:
                results[category] = self._stored_places(session, city.id, category)

        total_stored = sum(len(p) for p in results.values())
        logger.info(
            "Discovery completed for city=%s: %d total places across %d categories",
            city.name,
            total_stored,
            len(unique_categories),
        )
        return results

    def _persist_category(
        self,
        *,
        session: Session,
        city: City,
        category: DiscoveryCategory,
        nearby_places: list[OpenStreetMapNearbyPlace],
        fetched_at: datetime,
        source_name: str,
        licence_identifier: str,
    ) -> None:
        """Persist a category's places, handling deduplication across sources.

        This method now expects that duplicate external IDs across different providers
        are filtered before calling, but also provides a helper to query existing external IDs.
        """
        current_external_ids = [nearby.external_place_id for nearby in nearby_places]
        current_external_ids_set = set(current_external_ids)

        old_memberships = session.exec(
            select(PlaceTag, PlaceSource)
            .join(Place, Place.id == PlaceTag.place_id)
            .join(PlaceSource, PlaceSource.place_id == Place.id)
            .where(
                Place.city_id == city.id,
                PlaceTag.tag == category.value,
                PlaceSource.source == source_name,
            )
        ).all()

        membership_place_ids = [m.place_id for m, _ in old_memberships]
        other_sources_set = set()
        if membership_place_ids:
            other_sources = session.exec(
                select(PlaceSource.place_id).where(
                    PlaceSource.place_id.in_(membership_place_ids),  # type: ignore[union-attr]
                    PlaceSource.source != source_name,
                )
            ).all()
            other_sources_set.update(other_sources)

        for membership, source in old_memberships:
            if source.external_place_id in current_external_ids_set:
                continue
            if membership.place_id in other_sources_set:
                continue
            session.delete(membership)
        session.flush()

        sources_by_ext_id = {}
        places_by_id = {}
        tags_by_place_id: dict[UUID, set[str]] = {}

        if current_external_ids:
            existing_sources = session.exec(
                select(PlaceSource).where(
                    PlaceSource.source == source_name,
                    PlaceSource.external_place_id.in_(current_external_ids),  # type: ignore[union-attr]
                )
            ).all()
            sources_by_ext_id = {s.external_place_id: s for s in existing_sources}

            existing_place_ids = [s.place_id for s in existing_sources]
            if existing_place_ids:
                existing_places = session.exec(
                    select(Place).where(Place.id.in_(existing_place_ids))  # type: ignore[union-attr]
                ).all()
                places_by_id = {p.id: p for p in existing_places}

                existing_tags = session.exec(
                    select(PlaceTag).where(PlaceTag.place_id.in_(existing_place_ids))  # type: ignore[union-attr]
                ).all()
                for t in existing_tags:
                    tags_by_place_id.setdefault(t.place_id, set()).add(t.tag)

        for nearby in nearby_places:
            source = sources_by_ext_id.get(nearby.external_place_id)
            place = places_by_id.get(source.place_id) if source else None

            if place is None:
                place = Place(
                    city_id=city.id,
                    name=nearby.name,
                    category=category.value,
                    latitude=nearby.latitude,
                    longitude=nearby.longitude,
                    rating=None,
                    review_count=0,
                    is_popular=False,
                    is_heritage=(category is DiscoveryCategory.HERITAGE),
                    is_local_speciality=False,
                    last_fetched_at=fetched_at,
                )
                session.add(place)
                session.flush()
            else:
                place.city_id = city.id
                place.name = nearby.name
                place.latitude = nearby.latitude
                place.longitude = nearby.longitude
                place.is_heritage = (
                    place.is_heritage or category is DiscoveryCategory.HERITAGE
                )
                place.last_fetched_at = fetched_at

            if source is None:
                source = PlaceSource(
                    place_id=place.id,
                    source=source_name,
                    external_place_id=nearby.external_place_id,
                    source_url=nearby.source_url,
                    licence_identifier=licence_identifier,
                    website=OpenStreetMapDiscoveryService._bounded(
                        nearby.tags.get("website"), 1000
                    ),
                    telephone=OpenStreetMapDiscoveryService._bounded(
                        nearby.tags.get("phone"), 80
                    ),
                    last_fetched_at=fetched_at,
                )
                session.add(source)
            else:
                source.source_url = nearby.source_url
                source.website = OpenStreetMapDiscoveryService._bounded(
                    nearby.tags.get("website"), 1000
                )
                source.telephone = OpenStreetMapDiscoveryService._bounded(
                    nearby.tags.get("phone"), 80
                )
                source.last_fetched_at = fetched_at

            existing_place_tags = tags_by_place_id.get(place.id, set())
            for tag in sorted({category.value} - existing_place_tags):
                session.add(PlaceTag(place_id=place.id, tag=tag))
                tags_by_place_id.setdefault(place.id, set()).add(tag)

    @staticmethod
    def _stored_places(
        session: Session,
        city_id: UUID,
        category: DiscoveryCategory,
    ) -> list[Place]:
        return list(
            session.exec(
                select(Place)
                .join(PlaceTag, PlaceTag.place_id == Place.id)
                .where(
                    Place.city_id == city_id,
                    PlaceTag.tag == category.value,
                )
                .order_by(Place.name)
            ).all()
        )

    @staticmethod
    def _as_utc(value: datetime) -> datetime:
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)

    @staticmethod
    def _bounded(value: str | None, maximum: int) -> str | None:
        if value is None:
            return None
        normalized = value.strip()
        return normalized[:maximum] or None

    def _existing_external_ids(self, session: Session, city_id: UUID, places: list[OpenStreetMapNearbyPlace]) -> set[str]:
        """Return a set of external_place_id values that already exist for the given city.

        Used to deduplicate across providers before persisting new places.
        """
        external_ids = [p.external_place_id for p in places]
        if not external_ids:
            return set()
        result = session.exec(
            select(PlaceSource.external_place_id)
            .join(Place, Place.id == PlaceSource.place_id)
            .where(
                Place.city_id == city_id,
                PlaceSource.external_place_id.in_(external_ids),
            )
        ).all()
        return set(result)

