"""Cache and persist OpenStreetMap POIs as canonical place candidates."""

from datetime import datetime, timedelta, timezone
from uuid import UUID

from sqlmodel import Session, select

from app.core.config import Settings
from app.models import City, CityCategoryCache, Place, PlaceSource, PlaceTag
from app.schemas import DiscoveryCategory
from app.services.openstreetmap_places_service import (
    OpenStreetMapNearbyPlace,
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
        now = datetime.now(timezone.utc)
        cache = session.exec(
            select(CityCategoryCache).where(
                CityCategoryCache.city_id == city.id,
                CityCategoryCache.category == category.value,
            )
        ).first()
        if cache is not None and self._as_utc(cache.expires_at) > now:
            return self._stored_places(session, city.id, category)

        nearby_places = await self._provider.search_nearby_places(
            latitude=city.latitude,
            longitude=city.longitude,
            category=category,
        )

        current_external_ids = {nearby.external_place_id for nearby in nearby_places}
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
        for membership, source in old_memberships:
            if source.external_place_id in current_external_ids:
                continue
            has_another_source = session.exec(
                select(PlaceSource.id).where(
                    PlaceSource.place_id == membership.place_id,
                    PlaceSource.source != "openstreetmap",
                )
            ).first()
            if has_another_source is not None:
                continue
            session.delete(membership)
        session.flush()

        for nearby in nearby_places:
            place = self._upsert_place(
                session=session,
                city=city,
                category=category,
                nearby=nearby,
                fetched_at=now,
            )
            self._add_missing_tags(session, place, {category.value})

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
        session.commit()
        return self._stored_places(session, city.id, category)

    @staticmethod
    def _upsert_place(
        *,
        session: Session,
        city: City,
        category: DiscoveryCategory,
        nearby: OpenStreetMapNearbyPlace,
        fetched_at: datetime,
    ) -> Place:
        source = session.exec(
            select(PlaceSource).where(
                PlaceSource.source == "openstreetmap",
                PlaceSource.external_place_id == nearby.external_place_id,
            )
        ).first()
        place = session.get(Place, source.place_id) if source is not None else None
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
            session.add(
                PlaceSource(
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
            )
        else:
            source.source_url = nearby.source_url
            source.website = OpenStreetMapDiscoveryService._bounded(
                nearby.tags.get("website"), 1000
            )
            source.telephone = OpenStreetMapDiscoveryService._bounded(
                nearby.tags.get("phone"), 80
            )
            source.last_fetched_at = fetched_at
        return place

    @staticmethod
    def _add_missing_tags(
        session: Session,
        place: Place,
        tags: set[str],
    ) -> None:
        existing = set(
            session.exec(
                select(PlaceTag.tag).where(PlaceTag.place_id == place.id)
            ).all()
        )
        for tag in sorted(tags - existing):
            session.add(PlaceTag(place_id=place.id, tag=tag))

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
