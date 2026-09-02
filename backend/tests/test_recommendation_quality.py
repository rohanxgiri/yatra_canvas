"""Unit and integration tests for place discovery and recommendation quality."""

from datetime import datetime, timezone
from uuid import UUID, uuid4

import pytest
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.models.entities import City, Place, PlaceSource, PlaceTag, UserSavedPlace
from app.schemas.recommendation import DiscoveryCategory, RecommendationRequest
from app.services.place_deduplication_service import (
    are_names_similar,
    deduplicate_places,
    haversine_distance_meters,
)
from app.services.place_suitability_service import (
    AccessConfidence,
    evaluate_access_confidence,
    is_traveller_suitable,
)
from app.services.recommendation_service import (
    RecommendationService,
    calculate_recommendation_score,
)


class MockDiscovery:
    def __init__(self, places_by_cat: dict[DiscoveryCategory, list[Place]]) -> None:
        self._places_by_cat = places_by_cat

    async def discover_many(
        self,
        *,
        session: Session,
        city: City,
        categories: list[DiscoveryCategory],
    ) -> dict[DiscoveryCategory, list[Place]]:
        return {cat: self._places_by_cat.get(cat, []) for cat in categories}


@pytest.fixture
def session():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)
    with Session(engine) as s:
        yield s


def test_access_confidence_and_suitability():
    """Verify context-based rules correctly classify public vs institutional venues without hardcoding names."""
    # 1. Clear public venues
    suitable, conf = is_traveller_suitable(name="Kansar Gujarati Thali", category="restaurant")
    assert suitable is True
    assert conf == AccessConfidence.PUBLIC_LIKELY

    suitable, conf = is_traveller_suitable(name="Cafe Beats", category="cafes")
    assert suitable is True
    assert conf == AccessConfidence.PUBLIC_LIKELY

    # 2. Institutional canteens & student messes (general keyword patterns)
    suitable, conf = is_traveller_suitable(name="SVNIT Student Canteen", category="food")
    assert suitable is False
    assert conf == AccessConfidence.RESTRICTED_LIKELY

    suitable, conf = is_traveller_suitable(name="Hostel Mess 4", category="food")
    assert suitable is False
    assert conf == AccessConfidence.RESTRICTED_LIKELY

    suitable, conf = is_traveller_suitable(name="Employee Dining Hall", category="food")
    assert suitable is False
    assert conf == AccessConfidence.RESTRICTED_LIKELY

    suitable, conf = is_traveller_suitable(name="College Canteen", category="food")
    assert suitable is False
    assert conf == AccessConfidence.RESTRICTED_LIKELY

    # 3. Explicit tags
    suitable, conf = is_traveller_suitable(
        name="Tech Park Cafeteria",
        category="food",
        tags={"access": "private"},
    )
    assert suitable is False
    assert conf == AccessConfidence.RESTRICTED

    # 4. Explicit public access overrides canteen name
    suitable, conf = is_traveller_suitable(
        name="Public Beach Canteen",
        category="food",
        tags={"access": "yes"},
    )
    assert suitable is True
    assert conf == AccessConfidence.PUBLIC_LIKELY


def test_spatial_and_name_deduplication():
    """Verify deduplication resolves close duplicates while preserving separate branches."""
    # 1. Close duplicates (within 75m, similar name)
    p1 = Place(id=uuid4(), city_id=uuid4(), name="Sasumaa Gujarati Thali", category="food", latitude=21.1700, longitude=72.8300)
    p2 = Place(id=uuid4(), city_id=uuid4(), name="Sasumaa Thali Restaurant", category="food", latitude=21.1702, longitude=72.8301)  # ~25m away

    deduped = deduplicate_places([p1, p2])
    assert len(deduped) == 1

    # 2. Separate branches of same chain (e.g. 4 km apart)
    b1 = Place(id=uuid4(), city_id=uuid4(), name="Starbucks Coffee", category="cafes", latitude=21.1700, longitude=72.8300)
    b2 = Place(id=uuid4(), city_id=uuid4(), name="Starbucks Coffee", category="cafes", latitude=21.2100, longitude=72.8500)  # ~4.5 km away

    deduped_branches = deduplicate_places([b1, b2])
    assert len(deduped_branches) == 2


@pytest.mark.anyio
async def test_svnit_type_case_recommendation_pipeline(session):
    """Regression test: in Surat with FOOD purpose, institutional canteens are excluded and duplicates merged."""
    city = City(id=uuid4(), name="Surat", country="India", latitude=21.1702, longitude=72.8311)
    session.add(city)

    # 1. Legitimate public restaurant
    p_thali = Place(
        id=uuid4(),
        city_id=city.id,
        name="Sasumaa Gujarati Thali",
        category="food",
        latitude=21.1710,
        longitude=72.8315,
        rating=4.5,
        review_count=1200,
        is_popular=True,
        is_local_speciality=True,
    )
    # 2. Duplicate of thali from another OSM way (30m away)
    p_thali_dup = Place(
        id=uuid4(),
        city_id=city.id,
        name="Sasumaa Thali Restaurant",
        category="food",
        latitude=21.1712,
        longitude=72.8317,
        rating=4.4,
        review_count=800,
    )
    # 3. SVNIT Student Canteen (institutional)
    p_canteen = Place(
        id=uuid4(),
        city_id=city.id,
        name="SVNIT Student Canteen",
        category="food",
        latitude=21.1660,
        longitude=72.7830,
        rating=None,
        review_count=0,
    )
    # 4. Staff Dining (institutional)
    p_staff_mess = Place(
        id=uuid4(),
        city_id=city.id,
        name="L&T Employee Cafeteria",
        category="food",
        latitude=21.1500,
        longitude=72.8000,
        rating=None,
        review_count=0,
    )
    # 5. Public Cafe
    p_cafe = Place(
        id=uuid4(),
        city_id=city.id,
        name="Nomad Coffee House",
        category="cafes",
        latitude=21.1750,
        longitude=72.8250,
        rating=4.2,
        review_count=350,
    )
    # 6. Street Food Stall
    p_locho = Place(
        id=uuid4(),
        city_id=city.id,
        name="Jaani Locho Centre",
        category="food",
        latitude=21.1720,
        longitude=72.8330,
        rating=4.6,
        review_count=2100,
        is_local_speciality=True,
    )

    all_places = [p_thali, p_thali_dup, p_canteen, p_staff_mess, p_cafe, p_locho]
    session.add_all(all_places)
    session.commit()

    discovery = MockDiscovery({
        DiscoveryCategory.FOOD: [p_thali, p_thali_dup, p_canteen, p_staff_mess, p_locho],
        DiscoveryCategory.CAFES: [p_cafe],
    })

    service = RecommendationService(discovery=discovery)
    results = await service.recommend(
        session=session,
        city=city,
        request=RecommendationRequest(categories=[DiscoveryCategory.FOOD, DiscoveryCategory.CAFES]),
    )

    result_names = [r.name for r in results]

    # Verify institutional canteens are excluded
    assert "SVNIT Student Canteen" not in result_names
    assert "L&T Employee Cafeteria" not in result_names

    # Verify duplicate thali restaurant is merged (only 1 thali result)
    thali_count = sum(1 for name in result_names if "Sasumaa" in name)
    assert thali_count == 1

    # Verify public restaurants & local speciality rank at the top
    assert len(results) == 3  # Thali, Locho, and Nomad Cafe
    top_place = results[0]
    assert top_place.access_confidence == "PUBLIC_LIKELY"
    assert top_place.recommendation_reason is not None
    assert "food" in top_place.recommendation_reason.casefold() or "speciality" in top_place.recommendation_reason.casefold()


@pytest.mark.anyio
async def test_saved_place_marked_in_recommendations(session):
    """Verify that a place already saved in a trip is returned with is_saved=True."""
    city = City(id=uuid4(), name="Jaipur", country="India", latitude=26.91, longitude=75.78)
    session.add(city)

    p1 = Place(id=uuid4(), city_id=city.id, name="Hawa Mahal", category="heritage", latitude=26.92, longitude=75.82)
    p2 = Place(id=uuid4(), city_id=city.id, name="City Palace", category="heritage", latitude=26.93, longitude=75.83)
    session.add_all([p1, p2])

    trip_id = uuid4()
    session.add(UserSavedPlace(trip_id=trip_id, place_id=p1.id, custom_order=1))
    session.commit()

    discovery = MockDiscovery({
        DiscoveryCategory.HERITAGE: [p1, p2],
    })
    service = RecommendationService(discovery=discovery)
    results = await service.recommend(
        session=session,
        city=city,
        request=RecommendationRequest(categories=[DiscoveryCategory.HERITAGE], trip_id=trip_id),
    )

    by_id = {r.id: r for r in results}
    assert by_id[p1.id].is_saved is True
    assert by_id[p2.id].is_saved is False


@pytest.mark.anyio
async def test_other_trip_purposes_suitability_filtering(session):
    """Verify traveller suitability filtering works generally across religious, heritage, and tourism."""
    city = City(id=uuid4(), name="Varanasi", country="India", latitude=25.31, longitude=82.97)
    session.add(city)

    # Religious: public temple vs internal staff canteen
    t1 = Place(id=uuid4(), city_id=city.id, name="Kashi Vishwanath Temple", category="religious", latitude=25.31, longitude=82.97)
    t2 = Place(id=uuid4(), city_id=city.id, name="Temple Trust Staff Canteen", category="religious", latitude=25.31, longitude=82.97)

    # Tourism/Heritage: public fort vs office facility
    h1 = Place(id=uuid4(), city_id=city.id, name="Ramnagar Fort", category="heritage", latitude=25.26, longitude=83.02)
    h2 = Place(id=uuid4(), city_id=city.id, name="Administrative Officers Mess", category="heritage", latitude=25.26, longitude=83.02)

    session.add_all([t1, t2, h1, h2])
    session.commit()

    discovery = MockDiscovery({
        DiscoveryCategory.RELIGIOUS: [t1, t2],
        DiscoveryCategory.HERITAGE: [h1, h2],
    })
    service = RecommendationService(discovery=discovery)
    results = await service.recommend(
        session=session,
        city=city,
        request=RecommendationRequest(categories=[DiscoveryCategory.RELIGIOUS, DiscoveryCategory.HERITAGE]),
    )

    names = [r.name for r in results]
    assert "Kashi Vishwanath Temple" in names
    assert "Ramnagar Fort" in names
    assert "Temple Trust Staff Canteen" not in names
    assert "Administrative Officers Mess" not in names


@pytest.mark.anyio
async def test_low_confidence_results_truncate_safely(session):
    """Verify returns fewer good recommendations instead of padding with bad candidates."""
    city = City(id=uuid4(), name="Surat", country="India", latitude=21.17, longitude=72.83)
    session.add(city)

    good1 = Place(id=uuid4(), city_id=city.id, name="Surat Castle", category="tourism", latitude=21.17, longitude=72.83)
    bad1 = Place(id=uuid4(), city_id=city.id, name="Port Trust Canteen", category="tourism", latitude=21.18, longitude=72.84)
    bad2 = Place(id=uuid4(), city_id=city.id, name="Customs Staff Mess", category="tourism", latitude=21.19, longitude=72.85)

    session.add_all([good1, bad1, bad2])
    session.commit()

    discovery = MockDiscovery({
        DiscoveryCategory.TOURISM: [good1, bad1, bad2],
    })
    service = RecommendationService(discovery=discovery)
    # User requested limit=10, but only 1 suitable place exists
    results = await service.recommend(
        session=session,
        city=city,
        request=RecommendationRequest(categories=[DiscoveryCategory.TOURISM], limit=10),
    )

    assert len(results) == 1
    assert results[0].name == "Surat Castle"


@pytest.mark.anyio
async def test_multi_category_deduplication(session):
    """Verify a place discovered under multiple categories only appears once in the response."""
    city = City(id=uuid4(), name="Udaipur", country="India", latitude=24.58, longitude=73.68)
    session.add(city)

    # Place that matches both heritage and tourism
    palace = Place(
        id=uuid4(),
        city_id=city.id,
        name="City Palace Udaipur",
        category="heritage",
        latitude=24.576,
        longitude=73.683,
        rating=4.7,
        review_count=5000,
    )
    session.add(palace)
    session.commit()

    discovery = MockDiscovery({
        DiscoveryCategory.HERITAGE: [palace],
        DiscoveryCategory.TOURISM: [palace],
    })
    service = RecommendationService(discovery=discovery)
    results = await service.recommend(
        session=session,
        city=city,
        request=RecommendationRequest(categories=[DiscoveryCategory.HERITAGE, DiscoveryCategory.TOURISM]),
    )

    assert len(results) == 1
    assert results[0].name == "City Palace Udaipur"

