"""Unit and regression test suite for Multi-City Recommendation Quality Benchmark & Hardening.

Covers:
1. Institutional/private food venue exclusion (by operator, building, context)
2. Public normal restaurant remains allowed
3. Public cafe remains allowed
4. Missing access metadata is not automatically rejected (neutral/permissive fallback)
5. Known restricted POI is rejected (access="private", "students", "employees")
6. Canonical duplicates do not appear twice
7. Nearby distinct venues remain separate
8. Single-interest relevance stays strong
9. Purpose remains stronger than secondary interest
10. Mixed-interest results do not collapse into one category when alternatives exist
11. Prominence does not overpower intent
12. Missing Wikidata remains neutral
13. Top-10 request succeeds
14. Top-15 request succeeds
15. Top-20 request behaves safely
16. Same request is deterministic
17. Recommendation API contract remains valid
18. Route optimizer still accepts generated selections
"""

from datetime import date, datetime, time, timedelta, timezone
from uuid import UUID, uuid4

import pytest
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.models.entities import City, Place, PlaceSource, PlaceTag, UserSavedPlace
from app.schemas.recommendation import DiscoveryCategory, RecommendationRead, RecommendationRequest
from app.services.canonical_place_service import CanonicalPlaceService
from app.services.local_routes_service import LocalRoutesService
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
from app.services.preference_model import (
    DEFAULT_PREFERENCE_CONFIG,
    evaluate_preference_fit,
)
from app.services.recommendation_service import RecommendationService
from app.services.route_matrix_service import RouteNode
from app.services.vrptw_solver_service import VrptwSolverService


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
        name="Surat",
        country="India",
        latitude=21.1702,
        longitude=72.8311,
    )
    session.add(city)
    session.commit()
    return city


# -----------------------------------------------------------------------------
# 1. Institutional / Private Food Venue Exclusion
# -----------------------------------------------------------------------------
def test_institutional_private_food_exclusion():
    """Verify operator, building, and institutional dining patterns are rejected."""
    # Operator is educational institute (SVNIT) without explicit access tag
    suitable, conf = is_traveller_suitable(
        name="Campus Food Corner",
        category="food",
        tags={"amenity": "fast_food", "operator": "Sardar Vallabhbhai National Institute of Technology", "building": "university"},
    )
    assert suitable is False
    assert conf == AccessConfidence.RESTRICTED_LIKELY

    # Building is dormitory / hostel
    suitable, conf = is_traveller_suitable(
        name="Central Dining Hall",
        category="food",
        tags={"amenity": "canteen", "building": "dormitory"},
    )
    assert suitable is False
    assert conf == AccessConfidence.RESTRICTED_LIKELY

    # Hospital operator dining
    suitable, conf = is_traveller_suitable(
        name="Doctors Dining Point",
        category="food",
        tags={"amenity": "fast_food", "operator": "AIIMS", "building": "hospital"},
    )
    assert suitable is False
    assert conf == AccessConfidence.RESTRICTED_LIKELY


# -----------------------------------------------------------------------------
# 2 & 3. Public Normal Restaurant & Cafe Remain Allowed
# -----------------------------------------------------------------------------
def test_public_restaurant_and_cafe_remain_allowed():
    """Verify public restaurants and cafes remain PUBLIC_LIKELY and suitable."""
    suitable, conf = is_traveller_suitable(
        name="Sasumaa Gujarati Thali",
        category="food",
        tags={"amenity": "restaurant", "cuisine": "gujarati"},
    )
    assert suitable is True
    assert conf == AccessConfidence.PUBLIC_LIKELY

    suitable, conf = is_traveller_suitable(
        name="Nomad Coffee House",
        category="cafes",
        tags={"amenity": "cafe"},
    )
    assert suitable is True
    assert conf == AccessConfidence.PUBLIC_LIKELY


# -----------------------------------------------------------------------------
# 4. Missing Access Metadata is NOT Automatically Rejected
# -----------------------------------------------------------------------------
def test_missing_access_metadata_allowed():
    """Verify local speciality dining with sparse/missing tags is cautiously allowed."""
    suitable, conf = is_traveller_suitable(
        name="Jaani Locho Centre",
        category="food",
        tags=None,
    )
    assert suitable is True
    assert conf == AccessConfidence.PUBLIC_LIKELY


# -----------------------------------------------------------------------------
# 5. Known Restricted POI is Rejected
# -----------------------------------------------------------------------------
def test_known_restricted_poi_rejected():
    """Verify access=private / students / employees tags strictly yield RESTRICTED."""
    suitable, conf = is_traveller_suitable(
        name="Officers Dining Club",
        category="food",
        tags={"access": "employees"},
    )
    assert suitable is False
    assert conf == AccessConfidence.RESTRICTED

    suitable, conf = is_traveller_suitable(
        name="Hostel 4 Mess",
        category="food",
        tags={"access": "students"},
    )
    assert suitable is False
    assert conf == AccessConfidence.RESTRICTED


# -----------------------------------------------------------------------------
# 6. Canonical Duplicates Do Not Appear Twice
# -----------------------------------------------------------------------------
@pytest.mark.anyio
async def test_canonical_duplicates_do_not_appear_twice(session, test_city):
    """Verify that identical or close near-duplicate venues are deduplicated."""
    p1 = Place(
        id=uuid4(),
        city_id=test_city.id,
        name="Sasumaa Gujarati Thali",
        category="food",
        latitude=21.1710,
        longitude=72.8315,
        rating=4.5,
        review_count=1200,
    )
    p2 = Place(
        id=uuid4(),
        city_id=test_city.id,
        name="Sasumaa Gujarati Thali Restaurant",
        category="food",
        latitude=21.1711,
        longitude=72.8316,
        rating=4.3,
        review_count=600,
    )
    session.add_all([p1, p2])
    session.commit()

    discovery = MockDiscovery({DiscoveryCategory.FOOD: [p1, p2]})
    service = RecommendationService(discovery=discovery)

    results = await service.recommend(
        session=session,
        city=test_city,
        request=RecommendationRequest(categories=[DiscoveryCategory.FOOD], limit=10),
    )

    names = [r.name for r in results]
    assert len(names) == 1
    assert "Sasumaa" in names[0]


# -----------------------------------------------------------------------------
# 7. Nearby Distinct Venues Remain Separate
# -----------------------------------------------------------------------------
@pytest.mark.anyio
async def test_nearby_distinct_venues_remain_separate(session, test_city):
    """Verify that physically distinct nearby venues (e.g. distinct temples) are not falsely merged."""
    t1 = Place(
        id=uuid4(),
        city_id=test_city.id,
        name="Kashi Vishwanath Temple",
        category="religious",
        latitude=25.3108,
        longitude=83.0106,
        rating=4.8,
        review_count=15000,
    )
    t2 = Place(
        id=uuid4(),
        city_id=test_city.id,
        name="Annapurna Devi Temple",
        category="religious",
        latitude=25.3110,
        longitude=83.0109,
        rating=4.6,
        review_count=4000,
    )
    session.add_all([t1, t2])
    session.commit()

    discovery = MockDiscovery({DiscoveryCategory.RELIGIOUS: [t1, t2]})
    service = RecommendationService(discovery=discovery)

    results = await service.recommend(
        session=session,
        city=test_city,
        request=RecommendationRequest(categories=[DiscoveryCategory.RELIGIOUS], limit=10),
    )

    names = [r.name for r in results]
    assert "Kashi Vishwanath Temple" in names
    assert "Annapurna Devi Temple" in names
    assert len(results) == 2


# -----------------------------------------------------------------------------
# 8. Single-Interest Relevance Stays Strong
# -----------------------------------------------------------------------------
@pytest.mark.anyio
async def test_single_interest_relevance_stays_strong(session, test_city):
    """Verify single-intent query strictly surfaces intent-matched places."""
    p_fort = Place(
        id=uuid4(),
        city_id=test_city.id,
        name="Old Fort",
        category="heritage",
        latitude=21.1983,
        longitude=72.8167,
        is_heritage=True,
    )
    p_thali = Place(
        id=uuid4(),
        city_id=test_city.id,
        name="Kansar Thali",
        category="food",
        latitude=21.1730,
        longitude=72.8320,
    )
    session.add_all([p_fort, p_thali])
    session.commit()

    discovery = MockDiscovery({
        DiscoveryCategory.HERITAGE: [p_fort],
        DiscoveryCategory.FOOD: [p_thali],
    })
    service = RecommendationService(discovery=discovery)

    results = await service.recommend(
        session=session,
        city=test_city,
        request=RecommendationRequest(
            categories=[DiscoveryCategory.HERITAGE, DiscoveryCategory.FOOD],
            purposes=["heritage"],
            limit=5,
        ),
    )
    assert len(results) == 1
    assert results[0].name == "Old Fort"


# -----------------------------------------------------------------------------
# 9. Purpose Remains Stronger than Secondary Interest
# -----------------------------------------------------------------------------
def test_purpose_stronger_than_secondary_interest():
    """Verify purpose category match (25.0 pts) outweights secondary interest match (10.0 pts)."""
    p_heritage = Place(id=uuid4(), city_id=uuid4(), name="City Palace", category="heritage", latitude=0, longitude=0)
    p_food = Place(id=uuid4(), city_id=uuid4(), name="Local Thali", category="food", latitude=0, longitude=0)

    score_purp, _, _ = evaluate_preference_fit(
        p_heritage,
        {"heritage"},
        purposes=["heritage"],
        interests=["food"],
    )
    score_int, _, _ = evaluate_preference_fit(
        p_food,
        {"food"},
        purposes=["heritage"],
        interests=["food"],
    )
    assert score_purp > score_int
    assert score_purp >= 25.0
    assert score_int >= 10.0


# -----------------------------------------------------------------------------
# 10. Mixed-Interest Results Do Not Collapse into One Category
# -----------------------------------------------------------------------------
@pytest.mark.anyio
async def test_mixed_interest_results_preserve_both_categories(session, test_city):
    """Verify mixed-intent request (heritage + food) interleaves both categories without starvation."""
    heritage_places = [
        Place(id=uuid4(), city_id=test_city.id, name=f"Monument {i}", category="heritage", latitude=21.2 + i*0.001, longitude=72.8, is_heritage=True, rating=4.5, review_count=500)
        for i in range(8)
    ]
    food_places = [
        Place(id=uuid4(), city_id=test_city.id, name=f"Restaurant {i}", category="food", latitude=21.1 + i*0.001, longitude=72.8, rating=4.4, review_count=400)
        for i in range(5)
    ]
    session.add_all(heritage_places + food_places)
    session.commit()

    discovery = MockDiscovery({
        DiscoveryCategory.HERITAGE: heritage_places,
        DiscoveryCategory.FOOD: food_places,
    })
    service = RecommendationService(discovery=discovery)

    results = await service.recommend(
        session=session,
        city=test_city,
        request=RecommendationRequest(
            categories=[DiscoveryCategory.HERITAGE, DiscoveryCategory.FOOD],
            purposes=["heritage"],
            interests=["food"],
            limit=10,
        ),
    )

    cats = [r.category for r in results]
    assert "heritage" in cats
    assert "food" in cats
    # Secondary interest should receive at least 2 slots in top 10
    assert cats.count("food") >= 2


# -----------------------------------------------------------------------------
# 11. Prominence Does Not Overpower Intent
# -----------------------------------------------------------------------------
@pytest.mark.anyio
async def test_prominence_does_not_overpower_intent(session, test_city):
    """Verify a prominent landmark in an unrelated category does not beat intent-matched POIs."""
    p_famous_temple = Place(
        id=uuid4(),
        city_id=test_city.id,
        name="Famous Sacred Temple",
        category="religious",
        latitude=21.16,
        longitude=72.82,
        importance_score=0.99,
    )
    p_food = Place(
        id=uuid4(),
        city_id=test_city.id,
        name="Authentic Gujarati Thali",
        category="food",
        latitude=21.17,
        longitude=72.83,
        rating=4.5,
        review_count=800,
        is_local_speciality=True,
    )
    session.add_all([p_famous_temple, p_food])
    session.commit()

    discovery = MockDiscovery({
        DiscoveryCategory.RELIGIOUS: [p_famous_temple],
        DiscoveryCategory.FOOD: [p_food],
    })
    service = RecommendationService(discovery=discovery)

    results = await service.recommend(
        session=session,
        city=test_city,
        request=RecommendationRequest(
            categories=[DiscoveryCategory.FOOD],
            purposes=["food"],
            limit=5,
        ),
    )
    assert len(results) == 1
    assert results[0].name == "Authentic Gujarati Thali"


# -----------------------------------------------------------------------------
# 12. Missing Wikidata Remains Neutral
# -----------------------------------------------------------------------------
@pytest.mark.anyio
async def test_missing_wikidata_remains_neutral(session, test_city):
    """Verify places without Wikidata are not penalized and remain fully competitive."""
    p_no_wiki = Place(
        id=uuid4(),
        city_id=test_city.id,
        name="Authentic Locho Shop",
        category="food",
        latitude=21.172,
        longitude=72.833,
        rating=4.8,
        review_count=1200,
        is_local_speciality=True,
        wikidata_id=None,
        importance_score=None,
    )
    p_with_wiki = Place(
        id=uuid4(),
        city_id=test_city.id,
        name="Average Food Mall",
        category="food",
        latitude=21.175,
        longitude=72.835,
        rating=3.5,
        review_count=50,
        wikidata_id="Q12345",
        importance_score=0.3,
    )
    session.add_all([p_no_wiki, p_with_wiki])
    session.commit()

    discovery = MockDiscovery({DiscoveryCategory.FOOD: [p_no_wiki, p_with_wiki]})
    service = RecommendationService(discovery=discovery)

    results = await service.recommend(
        session=session,
        city=test_city,
        request=RecommendationRequest(categories=[DiscoveryCategory.FOOD], limit=5),
    )
    assert results[0].name == "Authentic Locho Shop"


# -----------------------------------------------------------------------------
# 13, 14, 15. Top-10, Top-15, Top-20 Requests Behave Safely
# -----------------------------------------------------------------------------
@pytest.mark.anyio
async def test_large_recommendation_requests_robustness(session, test_city):
    """Verify K=10, 15, 20 requests succeed without crashing and respect brand capping."""
    places = [
        Place(
            id=uuid4(),
            city_id=test_city.id,
            name=f"Authentic Venue {i}",
            category="food",
            latitude=21.17 + i*0.002,
            longitude=72.83 + i*0.001,
            rating=4.0 + (i % 5)*0.1,
            review_count=100 * i,
        )
        for i in range(25)
    ]
    # Add multiple branches of same brand (e.g. Domino's)
    dominos_branches = [
        Place(id=uuid4(), city_id=test_city.id, name="Domino's Pizza", category="food", latitude=21.18 + j*0.01, longitude=72.84, rating=3.8, review_count=200)
        for j in range(5)
    ]
    session.add_all(places + dominos_branches)
    session.commit()

    discovery = MockDiscovery({DiscoveryCategory.FOOD: places + dominos_branches})
    service = RecommendationService(discovery=discovery)

    for k in [10, 15, 20]:
        recs = await service.recommend(
            session=session,
            city=test_city,
            request=RecommendationRequest(categories=[DiscoveryCategory.FOOD], limit=k),
        )
        assert len(recs) == k
        # Verify brand capping: Domino's must appear at most once!
        dominos_count = sum(1 for r in recs if "domino" in r.name.lower())
        assert dominos_count <= 1


# -----------------------------------------------------------------------------
# 16. Determinism: Same Request Produces Identical Ordering
# -----------------------------------------------------------------------------
@pytest.mark.anyio
async def test_recommendation_determinism(session, test_city):
    """Verify identical inputs yield 100% deterministic recommendation ordering."""
    places = [
        Place(id=uuid4(), city_id=test_city.id, name=f"Venue {i}", category="food", latitude=21.17 + i*0.001, longitude=72.83, rating=4.2, review_count=300)
        for i in range(10)
    ]
    session.add_all(places)
    session.commit()

    discovery = MockDiscovery({DiscoveryCategory.FOOD: places})
    service = RecommendationService(discovery=discovery)

    req = RecommendationRequest(categories=[DiscoveryCategory.FOOD], limit=10)
    recs1 = await service.recommend(session=session, city=test_city, request=req)
    recs2 = await service.recommend(session=session, city=test_city, request=req)

    assert [r.id for r in recs1] == [r.id for r in recs2]
    assert [r.recommendation_score for r in recs1] == [r.recommendation_score for r in recs2]


# -----------------------------------------------------------------------------
# 17. Recommendation API Contract Remains Valid
# -----------------------------------------------------------------------------
@pytest.mark.anyio
async def test_recommendation_api_contract_valid(session, test_city):
    """Verify RecommendationRead instances satisfy all required schema fields."""
    p = Place(id=uuid4(), city_id=test_city.id, name="Test Venue", category="tourism", latitude=21.17, longitude=72.83, rating=4.5, review_count=500)
    session.add(p)
    session.commit()

    discovery = MockDiscovery({DiscoveryCategory.TOURISM: [p]})
    service = RecommendationService(discovery=discovery)

    results = await service.recommend(
        session=session,
        city=test_city,
        request=RecommendationRequest(categories=[DiscoveryCategory.TOURISM], limit=1),
    )
    assert len(results) == 1
    rec = results[0]
    assert isinstance(rec, RecommendationRead)
    assert isinstance(rec.id, UUID)
    assert isinstance(rec.name, str)
    assert isinstance(rec.recommendation_score, float)
    assert rec.access_confidence in ("PUBLIC_LIKELY", "UNKNOWN", "RESTRICTED", "RESTRICTED_LIKELY")


# -----------------------------------------------------------------------------
# 18. Route Optimizer Accepts Generated Selections
# -----------------------------------------------------------------------------
@pytest.mark.anyio
async def test_route_optimizer_accepts_recommended_places(session, test_city):
    """Verify recommended places feed cleanly into LocalRoutesService and VRPTW optimizer."""
    places = [
        Place(id=uuid4(), city_id=test_city.id, name=f"Stop {i}", category="heritage", latitude=21.17 + i*0.005, longitude=72.83 + i*0.005, rating=4.5, review_count=500)
        for i in range(4)
    ]
    session.add_all(places)
    session.commit()

    discovery = MockDiscovery({DiscoveryCategory.HERITAGE: places})
    service = RecommendationService(discovery=discovery)

    recs = await service.recommend(
        session=session,
        city=test_city,
        request=RecommendationRequest(categories=[DiscoveryCategory.HERITAGE], limit=4),
    )
    assert len(recs) == 4

    # Build RouteNodes from recommendations
    start_node = RouteNode(
        key="start",
        location_type="start",
        name="Hotel",
        latitude=test_city.latitude,
        longitude=test_city.longitude,
    )
    place_nodes = [
        RouteNode(
            key=str(r.id),
            location_type="place",
            name=r.name,
            latitude=r.latitude,
            longitude=r.longitude,
            place_id=r.id,
        )
        for r in recs
    ]
    all_nodes = [start_node] + place_nodes
    coords = [n.coordinate for n in all_nodes]
    routes_service = LocalRoutesService()
    idx_matrix = await routes_service.compute_matrix(coords, coords)
    matrix = {
        (all_nodes[i].key, all_nodes[j].key): leg
        for (i, j), leg in idx_matrix.items()
    }

    saved_rows = [
        UserSavedPlace(
            trip_id=uuid4(),
            place_id=r.id,
            is_locked=False,
        )
        for r in recs
    ]

    solver = VrptwSolverService()
    solution = solver.solve(
        start_node=start_node,
        place_nodes=place_nodes,
        places=places,
        saved_rows=saved_rows,
        matrix=matrix,
        trip_days=1,
        start_date=date(2026, 9, 10),
    )
    assert len(solution.optimized_places) >= 1
    assert solution.total_distance_meters >= 0
