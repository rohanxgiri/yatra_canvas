"""Cache and persist OpenStreetMap POIs as canonical place candidates."""

import asyncio
import logging
import time
from datetime import datetime, timedelta, timezone
from uuid import UUID

from sqlmodel import Session, select

from app.core.config import Settings
from app.core.request_context import get_request_id
from app.models import City, CityCategoryCache, Place, PlaceSource, PlaceTag
from app.schemas import DiscoveryCategory
from app.services.audiala_places_provider import AudialaPlacesProvider
from app.services.canonical_place_service import (
    CanonicalNearbyCandidate,
    CanonicalPlaceService,
)
from app.services.geoapify_places_provider import GeoapifyPlacesProvider
from app.services.openstreetmap_places_service import (
    OpenStreetMapNearbyPlace,
    OpenStreetMapPlacesError,
    OpenStreetMapPlacesService,
    OpenStreetMapPlacesUnavailableError,
)

logger = logging.getLogger(__name__)


class _SkipOverpass(Exception):
    """Internal control signal for fast speculative prefetch."""


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

    def cache_key(self, category: DiscoveryCategory) -> str:
        """Return the versioned cache key without changing place-category tags."""

        version = self._settings.place_discovery_cache_version
        return category.value if version == 1 else f"v{version}:{category.value}"

    @property
    def has_fast_prefetch_provider(self) -> bool:
        return self._audiala_provider is not None or bool(
            self._geoapify_provider is not None
            and self._geoapify_provider.is_configured
        )

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
        force_refresh_categories: set[DiscoveryCategory] | None = None,
        include_overpass: bool = True,
    ) -> dict[DiscoveryCategory, list[Place]]:
        """Refresh uncached categories with 3-tier cache semantics, Geoapify fallback, and failure isolation."""

        unique_categories = list(dict.fromkeys(categories))
        if not unique_categories:
            return {}

        request_id = get_request_id() or "unscoped"
        now = datetime.now(timezone.utc)
        results: dict[DiscoveryCategory, list[Place]] = {}
        pending: list[DiscoveryCategory] = []
        caches: dict[DiscoveryCategory, CityCategoryCache | None] = {}
        t_start = time.monotonic()

        cache_keys = {
            category: self.cache_key(category) for category in unique_categories
        }
        cache_rows = session.exec(
            select(CityCategoryCache).where(
                CityCategoryCache.city_id == city.id,
                CityCategoryCache.category.in_(list(cache_keys.values())),
            )
        ).all()
        cache_by_key = {cache.category: cache for cache in cache_rows}
        stored_by_category = self._stored_places_many(
            session,
            city.id,
            unique_categories,
        )

        for category in unique_categories:
            cache_key = cache_keys[category]
            cache = cache_by_key.get(cache_key)
            caches[category] = cache
            stored = stored_by_category.get(category, [])
            force_refresh = (
                force_refresh_categories is not None
                and category in force_refresh_categories
            )
            # 3-tier classification:
            # 1. FRESH: cache unexpired and has stored places
            if (
                not force_refresh
                and cache is not None
                and self._as_utc(cache.expires_at) > now
                and stored
            ):
                results[category] = stored
                logger.info(
                    "PREFETCH_CACHE_HIT request_id=%s city_id=%s category=%s cache_key=%s",
                    request_id,
                    city.id,
                    category.value,
                    cache_key,
                )
            # 2. STALE_USABLE: expired cache or unverified, but stored places exist
            elif not force_refresh and stored and prefer_stale:
                results[category] = stored
                logger.info(
                    "PREFETCH_CACHE request_id=%s city_id=%s category=%s "
                    "state=stale_usable count=%d",
                    request_id,
                    city.id,
                    category.value,
                    len(stored),
                )
            # 3. MISSING: no stored places
            else:
                pending.append(category)
                logger.info(
                    "PREFETCH_CACHE_MISS request_id=%s city_id=%s category=%s cache_key=%s",
                    request_id,
                    city.id,
                    category.value,
                    cache_key,
                )

        cache_lookup_ms = (time.monotonic() - t_start) * 1000

        if not pending:
            logger.info(
                "PLACE_DISCOVERY_CACHE_HIT request_id=%s city_id=%s categories=%d "
                "elapsed_ms=%.1f",
                request_id,
                city.id,
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
            "PLACE_DISCOVERY_START request_id=%s city_id=%s categories=%s limits=%s",
            request_id,
            city.id,
            [c.value for c in pending],
            {c.value: category_limits[c] for c in pending},
        )

        provider_outcomes: dict[str, str] = {}

        # Provider 1: Audiala (local dataset, fast)
        audiala_by_category: dict[
            DiscoveryCategory, list[OpenStreetMapNearbyPlace]
        ] = {}
        t_aud = time.monotonic()
        if self._audiala_provider is not None:
            try:
                logger.info(
                    "PLACE_PROVIDER_CATEGORY_START request_id=%s city_id=%s "
                    "provider=audiala categories=%s",
                    request_id,
                    city.id,
                    [category.value for category in pending],
                )
                audiala_by_category = (
                    await self._audiala_provider.search_nearby_places_for_categories(
                        latitude=city.latitude,
                        longitude=city.longitude,
                        categories=pending,
                        category_radii=category_radii,
                        category_limits=category_limits,
                    )
                )
                provider_outcomes["audiala"] = (
                    f"success ({sum(len(p) for p in audiala_by_category.values())} places)"
                )
            except Exception as exc:
                provider_outcomes["audiala"] = f"failed ({type(exc).__name__})"
                logger.warning(
                    "PLACE_PROVIDER_CATEGORY_FAILED request_id=%s city_id=%s "
                    "provider=audiala error_type=%s",
                    request_id,
                    city.id,
                    type(exc).__name__,
                )
        else:
            provider_outcomes["audiala"] = "skipped (none)"
        audiala_ms = (time.monotonic() - t_aud) * 1000

        # Provider 2: Geoapify Places (fast structured hosted API)
        geoapify_by_category: dict[
            DiscoveryCategory, list[OpenStreetMapNearbyPlace]
        ] = {}
        t_geo = time.monotonic()
        if (
            self._geoapify_provider is not None
            and self._geoapify_provider.is_configured
        ):
            try:
                logger.info(
                    "PLACE_PROVIDER_CATEGORY_START request_id=%s city_id=%s "
                    "provider=geoapify categories=%s",
                    request_id,
                    city.id,
                    [category.value for category in pending],
                )
                geoapify_by_category = (
                    await self._geoapify_provider.search_nearby_places_for_categories(
                        latitude=city.latitude,
                        longitude=city.longitude,
                        categories=pending,
                        category_radii=category_radii,
                        category_limits=category_limits,
                    )
                )
                provider_outcomes["geoapify"] = (
                    f"success ({sum(len(p) for p in geoapify_by_category.values())} places)"
                )
            except Exception as exc:
                provider_outcomes["geoapify"] = f"failed ({type(exc).__name__})"
                logger.warning(
                    "PLACE_PROVIDER_CATEGORY_FAILED request_id=%s city_id=%s "
                    "provider=geoapify error_type=%s",
                    request_id,
                    city.id,
                    type(exc).__name__,
                )
        else:
            provider_outcomes["geoapify"] = "skipped (unconfigured)"
        geoapify_ms = (time.monotonic() - t_geo) * 1000

        # Provider 3: Overpass (OSM)
        nearby_by_category: dict[DiscoveryCategory, list[OpenStreetMapNearbyPlace]] = {}
        minimum_usable = self._settings.discovery_min_usable_candidates_per_category
        overpass_pending = [
            category
            for category in pending
            if len(audiala_by_category.get(category, []))
            + len(geoapify_by_category.get(category, []))
            < minimum_usable
        ]
        t_osm = time.monotonic()
        try:
            if not include_overpass:
                provider_outcomes["overpass"] = "skipped (speculative prefetch)"
                raise _SkipOverpass
            if not overpass_pending:
                provider_outcomes["overpass"] = (
                    "skipped (fast-provider coverage sufficient)"
                )
                raise _SkipOverpass
            search_many = getattr(
                self._provider,
                "search_nearby_places_for_categories",
                None,
            )
            if callable(search_many):
                logger.info(
                    "PLACE_PROVIDER_CATEGORY_START request_id=%s city_id=%s "
                    "provider=overpass categories=%s",
                    request_id,
                    city.id,
                    [category.value for category in overpass_pending],
                )
                nearby_by_category = await asyncio.wait_for(
                    search_many(  # type: ignore[misc]
                        latitude=city.latitude,
                        longitude=city.longitude,
                        categories=overpass_pending,
                        category_radii=category_radii,
                        category_limits=category_limits,
                    ),
                    timeout=self._settings.discovery_interactive_timeout_seconds,
                )
                provider_outcomes["overpass"] = (
                    f"success ({sum(len(p) for p in nearby_by_category.values())} places)"
                )
            else:
                for category in overpass_pending:
                    try:
                        logger.info(
                            "PLACE_PROVIDER_CATEGORY_START request_id=%s city_id=%s "
                            "provider=overpass categories=%s",
                            request_id,
                            city.id,
                            [category.value],
                        )
                        try:
                            nearby_by_category[
                                category
                            ] = await self._provider.search_nearby_places(
                                latitude=city.latitude,
                                longitude=city.longitude,
                                category=category,
                                radius_meters=category_radii[category],
                                limit=category_limits[category],
                            )
                        except TypeError:
                            nearby_by_category[
                                category
                            ] = await self._provider.search_nearby_places(
                                latitude=city.latitude,
                                longitude=city.longitude,
                                category=category,
                            )
                    except OpenStreetMapPlacesError as exc:
                        logger.warning(
                            "PLACE_PROVIDER_CATEGORY_FAILED request_id=%s city_id=%s "
                            "provider=overpass category=%s error_type=%s",
                            request_id,
                            city.id,
                            category.value,
                            type(exc).__name__,
                        )
                provider_outcomes["overpass"] = (
                    f"partial/success ({sum(len(p) for p in nearby_by_category.values())} places)"
                )
        except _SkipOverpass:
            pass
        except TimeoutError:
            provider_outcomes["overpass"] = (
                "timed out after "
                f"{self._settings.discovery_interactive_timeout_seconds:.1f}s"
            )
            logger.warning(
                "PLACE_PROVIDER_CATEGORY_FAILED request_id=%s city_id=%s "
                "provider=overpass error_type=TimeoutError budget_seconds=%.1f",
                request_id,
                city.id,
                self._settings.discovery_interactive_timeout_seconds,
            )
        except OpenStreetMapPlacesError as exc:
            provider_outcomes["overpass"] = f"failed ({type(exc).__name__})"
            logger.warning(
                "PLACE_PROVIDER_CATEGORY_FAILED request_id=%s city_id=%s "
                "provider=overpass error_type=%s",
                request_id,
                city.id,
                type(exc).__name__,
            )
        overpass_ms = (time.monotonic() - t_osm) * 1000

        # Persist and update cache
        t_persist = time.monotonic()
        failed_categories: list[DiscoveryCategory] = []
        use_cold_batch = len(unique_categories) == len(DiscoveryCategory) and not any(
            stored_by_category.values()
        )
        if use_cold_batch:
            batch_candidates: list[CanonicalNearbyCandidate] = []
            provider_batches = (
                ("audiala", "CC BY 4.0", audiala_by_category),
                ("geoapify", "Geoapify-Proprietary", geoapify_by_category),
                ("openstreetmap", "ODbL-1.0", nearby_by_category),
            )
            for source_name, licence_identifier, places_by_category in provider_batches:
                for category in pending:
                    batch_candidates.extend(
                        CanonicalNearbyCandidate(
                            category=category,
                            nearby=nearby,
                            source_name=source_name,
                            licence_identifier=licence_identifier,
                        )
                        for nearby in places_by_category.get(category, [])
                    )
            self._canonical_service.create_cold_city_batch(
                session,
                city,
                batch_candidates,
                fetched_at=now,
            )

        for category in pending:
            osm_places = nearby_by_category.get(category, [])
            aud_places = audiala_by_category.get(category, [])
            geo_places = geoapify_by_category.get(category, [])

            has_places = bool(osm_places or aud_places or geo_places)
            if has_places and not use_cold_batch:
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

            if has_places:
                cache = caches.get(category)
                if cache is None:
                    cache = CityCategoryCache(
                        city_id=city.id,
                        category=self.cache_key(category),
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

        stored_after_refresh = self._stored_places_many(session, city.id, pending)

        # Handle failed categories with stale DB fallback
        for category in failed_categories:
            stale_places = stored_after_refresh.get(category, [])
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
                results[category] = stored_after_refresh.get(category, [])

        total_ms = (time.monotonic() - t_start) * 1000
        logger.info(
            "PLACE_DISCOVERY_COMPLETE request_id=%s city_id=%s cache_lookup_ms=%.1f "
            "audiala_ms=%.1f geoapify_ms=%.1f overpass_ms=%.1f persist_ms=%.1f "
            "elapsed_ms=%.1f outcomes=%s",
            request_id,
            city.id,
            cache_lookup_ms,
            audiala_ms,
            geoapify_ms,
            overpass_ms,
            persistence_ms,
            total_ms,
            provider_outcomes,
        )
        logger.info(
            "PREFETCH_COMPLETE request_id=%s city_id=%s categories=%s places=%d "
            "duration_ms=%.1f",
            request_id,
            city.id,
            [category.value for category in pending],
            sum(len(places) for places in results.values()),
            total_ms,
        )

        total_stored = sum(len(p) for p in results.values())
        if (
            total_stored == 0
            and failed_categories
            and len(failed_categories) == len(unique_categories)
        ):
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
        sources_by_external_id = {
            source.external_place_id: source for _, source in old_memberships
        }
        places_by_id: dict[UUID, Place] = {}
        if membership_place_ids:
            existing_places = session.exec(
                select(Place).where(Place.id.in_(membership_place_ids))
            ).all()
            places_by_id = {place.id: place for place in existing_places}
        for nearby in nearby_places:
            source_hint = sources_by_external_id.get(nearby.external_place_id)
            place_hint = (
                places_by_id.get(source_hint.place_id)
                if source_hint is not None
                else None
            )
            identity_hint = (
                (place_hint, source_hint)
                if place_hint is not None and source_hint is not None
                else None
            )
            self._canonical_service.resolve_or_create_nearby_place(
                session=session,
                city=city,
                category=category,
                nearby=nearby,
                source_name=source_name,
                licence_identifier=licence_identifier,
                fetched_at=fetched_at,
                identity_hint=identity_hint,
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
                    Place.moderation_status == "ACTIVE",
                )
                .order_by(Place.name)
            ).all()
        )

    @staticmethod
    def _stored_places_many(
        session: Session,
        city_id: UUID,
        categories: list[DiscoveryCategory],
    ) -> dict[DiscoveryCategory, list[Place]]:
        if not categories:
            return {}
        category_by_value = {category.value: category for category in categories}
        places_by_category: dict[DiscoveryCategory, list[Place]] = {
            category: [] for category in categories
        }
        rows = session.exec(
            select(Place, PlaceTag.tag)
            .join(PlaceTag, PlaceTag.place_id == Place.id)
            .where(
                Place.city_id == city_id,
                PlaceTag.tag.in_(list(category_by_value)),
                Place.moderation_status == "ACTIVE",
            )
            .order_by(Place.name)
        ).all()

        for place, tag in rows:
            category = category_by_value.get(tag)
            if category is not None:
                places_by_category[category].append(place)
        return places_by_category

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

    def _existing_external_ids(
        self, session: Session, city_id: UUID, places: list[OpenStreetMapNearbyPlace]
    ) -> set[str]:
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
