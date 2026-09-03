"""Unit and integration tests for trip purpose and interest weighting."""

from uuid import uuid4

import pytest
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine

from app.models.entities import City, Place, PlaceTag, Trip, TripPreference, UserSavedPlace
from app.schemas.recommendation import DiscoveryCategory, RecommendationRequest
from app.services.place_suitability_service import AccessConfidence, is_traveller_suitable
from app.services.preference_model import (
    DEFAULT_PREFERENCE_CONFIG,
    PreferenceWeightingConfig,
    evaluate_preference_fit,
    generate_preference_explanation,
    normalize_preference_key,
)
from app.services.recommendation_service import RecommendationService


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


@pytest.fixture
def test_city(session):
    city = City(
        id=uuid4(),
        name="Ujjain",
        country="India",
        latitude=23.18,
        longitude=75.77,
    )
    session.add(city)
    session.commit()
    return city


def test_preference_key_normalization():
    assert normalize_preference_key("Food Exploration") == "food"
    assert normalize_preference_key("Religious / Spiritual") == "religious"
    assert normalize_preference_key("Culture & Heritage") == "heritage"
    assert normalize_preference_key("Sightseeing") == "sightseeing"
    assert normalize_preference_key("Nature") == "nature"
    assert normalize_preference_key("Shopping") == "shopping"
    assert normalize_preference_key("Photography") == "photography"
    assert normalize_preference_key("Cafes") == "cafes"


def test_purpose_fit_stronger_than_secondary_interest():
    """Verify that primary trip purpose produces a significantly higher relevance score than a secondary interest."""
    p_food = Place(id=uuid4(), city_id=uuid4(), name="Local Thali", category="food", latitude=23.18, longitude=75.77)
    p_heritage = Place(id=uuid4(), city_id=uuid4(), name="Ancient Fort", category="heritage", latitude=23.18, longitude=75.77)

    # Primary purpose: FOOD, Secondary interest: HERITAGE
    food_fit, p_m, i_m = evaluate_preference_fit(
        p_food,
        {"restaurant", "vegetarian"},
        purposes=["Food Exploration"],
        interests=["heritage"],
    )
    heritage_fit, p_m2, i_m2 = evaluate_preference_fit(
        p_heritage,
        {"historic", "fort"},
        purposes=["Food Exploration"],
        interests=["heritage"],
    )

    # Food venue must outscore the heritage venue because purpose has 2.5x multiplier
    assert food_fit > heritage_fit
    assert "food" in p_m
    assert "heritage" in i_m2


@pytest.mark.anyio
async def test_food_trip_strongly_dominates(session, test_city):
    """FOOD trip: food-related traveller-facing places strongly dominate the top ranks."""
    p1 = Place(id=uuid4(), city_id=test_city.id, name="Malwi Dhaba", category="food", latitude=23.18, longitude=75.77, is_local_speciality=True)
    p2 = Place(id=uuid4(), city_id=test_city.id, name="Chaat Bazaar", category="food", latitude=23.181, longitude=75.771)
    p3 = Place(id=uuid4(), city_id=test_city.id, name="City Museum", category="tourism", latitude=23.182, longitude=75.772)
    p4 = Place(id=uuid4(), city_id=test_city.id, name="River Viewpoint", category="tourism", latitude=23.183, longitude=75.773)

    session.add_all([p1, p2, p3, p4])
    session.commit()

    discovery = MockDiscovery({
        DiscoveryCategory.FOOD: [p1, p2],
        DiscoveryCategory.TOURISM: [p3, p4],
    })
    service = RecommendationService(discovery)

    results = await service.recommend(
        session=session,
        city=test_city,
        request=RecommendationRequest(
            categories=[DiscoveryCategory.FOOD, DiscoveryCategory.TOURISM],
            purposes=["Food Exploration"],
        ),
    )

    result_names = [r.name for r in results]
    assert result_names[0] == "Malwi Dhaba"
    assert result_names[1] == "Chaat Bazaar"
    assert "food" in results[0].recommendation_reason.casefold()


@pytest.mark.anyio
async def test_religious_trip_strongly_dominates(session, test_city):
    """RELIGIOUS trip: temples and pilgrimage sites dominate."""
    p_temple = Place(id=uuid4(), city_id=test_city.id, name="Mahakaleshwar Temple", category="religious", latitude=23.18, longitude=75.77)
    p_ashram = Place(id=uuid4(), city_id=test_city.id, name="Sandipani Ashram", category="religious", latitude=23.181, longitude=75.771)
    p_cafe = Place(id=uuid4(), city_id=test_city.id, name="Brew & Bake", category="cafes", latitude=23.182, longitude=75.772)

    session.add_all([p_temple, p_ashram, p_cafe])
    session.add(PlaceTag(place_id=p_temple.id, tag="temple"))
    session.add(PlaceTag(place_id=p_ashram.id, tag="ashram"))
    session.commit()

    discovery = MockDiscovery({
        DiscoveryCategory.RELIGIOUS: [p_temple, p_ashram],
        DiscoveryCategory.CAFES: [p_cafe],
    })
    service = RecommendationService(discovery)

    results = await service.recommend(
        session=session,
        city=test_city,
        request=RecommendationRequest(
            categories=[DiscoveryCategory.RELIGIOUS, DiscoveryCategory.CAFES],
            purposes=["Religious / Spiritual"],
        ),
    )

    result_names = [r.name for r in results]
    assert "Mahakaleshwar Temple" in result_names[:2]
    assert "Sandipani Ashram" in result_names[:2]
    assert "spiritual" in results[0].recommendation_reason.casefold() or "worship" in results[0].recommendation_reason.casefold()


@pytest.mark.anyio
async def test_history_trip_dominates(session, test_city):
    """HISTORY trip: heritage, monuments, historical sites dominate."""
    p_fort = Place(id=uuid4(), city_id=test_city.id, name="Ancient Palace", category="heritage", latitude=23.18, longitude=75.77, is_heritage=True)
    p_fast_food = Place(id=uuid4(), city_id=test_city.id, name="Burger Corner", category="food", latitude=23.181, longitude=75.771)

    session.add_all([p_fort, p_fast_food])
    session.add(PlaceTag(place_id=p_fort.id, tag="monument"))
    session.commit()

    discovery = MockDiscovery({
        DiscoveryCategory.HERITAGE: [p_fort],
        DiscoveryCategory.FOOD: [p_fast_food],
    })
    service = RecommendationService(discovery)

    results = await service.recommend(
        session=session,
        city=test_city,
        request=RecommendationRequest(
            categories=[DiscoveryCategory.HERITAGE, DiscoveryCategory.FOOD],
            purposes=["Culture & Heritage"],
        ),
    )

    assert len(results) >= 1
    assert results[0].name == "Ancient Palace"
    assert "heritage" in results[0].recommendation_reason.casefold() or "historic" in results[0].recommendation_reason.casefold()


@pytest.mark.anyio
async def test_nature_trip_dominates(session, test_city):
    """NATURE trip: parks, gardens, and scenic viewpoints dominate."""
    p_park = Place(id=uuid4(), city_id=test_city.id, name="Kshipra River Park", category="tourism", latitude=23.18, longitude=75.77)
    p_restaurant = Place(id=uuid4(), city_id=test_city.id, name="City Diner", category="food", latitude=23.181, longitude=75.771)

    session.add_all([p_park, p_restaurant])
    session.add(PlaceTag(place_id=p_park.id, tag="park"))
    session.commit()

    discovery = MockDiscovery({
        DiscoveryCategory.TOURISM: [p_park],
        DiscoveryCategory.FOOD: [p_restaurant],
    })
    service = RecommendationService(discovery)

    results = await service.recommend(
        session=session,
        city=test_city,
        request=RecommendationRequest(
            categories=[DiscoveryCategory.TOURISM, DiscoveryCategory.FOOD],
            purposes=["Nature"],
        ),
    )

    assert results[0].name == "Kshipra River Park"
    assert "nature" in results[0].recommendation_reason.casefold() or "outdoor" in results[0].recommendation_reason.casefold()


@pytest.mark.anyio
async def test_shopping_trip_dominates(session, test_city):
    """SHOPPING trip: bazaars and markets dominate."""
    p_market = Place(id=uuid4(), city_id=test_city.id, name="Sarafa Bazaar", category="tourism", latitude=23.18, longitude=75.77)
    p_temple = Place(id=uuid4(), city_id=test_city.id, name="Small Shrine", category="religious", latitude=23.181, longitude=75.771)

    session.add_all([p_market, p_temple])
    session.add(PlaceTag(place_id=p_market.id, tag="bazaar"))
    session.commit()

    discovery = MockDiscovery({
        DiscoveryCategory.TOURISM: [p_market],
        DiscoveryCategory.RELIGIOUS: [p_temple],
    })
    service = RecommendationService(discovery)

    results = await service.recommend(
        session=session,
        city=test_city,
        request=RecommendationRequest(
            categories=[DiscoveryCategory.TOURISM, DiscoveryCategory.RELIGIOUS],
            purposes=["Shopping"],
        ),
    )

    assert results[0].name == "Sarafa Bazaar"


@pytest.mark.anyio
async def test_mixed_interests_balanced_relevance(session, test_city):
    """Mixed interests (Food + History + Cafes) produce a balanced but relevance-ranked result set."""
    p_food1 = Place(id=uuid4(), city_id=test_city.id, name="Thali Bhavan", category="food", latitude=23.18, longitude=75.77, rating=4.7, review_count=1000)
    p_food2 = Place(id=uuid4(), city_id=test_city.id, name="Samosa Corner", category="food", latitude=23.181, longitude=75.771, rating=4.5, review_count=800)
    p_food3 = Place(id=uuid4(), city_id=test_city.id, name="Sweet Centre", category="food", latitude=23.182, longitude=75.772, rating=4.4, review_count=600)
    p_hist1 = Place(id=uuid4(), city_id=test_city.id, name="Kaliadeh Palace", category="heritage", latitude=23.183, longitude=75.773, rating=4.6, review_count=900, is_heritage=True)
    p_cafe1 = Place(id=uuid4(), city_id=test_city.id, name="Artisan Cafe", category="cafes", latitude=23.184, longitude=75.774, rating=4.5, review_count=400)

    session.add_all([p_food1, p_food2, p_food3, p_hist1, p_cafe1])
    session.commit()

    discovery = MockDiscovery({
        DiscoveryCategory.FOOD: [p_food1, p_food2, p_food3],
        DiscoveryCategory.HERITAGE: [p_hist1],
        DiscoveryCategory.CAFES: [p_cafe1],
    })
    service = RecommendationService(discovery)

    results = await service.recommend(
        session=session,
        city=test_city,
        request=RecommendationRequest(
            categories=[DiscoveryCategory.FOOD, DiscoveryCategory.HERITAGE, DiscoveryCategory.CAFES],
            purposes=["Food Exploration"],
            interests=["heritage", "cafes"],
        ),
    )

    categories_in_results = {r.category for r in results}
    # Check that food, heritage, and cafe are all represented
    assert "food" in categories_in_results
    assert "heritage" in categories_in_results
    assert "cafes" in categories_in_results

    # Food dominates top rank
    assert results[0].category == "food"


@pytest.mark.anyio
async def test_category_filter_interaction(session, test_city):
    """Explicit category filter narrows the candidate set while ranking using trip preferences."""
    p_cafe1 = Place(id=uuid4(), city_id=test_city.id, name="Bakery & Breakfast Cafe", category="cafes", latitude=23.18, longitude=75.77, is_local_speciality=True)
    p_cafe2 = Place(id=uuid4(), city_id=test_city.id, name="Internet Cafe", category="cafes", latitude=23.181, longitude=75.771)
    p_food = Place(id=uuid4(), city_id=test_city.id, name="Famous Thali", category="food", latitude=23.182, longitude=75.772)

    session.add_all([p_cafe1, p_cafe2, p_food])
    session.add(PlaceTag(place_id=p_cafe1.id, tag="bakery"))
    session.commit()

    discovery = MockDiscovery({
        DiscoveryCategory.FOOD: [p_food],
        DiscoveryCategory.CAFES: [p_cafe1, p_cafe2],
    })
    service = RecommendationService(discovery)

    # Filter by CAFES on a FOOD trip
    results = await service.recommend(
        session=session,
        city=test_city,
        request=RecommendationRequest(
            categories=[DiscoveryCategory.FOOD, DiscoveryCategory.CAFES],
            purposes=["Food Exploration"],
            category_filter=DiscoveryCategory.CAFES,
        ),
    )

    # Only cafe places return
    assert all(r.category == "cafes" for r in results)
    assert results[0].name == "Bakery & Breakfast Cafe"

    # Clearing the filter returns both cafes and food places
    unfiltered_results = await service.recommend(
        session=session,
        city=test_city,
        request=RecommendationRequest(
            categories=[DiscoveryCategory.FOOD, DiscoveryCategory.CAFES],
            purposes=["Food Exploration"],
            category_filter=None,
        ),
    )
    result_categories = {r.category for r in unfiltered_results}
    assert "food" in result_categories
    assert "cafes" in result_categories


@pytest.mark.anyio
async def test_low_relevance_candidates_omitted(session, test_city):
    """Unrelated filler candidates with near-zero preference fit are omitted rather than diluting responses."""
    p_food = Place(id=uuid4(), city_id=test_city.id, name="Local Bhojanalaya", category="food", latitude=23.18, longitude=75.77)
    p_unrelated1 = Place(id=uuid4(), city_id=test_city.id, name="Government Office Park", category="tourism", latitude=23.181, longitude=75.771)
    p_unrelated2 = Place(id=uuid4(), city_id=test_city.id, name="General Memorial", category="heritage", latitude=23.182, longitude=75.772)

    session.add_all([p_food, p_unrelated1, p_unrelated2])
    session.commit()

    discovery = MockDiscovery({
        DiscoveryCategory.FOOD: [p_food],
        DiscoveryCategory.TOURISM: [p_unrelated1],
        DiscoveryCategory.HERITAGE: [p_unrelated2],
    })
    service = RecommendationService(discovery)

    # Pure FOOD trip
    results = await service.recommend(
        session=session,
        city=test_city,
        request=RecommendationRequest(
            categories=[DiscoveryCategory.FOOD, DiscoveryCategory.TOURISM, DiscoveryCategory.HERITAGE],
            purposes=["Food Exploration"],
            limit=10,
        ),
    )

    # Only the relevant food place returns; the unrelated tourism/heritage filler is omitted
    assert len(results) == 1
    assert results[0].name == "Local Bhojanalaya"


@pytest.mark.anyio
async def test_traveller_suitability_exclusion_despite_high_food_weight(session, test_city):
    """Institutional canteen / student mess is strictly excluded even when FOOD has high weight."""
    p_canteen = Place(id=uuid4(), city_id=test_city.id, name="Engineering College Canteen", category="food", latitude=23.18, longitude=75.77)
    p_mess = Place(id=uuid4(), city_id=test_city.id, name="Boys Hostel Mess", category="food", latitude=23.181, longitude=75.771)
    p_restaurant = Place(id=uuid4(), city_id=test_city.id, name="Shree Ganga Restaurant", category="food", latitude=23.182, longitude=75.772)

    session.add_all([p_canteen, p_mess, p_restaurant])
    session.commit()

    discovery = MockDiscovery({
        DiscoveryCategory.FOOD: [p_canteen, p_mess, p_restaurant],
    })
    service = RecommendationService(discovery)

    results = await service.recommend(
        session=session,
        city=test_city,
        request=RecommendationRequest(
            categories=[DiscoveryCategory.FOOD],
            purposes=["Food Exploration"],
        ),
    )

    result_names = [r.name for r in results]
    assert "Engineering College Canteen" not in result_names
    assert "Boys Hostel Mess" not in result_names
    assert result_names == ["Shree Ganga Restaurant"]


@pytest.mark.anyio
async def test_saved_place_handling(session, test_city):
    """Saved places are returned with is_saved=True without duplicates."""
    p1 = Place(id=uuid4(), city_id=test_city.id, name="Saved Dhaba", category="food", latitude=23.18, longitude=75.77)
    p2 = Place(id=uuid4(), city_id=test_city.id, name="Unsaved Cafe", category="cafes", latitude=23.181, longitude=75.771)

    session.add_all([p1, p2])
    trip_id = uuid4()
    session.add(UserSavedPlace(trip_id=trip_id, place_id=p1.id, custom_order=1))
    session.commit()

    discovery = MockDiscovery({
        DiscoveryCategory.FOOD: [p1],
        DiscoveryCategory.CAFES: [p2],
    })
    service = RecommendationService(discovery)

    results = await service.recommend(
        session=session,
        city=test_city,
        request=RecommendationRequest(
            categories=[DiscoveryCategory.FOOD, DiscoveryCategory.CAFES],
            trip_id=trip_id,
            purposes=["Food Exploration"],
        ),
    )

    saved_map = {r.name: r.is_saved for r in results}
    assert saved_map["Saved Dhaba"] is True
    assert saved_map["Unsaved Cafe"] is False


@pytest.mark.anyio
async def test_trip_preference_loaded_from_db_when_trip_id_provided(session, test_city):
    """If request.purposes is None, preferences are loaded from TripPreference rows."""
    p_food = Place(id=uuid4(), city_id=test_city.id, name="Rajasthani Thali", category="food", latitude=23.18, longitude=75.77)
    p_heritage = Place(id=uuid4(), city_id=test_city.id, name="City Gateway", category="heritage", latitude=23.181, longitude=75.771)

    session.add_all([p_food, p_heritage])

    trip_id = uuid4()
    trip = Trip(
        id=trip_id,
        user_id=uuid4(),
        city_id=test_city.id,
        trip_name="Ujjain Food Trip",
        days=2,
    )
    session.add(trip)
    # Stored preference with weight 2.0 indicates purpose
    session.add(TripPreference(trip_id=trip_id, preference="Food Exploration", weight=2.0))
    session.commit()

    discovery = MockDiscovery({
        DiscoveryCategory.FOOD: [p_food],
        DiscoveryCategory.HERITAGE: [p_heritage],
    })
    service = RecommendationService(discovery)

    # No explicit purposes passed; should load from TripPreference
    results = await service.recommend(
        session=session,
        city=test_city,
        request=RecommendationRequest(
            categories=[DiscoveryCategory.FOOD, DiscoveryCategory.HERITAGE],
            trip_id=trip_id,
        ),
    )

    assert results[0].name == "Rajasthani Thali"
    assert "food" in results[0].recommendation_reason.casefold()


@pytest.mark.anyio
async def test_surat_food_regression(session):
    """Surat + FOOD regression: public traveller food places rank high, institutional canteens excluded, no duplicates."""
    city = City(id=uuid4(), name="Surat", country="India", latitude=21.1702, longitude=72.8311)
    session.add(city)

    # 1. Public thali restaurant
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
    # 2. Duplicate thali (25m away)
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
    )
    # 4. Staff mess (institutional)
    p_staff_mess = Place(
        id=uuid4(),
        city_id=city.id,
        name="L&T Employee Cafeteria",
        category="food",
        latitude=21.1500,
        longitude=72.8000,
    )
    # 5. Public cafe
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
    # 6. Street food stall
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

    session.add_all([p_thali, p_thali_dup, p_canteen, p_staff_mess, p_cafe, p_locho])
    session.commit()

    discovery = MockDiscovery({
        DiscoveryCategory.FOOD: [p_thali, p_thali_dup, p_canteen, p_staff_mess, p_locho],
        DiscoveryCategory.CAFES: [p_cafe],
    })
    service = RecommendationService(discovery)

    results = await service.recommend(
        session=session,
        city=city,
        request=RecommendationRequest(
            categories=[DiscoveryCategory.FOOD, DiscoveryCategory.CAFES],
            purposes=["Food Exploration"],
        ),
    )

    result_names = [r.name for r in results]

    # Verification:
    # 1. Institutional canteens excluded
    assert "SVNIT Student Canteen" not in result_names
    assert "L&T Employee Cafeteria" not in result_names

    # 2. Duplicate thali merged into 1
    thali_count = sum(1 for name in result_names if "Sasumaa" in name)
    assert thali_count == 1

    # 3. Public food places rank high with explainable reason
    assert len(results) == 3
    top_names = [results[0].name, results[1].name]
    assert "Sasumaa Gujarati Thali" in top_names
    assert "Jaani Locho Centre" in top_names
    assert "food" in results[0].recommendation_reason.casefold() or "speciality" in results[0].recommendation_reason.casefold()
