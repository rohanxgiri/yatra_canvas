"""Cache-aware discovery and persistence for Google nearby places."""

from datetime import datetime, timedelta, timezone
from uuid import UUID

from sqlmodel import Session, select

from app.core.config import Settings
from app.models import City, CityCategoryCache, Place, PlaceSource, PlaceTag
from app.schemas import DiscoveryCategory, GoogleNearbyPlace
from app.services.google_places_service import GooglePlacesService


# Only Places API (New) Table A types are sent to Nearby Search.
GOOGLE_TYPES_BY_CATEGORY: dict[DiscoveryCategory, tuple[str, ...]] = {
    DiscoveryCategory.RELIGIOUS: (
        "hindu_temple",
        "mosque",
        "church",
        "buddhist_temple",
        "synagogue",
    ),
    DiscoveryCategory.FOOD: (
        "restaurant",
        "indian_restaurant",
        "meal_takeaway",
        "food_court",
    ),
    DiscoveryCategory.TOURISM: (
        "tourist_attraction",
        "museum",
        "park",
        "national_park",
        "scenic_spot",
        "monument",
        "cultural_landmark",
    ),
    DiscoveryCategory.CAFES: (
        "cafe",
        "coffee_shop",
        "tea_house",
    ),
    DiscoveryCategory.HERITAGE: (
        "historical_place",
        "historical_landmark",
        "cultural_landmark",
        "monument",
    ),
}

HERITAGE_GOOGLE_TYPES = frozenset(
    GOOGLE_TYPES_BY_CATEGORY[DiscoveryCategory.HERITAGE]
)

TAGS_BY_GOOGLE_TYPE: dict[str, frozenset[str]] = {
    "hindu_temple": frozenset({"religious", "temple"}),
    "buddhist_temple": frozenset({"religious", "temple"}),
    "mosque": frozenset({"religious", "mosque"}),
    "church": frozenset({"religious", "church"}),
    "synagogue": frozenset({"religious", "synagogue"}),
    "restaurant": frozenset({"food", "restaurant"}),
    "indian_restaurant": frozenset({"food", "restaurant", "indian_food"}),
    "meal_takeaway": frozenset({"food", "takeaway"}),
    "food_court": frozenset({"food", "food_court"}),
    "cafe": frozenset({"cafes", "cafe"}),
    "coffee_shop": frozenset({"cafes", "coffee"}),
    "tea_house": frozenset({"cafes", "tea"}),
    "tourist_attraction": frozenset({"tourism", "attraction"}),
    "museum": frozenset({"tourism", "museum"}),
    "park": frozenset({"tourism", "park"}),
    "national_park": frozenset({"tourism", "park"}),
    "scenic_spot": frozenset({"tourism", "scenic"}),
    "historical_place": frozenset({"heritage", "historical"}),
    "historical_landmark": frozenset({"heritage", "landmark"}),
    "cultural_landmark": frozenset({"heritage", "cultural"}),
    "monument": frozenset({"heritage", "monument"}),
}


class PlaceDiscoveryService:
    """Discover places once, then serve category membership from Supabase."""

    def __init__(self, settings: Settings) -> None:
        self._cache_ttl = timedelta(
            hours=settings.place_discovery_cache_ttl_hours
        )
        self._radius_meters = settings.google_nearby_radius_meters
        self._popular_min_rating = settings.place_popular_min_rating
        self._popular_min_reviews = settings.place_popular_min_review_count

    async def discover(
        self,
        *,
        session: Session,
        city: City,
        category: DiscoveryCategory,
        google_places: GooglePlacesService,
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

        nearby_places = await google_places.search_nearby_places(
            latitude=city.latitude,
            longitude=city.longitude,
            included_types=GOOGLE_TYPES_BY_CATEGORY[category],
            radius_meters=self._radius_meters,
        )

        # Category tags also act as cache membership. Replace only this city's
        # membership after a successful Google response, leaving other tags and
        # categories untouched.
        old_memberships = session.exec(
            select(PlaceTag)
            .join(Place, Place.id == PlaceTag.place_id)
            .where(
                Place.city_id == city.id,
                PlaceTag.tag == category.value,
            )
        ).all()
        for membership in old_memberships:
            session.delete(membership)
        session.flush()

        for nearby in nearby_places:
            place = self._upsert_google_place(
                session=session,
                city=city,
                category=category,
                nearby=nearby,
                fetched_at=now,
            )
            self._add_missing_tags(
                session,
                place,
                self._tags_for(nearby, category),
            )

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

    def _upsert_google_place(
        self,
        *,
        session: Session,
        city: City,
        category: DiscoveryCategory,
        nearby: GoogleNearbyPlace,
        fetched_at: datetime,
    ) -> Place:
        source = session.exec(
            select(PlaceSource).where(
                PlaceSource.source == "google",
                PlaceSource.external_place_id == nearby.google_place_id,
            )
        ).first()
        place = (
            session.get(Place, source.place_id)
            if source is not None
            else None
        )

        is_popular = (
            nearby.rating is not None
            and nearby.rating >= self._popular_min_rating
            and nearby.review_count >= self._popular_min_reviews
        )
        is_heritage = (
            (place.is_heritage if place is not None else False)
            or category is DiscoveryCategory.HERITAGE
            or bool(set(nearby.types) & HERITAGE_GOOGLE_TYPES)
            or nearby.primary_type in HERITAGE_GOOGLE_TYPES
        )

        if place is None:
            place = Place(
                city_id=city.id,
                name=nearby.name,
                category=category.value,
                latitude=nearby.latitude,
                longitude=nearby.longitude,
                rating=nearby.rating,
                review_count=nearby.review_count,
                is_popular=is_popular,
                is_heritage=is_heritage,
                is_local_speciality=False,
                last_fetched_at=fetched_at,
            )
            session.add(place)
            session.flush()
        else:
            place.city_id = city.id
            place.name = nearby.name
            place.category = category.value
            place.latitude = nearby.latitude
            place.longitude = nearby.longitude
            place.rating = nearby.rating
            place.review_count = nearby.review_count
            place.is_popular = is_popular
            place.is_heritage = is_heritage
            place.is_local_speciality = False
            place.last_fetched_at = fetched_at

        if source is None:
            source = PlaceSource(
                place_id=place.id,
                source="google",
                external_place_id=nearby.google_place_id,
                last_fetched_at=fetched_at,
            )
            session.add(source)
        else:
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
    def _tags_for(
        nearby: GoogleNearbyPlace,
        category: DiscoveryCategory,
    ) -> set[str]:
        tags = {category.value}
        google_types = set(nearby.types)
        if nearby.primary_type:
            google_types.add(nearby.primary_type)
        for google_type in google_types:
            tags.update(TAGS_BY_GOOGLE_TYPE.get(google_type, ()))
        return tags

    @staticmethod
    def _stored_places(
        session: Session,
        city_id: UUID,
        category: DiscoveryCategory,
    ) -> list[Place]:
        statement = (
            select(Place)
            .join(PlaceTag, PlaceTag.place_id == Place.id)
            .where(
                Place.city_id == city_id,
                PlaceTag.tag == category.value,
            )
            .order_by(
                Place.is_popular.desc(),
                Place.rating.desc(),
                Place.review_count.desc(),
                Place.name,
            )
        )
        return list(session.exec(statement).all())

    @staticmethod
    def _as_utc(value: datetime) -> datetime:
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)
