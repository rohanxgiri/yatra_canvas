"""Cache fallback behavior for OpenStreetMap place discovery."""

import asyncio
from collections.abc import Generator

import pytest
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.core.config import Settings
from app.models import City, Place, PlaceTag
from app.schemas import DiscoveryCategory
from app.services.openstreetmap_discovery_service import (
    OpenStreetMapDiscoveryService,
)
from app.services.openstreetmap_places_service import (
    OpenStreetMapNearbyPlace,
    OpenStreetMapPlacesUnavailableError,
)


class UnavailableProvider:
    async def search_nearby_places(self, **_: object) -> list[object]:
        raise OpenStreetMapPlacesUnavailableError(
            "OpenStreetMap discovery is temporarily unavailable."
        )


class BatchProvider:
    def __init__(self) -> None:
        self.calls = 0

    async def search_nearby_places_for_categories(
        self,
        *,
        categories: list[DiscoveryCategory],
        **_: object,
    ) -> dict[DiscoveryCategory, list[OpenStreetMapNearbyPlace]]:
        self.calls += 1
        assert categories == [DiscoveryCategory.FOOD, DiscoveryCategory.HERITAGE]
        shared = OpenStreetMapNearbyPlace(
            external_place_id="node/42",
            source_url="https://www.openstreetmap.org/node/42",
            name="Historic Restaurant",
            latitude=32.24,
            longitude=77.18,
            tags={"amenity": "restaurant", "historic": "yes"},
        )
        return {
            DiscoveryCategory.FOOD: [shared],
            DiscoveryCategory.HERITAGE: [shared],
        }


@pytest.fixture
def session() -> Generator[Session, None, None]:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)
    with Session(engine) as value:
        yield value
    SQLModel.metadata.drop_all(engine)


def _service() -> OpenStreetMapDiscoveryService:
    settings = Settings(DATABASE_URL="postgresql://example.invalid/yatra")
    return OpenStreetMapDiscoveryService(settings, UnavailableProvider())  # type: ignore[arg-type]


def _city(session: Session) -> City:
    city = City(
        name="Manali",
        state="Himachal Pradesh",
        country="India",
        latitude=32.2454608,
        longitude=77.1872926,
    )
    session.add(city)
    session.commit()
    session.refresh(city)
    return city


def test_stored_places_are_served_when_overpass_refresh_fails(
    session: Session,
) -> None:
    city = _city(session)
    place = Place(
        city_id=city.id,
        name="Hadimba Devi Temple",
        category="religious",
        latitude=32.2483855,
        longitude=77.1809861,
        review_count=0,
    )
    session.add(place)
    session.flush()
    session.add(PlaceTag(place_id=place.id, tag="religious"))
    session.commit()

    result = asyncio.run(
        _service().discover(
            session=session,
            city=city,
            category=DiscoveryCategory.RELIGIOUS,
        )
    )

    assert [item.name for item in result] == ["Hadimba Devi Temple"]


def test_provider_failure_is_preserved_without_stored_places(
    session: Session,
) -> None:
    city = _city(session)

    with pytest.raises(OpenStreetMapPlacesUnavailableError):
        asyncio.run(
            _service().discover(
                session=session,
                city=city,
                category=DiscoveryCategory.RELIGIOUS,
            )
        )


def test_uncached_categories_are_fetched_once_and_persisted_with_all_tags(
    session: Session,
) -> None:
    city = _city(session)
    provider = BatchProvider()
    settings = Settings(DATABASE_URL="postgresql://example.invalid/yatra")
    service = OpenStreetMapDiscoveryService(settings, provider)  # type: ignore[arg-type]

    result = asyncio.run(
        service.discover_many(
            session=session,
            city=city,
            categories=[DiscoveryCategory.FOOD, DiscoveryCategory.HERITAGE],
        )
    )

    assert provider.calls == 1
    assert [place.name for place in result[DiscoveryCategory.FOOD]] == [
        "Historic Restaurant"
    ]
    assert [place.name for place in result[DiscoveryCategory.HERITAGE]] == [
        "Historic Restaurant"
    ]
    place = result[DiscoveryCategory.FOOD][0]
    tags = session.exec(select(PlaceTag.tag).where(PlaceTag.place_id == place.id)).all()
    assert set(tags) == {"food", "heritage"}


def test_cross_category_duplicate_merges_into_canonical_place(session: Session) -> None:
    """Test C: Landmark appearing in both tourism and heritage becomes one canonical candidate with all tags."""

    city = _city(session)
    shared_monument = OpenStreetMapNearbyPlace(
        external_place_id="way/9001",
        source_url="https://www.openstreetmap.org/way/9001",
        name="Red Fort",
        latitude=28.6562,
        longitude=77.2410,
        tags={"tourism": "attraction", "historic": "monument", "heritage": "1"},
    )

    class MultiCategoryProvider:
        async def search_nearby_places_for_categories(
            self,
            *,
            categories: list[DiscoveryCategory],
            **_: object,
        ) -> dict[DiscoveryCategory, list[OpenStreetMapNearbyPlace]]:
            return {
                DiscoveryCategory.TOURISM: [shared_monument],
                DiscoveryCategory.HERITAGE: [shared_monument],
            }

    settings = Settings(DATABASE_URL="postgresql://example.invalid/yatra")
    service = OpenStreetMapDiscoveryService(settings, MultiCategoryProvider())  # type: ignore[arg-type]

    result = asyncio.run(
        service.discover_many(
            session=session,
            city=city,
            categories=[DiscoveryCategory.TOURISM, DiscoveryCategory.HERITAGE],
        )
    )

    tourism_places = result[DiscoveryCategory.TOURISM]
    heritage_places = result[DiscoveryCategory.HERITAGE]

    assert len(tourism_places) == 1
    assert len(heritage_places) == 1
    # Canonical identity: exactly the same database Place record
    assert tourism_places[0].id == heritage_places[0].id
    assert tourism_places[0].name == "Red Fort"
    assert tourism_places[0].is_heritage is True

    # Exactly 1 Place record created in the database, not 2
    all_places = session.exec(select(Place).where(Place.city_id == city.id)).all()
    assert len(all_places) == 1

    # Both tags accumulated on the single canonical place
    tags = session.exec(
        select(PlaceTag.tag).where(PlaceTag.place_id == tourism_places[0].id)
    ).all()
    assert set(tags) == {"tourism", "heritage"}


def test_partial_provider_failure_retains_successful_categories(session: Session) -> None:
    """Test F: When heritage query fails, food succeeds and discovery completes gracefully."""

    city = _city(session)
    food_place = OpenStreetMapNearbyPlace(
        external_place_id="node/123",
        source_url="https://www.openstreetmap.org/node/123",
        name="Haldiram's",
        latitude=28.63,
        longitude=77.22,
        tags={"amenity": "restaurant"},
    )

    class PartialFailProvider:
        async def search_nearby_places_for_categories(
            self,
            *,
            categories: list[DiscoveryCategory],
            **_: object,
        ) -> dict[DiscoveryCategory, list[OpenStreetMapNearbyPlace]]:
            # Heritage fails and is omitted; Food succeeds
            return {
                DiscoveryCategory.FOOD: [food_place],
            }

    settings = Settings(DATABASE_URL="postgresql://example.invalid/yatra")
    service = OpenStreetMapDiscoveryService(settings, PartialFailProvider())  # type: ignore[arg-type]

    result = asyncio.run(
        service.discover_many(
            session=session,
            city=city,
            categories=[DiscoveryCategory.FOOD, DiscoveryCategory.HERITAGE],
        )
    )

    assert len(result[DiscoveryCategory.FOOD]) == 1
    assert result[DiscoveryCategory.FOOD][0].name == "Haldiram's"
    # Heritage failed and had no stale cache, returns empty gracefully without crashing
    assert result[DiscoveryCategory.HERITAGE] == []


def test_large_candidate_pool_merge_dedup_and_recommendation(session: Session) -> None:
    """Test G: >300 synthetic candidates across categories merge, deduplicate, and score without error."""

    from app.schemas.recommendation import RecommendationRequest
    from app.services.recommendation_service import RecommendationService

    city = _city(session)

    # Build >300 synthetic places across 5 categories
    candidates_by_cat: dict[DiscoveryCategory, list[OpenStreetMapNearbyPlace]] = {
        DiscoveryCategory.TOURISM: [
            OpenStreetMapNearbyPlace(
                external_place_id=f"way/tourism_{i}",
                source_url=f"https://www.openstreetmap.org/way/tourism_{i}",
                name=f"Major Attraction {i}",
                latitude=28.60 + (i * 0.002),
                longitude=77.20 + (i * 0.002),
                tags={"tourism": "attraction"},
            )
            for i in range(70)
        ],
        DiscoveryCategory.HERITAGE: [
            OpenStreetMapNearbyPlace(
                external_place_id=f"relation/heritage_{i}",
                source_url=f"https://www.openstreetmap.org/relation/heritage_{i}",
                name=f"Historic Monument {i}",
                latitude=28.61 + (i * 0.002),
                longitude=77.21 + (i * 0.002),
                tags={"historic": "monument"},
            )
            for i in range(65)
        ],
        DiscoveryCategory.RELIGIOUS: [
            OpenStreetMapNearbyPlace(
                external_place_id=f"node/religious_{i}",
                source_url=f"https://www.openstreetmap.org/node/religious_{i}",
                name=f"Sacred Temple {i}",
                latitude=28.58 + (i * 0.002),
                longitude=77.18 + (i * 0.002),
                tags={"amenity": "place_of_worship", "religion": "hindu"},
            )
            for i in range(50)
        ],
        DiscoveryCategory.FOOD: [
            OpenStreetMapNearbyPlace(
                external_place_id=f"node/food_{i}",
                source_url=f"https://www.openstreetmap.org/node/food_{i}",
                name=f"Famous Eatery {i}",
                latitude=28.62 + (i * 0.001),
                longitude=77.22 + (i * 0.001),
                tags={"amenity": "restaurant"},
            )
            for i in range(80)
        ],
        DiscoveryCategory.CAFES: [
            OpenStreetMapNearbyPlace(
                external_place_id=f"node/cafe_{i}",
                source_url=f"https://www.openstreetmap.org/node/cafe_{i}",
                name=f"Artisan Cafe {i}",
                latitude=28.63 + (i * 0.001),
                longitude=77.23 + (i * 0.001),
                tags={"amenity": "cafe"},
            )
            for i in range(55)
        ],
    }

    # Total synthetic candidates = 70 + 65 + 50 + 80 + 55 = 320 candidates (>300)
    total_raw = sum(len(v) for v in candidates_by_cat.values())
    assert total_raw > 300

    class BigPoolProvider:
        async def search_nearby_places_for_categories(
            self,
            *,
            categories: list[DiscoveryCategory],
            **_: object,
        ) -> dict[DiscoveryCategory, list[OpenStreetMapNearbyPlace]]:
            return {cat: candidates_by_cat[cat] for cat in categories}

    settings = Settings(DATABASE_URL="postgresql://example.invalid/yatra")
    discovery_service = OpenStreetMapDiscoveryService(settings, BigPoolProvider())  # type: ignore[arg-type]
    rec_service = RecommendationService(discovery_service)

    req = RecommendationRequest(
        categories=[
            DiscoveryCategory.TOURISM,
            DiscoveryCategory.HERITAGE,
            DiscoveryCategory.RELIGIOUS,
            DiscoveryCategory.FOOD,
            DiscoveryCategory.CAFES,
        ],
        limit=30,
    )

    recommendations = asyncio.run(
        rec_service.recommend(
            session=session,
            city=city,
            request=req,
        )
    )

    assert len(recommendations) <= 30
    assert len(recommendations) > 0
    # Verify no duplicate IDs in recommendations
    rec_ids = [r.id for r in recommendations]
    assert len(rec_ids) == len(set(rec_ids))


def test_institutional_dining_regression_exclusion() -> None:
    """Test H: Ensure institutional dining (college canteen, student mess, staff cafeteria) is excluded."""

    from app.services.place_suitability_service import is_traveller_suitable

    # Institutional dining must be rejected
    rejected_cases = [
        ("Delhi University College Canteen", "food", {"amenity": "canteen"}),
        ("IIT Bombay Student Mess", "food", {"amenity": "canteen"}),
        ("Railway Staff Cafeteria", "food", {"amenity": "canteen"}),
        ("Hostel Dining Hall", "food", {"amenity": "restaurant"}),
        ("Police Headquarters Mess", "food", {"amenity": "restaurant"}),
        ("Medical College Canteen", "cafes", {"amenity": "cafe"}),
    ]

    for name, cat, tags in rejected_cases:
        suitable, _ = is_traveller_suitable(name=name, category=cat, tags=tags)
        assert not suitable, f"Expected {name} to be excluded as non-suitable institutional dining"

    # Legitimate public places must be accepted
    accepted_cases = [
        ("Karim's Restaurant", "food", {"amenity": "restaurant"}),
        ("Indian Coffee House", "cafes", {"amenity": "cafe"}),
        ("Saravana Bhavan", "food", {"amenity": "restaurant"}),
        ("Glenary's Bakery & Cafe", "cafes", {"amenity": "cafe"}),
    ]

    for name, cat, tags in accepted_cases:
        suitable, _ = is_traveller_suitable(name=name, category=cat, tags=tags)
        assert suitable, f"Expected {name} to be accepted as suitable public dining"

