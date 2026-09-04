"""Cache and persist OpenStreetMap POIs as canonical place candidates."""

import logging
import time
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
from app.services.geoapify_places_provider import GeoapifyPlacesProvider
from app.services.canonical_place_service import CanonicalPlaceService

logger = logging.getLogger(__name__)


class OpenStreetMapDiscoveryService:
    def __init__(
        self,
        settings: Settings,
        provider: OpenStreetMapPlacesService,
        audiala_provider: AudialaPlacesProvider | None = None,
        canonical_service: CanonicalPlaceService | None = None,
        geoapify_provider: GeoapifyPlacesProvider | None = None,
    ) -> None:
        self._settings = settings
        self._cache_ttl = timedelta(hours=settings.place_discovery_cache_ttl_hours)
        self._provider = provider
        self._audiala_provider = audiala_provider
        self._canonical_service = canonical_service or CanonicalPlaceService()
        self._geoapify_provider = geoapify_provider

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
        custom_category_limits: dict[DiscoveryCategory, int] | None = None,
        prefer_stale: bool = True,
    ) -> dict[DiscoveryCategory, list[Place]]:
        """Refresh uncached categories with 3-tier cache semantics, Geoapify fallback, and failure isolation."""

        unique_categories = list(dict.fromkeys(categories))
        if not unique_categories:
            return {}

        now = datetime.now(timezone.utc)
        results: dict[DiscoveryCategory, list[Place]] = {}
        pending: list[DiscoveryCategory] = []
        caches: dict[DiscoveryCategory, CityCategoryCache | None] = {}
        t_start = time.monotonic()

        for category in unique_categories:
            cache = session.exec(
                select(CityCategoryCache).where(
                    CityCategoryCache.city_id == city.id,
                    CityCategoryCache.category == category.value,
                )
            ).first()
            caches[category] = cache
            stored = self._stored_places(session, city.id, category)

            # 3-tier classification:
            # 1. FRESH: cache unexpired and has stored places
            if cache is not None and self._as_utc(cache.expires_at) > now and stored:
                results[category] = stored
            # 2. STALE_USABLE: expired cache or unverified, but stored places exist
            elif stored and prefer_stale:
                results[category] = stored
            # 3. MISSING: no stored places
            else:
                pending.append(category)

        cache_lookup_ms = (time.monotonic() - t_start) * 1000

        if not pending:
            logger.info(
                "Discovery cache-hit for city=%s (%d categories): cache_lookup=%.1fms",
                city.name,
                len(unique_categories),
                cache_lookup_ms,
            )
            return results

        category_radii = {
            category: self._settings.overpass_radius_for_category(category)
            for category in pending
        }
        category_limits = {
            category: (
                custom_category_limits[category]
                if custom_category_limits and category in custom_category_limits
                else self._settings.overpass_limit_for_category(category)
            )
            for category in pending
        }

        logger.info(
            "Starting discovery for city=%s (lat=%.4f, lon=%.4f): pending_categories=%s limits=%s",
            city.name,
            city.latitude,
            city.longitude,
            [c.value for c in pending],
            {c.value: category_limits[c] for c in pending},
        )

        provider_outcomes: dict[str, str] = {}

        # Provider 1: Audiala (local dataset, fast)
        audiala_by_category: dict[DiscoveryCategory, list[OpenStreetMapNearbyPlace]] = {}
        t_aud = time.monotonic()
        if self._audiala_provider is not None:
            try:
                audiala_by_category = await self._audiala_provider.search_nearby_places_for_categories(
                    latitude=city.latitude,
                    longitude=city.longitude,
                    categories=pending,
                    category_radii=category_radii,
                    category_limits=category_limits,
                )
                provider_outcomes["audiala"] = f"success ({sum(len(p) for p in audiala_by_category.values())} places)"
            except Exception as exc:
                provider_outcomes["audiala"] = f"failed ({exc})"
                logger.warning("Audiala provider discovery failed for city=%s: %s", city.name, exc)
        else:
            provider_outcomes["audiala"] = "skipped (none)"
        audiala_ms = (time.monotonic() - t_aud) * 1000

        # Provider 2: Geoapify Places (fast structured hosted API)
        geoapify_by_category: dict[DiscoveryCategory, list[OpenStreetMapNearbyPlace]] = {}
        t_geo = time.monotonic()
        if self._geoapify_provider is not None and self._geoapify_provider.is_configured:
            try:
                geoapify_by_category = await self._geoapify_provider.search_nearby_places_for_categories(
                    latitude=city.latitude,
                    longitude=city.longitude,
                    categories=pending,
                    category_radii=category_radii,
                    category_limits=category_limits,
                )
                provider_outcomes["geoapify"] = f"success ({sum(len(p) for p in geoapify_by_category.values())} places)"
            except Exception as exc:
                provider_outcomes["geoapify"] = f"failed ({exc})"
                logger.warning("Geoapify provider discovery failed for city=%s: %s", city.name, exc)
        else:
            provider_outcomes["geoapify"] = "skipped (unconfigured)"
        geoapify_ms = (time.monotonic() - t_geo) * 1000

        # Provider 3: Overpass (OSM)
        nearby_by_category: dict[DiscoveryCategory, list[OpenStreetMapNearbyPlace]] = {}
        t_osm = time.monotonic()
        try:
            search_many = getattr(
                self._provider,
                "search_nearby_places_for_categories",
                None,
            )
            if callable(search_many):
                nearby_by_category = await search_many(  # type: ignore[misc]
                    latitude=city.latitude,
                    longitude=city.longitude,
                    categories=pending,
                    category_radii=category_radii,
                    category_limits=category_limits,
                )
                provider_outcomes["overpass"] = f"success ({sum(len(p) for p in nearby_by_category.values())} places)"
            else:
                for category in pending:
                    try:
                        try:
                            nearby_by_category[category] = await self._provider.search_nearby_places(
                                latitude=city.latitude,
                                longitude=city.longitude,
                                category=category,
                                radius_meters=category_radii[category],
                                limit=category_limits[category],
                            )
                        except TypeError:
                            nearby_by_category[category] = await self._provider.search_nearby_places(
                                latitude=city.latitude,
                                longitude=city.longitude,
                                category=category,
                            )
                    except OpenStreetMapPlacesError as exc:
                        logger.warning(
                            "Provider discovery failed for category=%s in city=%s: %s",
                            category.value,
                            city.name,
                            exc,
                        )
                provider_outcomes["overpass"] = f"partial/success ({sum(len(p) for p in nearby_by_category.values())} places)"
        except OpenStreetMapPlacesError as exc:
            provider_outcomes["overpass"] = f"failed ({exc})"
            logger.warning("Overpass provider discovery batch failed for city=%s: %s", city.name, exc)
        overpass_ms = (time.monotonic() - t_osm) * 1000

        # Persist and update cache
        t_persist = time.monotonic()
        failed_categories: list[DiscoveryCategory] = []
        for category in pending:
            osm_places = nearby_by_category.get(category, [])
            aud_places = audiala_by_category.get(category, [])
            geo_places = geoapify_by_category.get(category, [])

            has_places = bool(osm_places or aud_places or geo_places)
            if has_places:
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
                    self._persist_category(
                        session=session,
                        city=city,
                        category=category,
                        nearby_places=aud_places,
                        fetched_at=now,
                        source_name="audiala",
                        licence_identifier="CC BY 4.0",
                    )
                if geo_places:
                    self._persist_category(
                        session=session,
                        city=city,
                        category=category,
                        nearby_places=geo_places,
                        fetched_at=now,
                        source_name="geoapify",
                        licence_identifier="Geoapify-Proprietary",
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
        persistence_ms = (time.monotonic() - t_persist) * 1000

        # Handle failed categories with stale DB fallback
        for category in failed_categories:
            stale_places = self._stored_places(session, city.id, category)
            results[category] = stale_places
            if stale_places:
                logger.info(
                    "Falling back to %d stale places for failed category=%s in city=%s",
                    len(stale_places),
                    category.value,
                    city.name,
                )

        for category in pending:
            if category not in failed_categories:
                results[category] = self._stored_places(session, city.id, category)

        total_ms = (time.monotonic() - t_start) * 1000
        logger.info(
            "Discovery completed for city=%s: cache_lookup=%.1fms audiala=%.1fms geoapify=%.1fms overpass=%.1fms persist=%.1fms total=%.1fms outcomes=%s",
            city.name,
            cache_lookup_ms,
            audiala_ms,
            geoapify_ms,
            overpass_ms,
            persistence_ms,
            total_ms,
            provider_outcomes,
        )

        total_stored = sum(len(p) for p in results.values())
        if total_stored == 0 and failed_categories and len(failed_categories) == len(unique_categories):
            raise OpenStreetMapPlacesUnavailableError(
                f"POI discovery returned no usable results for {city.name}."
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

        for nearby in nearby_places:
            self._canonical_service.resolve_or_create_nearby_place(
                session=session,
                city=city,
                category=category,
                nearby=nearby,
                source_name=source_name,
                licence_identifier=licence_identifier,
                fetched_at=fetched_at,
            )

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

