"""Cache and persist OpenStreetMap POIs as canonical place candidates."""

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
)


class OpenStreetMapDiscoveryService:
    def __init__(
        self,
        settings: Settings,
        provider: OpenStreetMapPlacesService,
    ) -> None:
        self._cache_ttl = timedelta(hours=settings.place_discovery_cache_ttl_hours)
        self._provider = provider

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
        """Refresh uncached categories together and return every requested category."""

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

        try:
            search_many = getattr(
                self._provider,
                "search_nearby_places_for_categories",
                None,
            )
            if len(pending) > 1 and callable(search_many):
                nearby_by_category = await search_many(
                    latitude=city.latitude,
                    longitude=city.longitude,
                    categories=pending,
                )
            else:
                nearby_by_category = {}
                for category in pending:
                    nearby_by_category[
                        category
                    ] = await self._provider.search_nearby_places(
                        latitude=city.latitude,
                        longitude=city.longitude,
                        category=category,
                    )
        except OpenStreetMapPlacesError:
            has_stale_places = False
            for category in pending:
                stale_places = self._stored_places(session, city.id, category)
                results[category] = stale_places
                has_stale_places = has_stale_places or bool(stale_places)
            if has_stale_places:
                return results
            raise

        for category in pending:
            self._persist_category(
                session=session,
                city=city,
                category=category,
                nearby_places=nearby_by_category.get(category, []),
                fetched_at=now,
                cache=caches[category],
            )
        session.commit()
        for category in pending:
            results[category] = self._stored_places(session, city.id, category)
        return results

    def _persist_category(
        self,
        *,
        session: Session,
        city: City,
        category: DiscoveryCategory,
        nearby_places: list[OpenStreetMapNearbyPlace],
        fetched_at: datetime,
        cache: CityCategoryCache | None,
    ) -> None:
        current_external_ids = [nearby.external_place_id for nearby in nearby_places]
        current_external_ids_set = set(current_external_ids)

        old_memberships = session.exec(
            select(PlaceTag, PlaceSource)
            .join(Place, Place.id == PlaceTag.place_id)
            .join(PlaceSource, PlaceSource.place_id == Place.id)
            .where(
                Place.city_id == city.id,
                PlaceTag.tag == category.value,
                PlaceSource.source == "openstreetmap",
            )
        ).all()

        membership_place_ids = [m.place_id for m, _ in old_memberships]
        other_sources_set = set()
        if membership_place_ids:
            other_sources = session.exec(
                select(PlaceSource.place_id).where(
                    PlaceSource.place_id.in_(membership_place_ids),  # type: ignore[union-attr]
                    PlaceSource.source != "openstreetmap",
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
                    PlaceSource.source == "openstreetmap",
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
                    source="openstreetmap",
                    external_place_id=nearby.external_place_id,
                    source_url=nearby.source_url,
                    licence_identifier="ODbL-1.0",
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

        if cache is None:
            cache = CityCategoryCache(
                city_id=city.id,
                category=category.value,
                last_fetched_at=fetched_at,
                expires_at=fetched_at + self._cache_ttl,
            )
            session.add(cache)
        else:
            cache.last_fetched_at = fetched_at
            cache.expires_at = fetched_at + self._cache_ttl

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
