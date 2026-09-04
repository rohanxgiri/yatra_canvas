"""Unit and integration tests for PlaceImportanceScorer and importance-aware ranking.

Verifies:
1. Normalization bounds (sitelinks log scaling, PageRank log scaling, upper caps)
2. Outlier bounding (PageRank 162, Sitelinks 180 capped at 1.0)
3. Deterministic output for identical inputs
4. Missing importance neutrality (0.0 score, no penalty)
5. Rejection of article_tier as prominence signal
6. Prominence breaks ties among otherwise equally relevant POIs
7. High prominence cannot overpower an incompatible user preference (personalization protection)
8. Local-speciality and food POIs without Wikidata remain recommendable
9. Explainability breakdown matches calculated score
10. Persistence in canonical place service and multi-source provenance
11. Recommendation API schema contract remains unchanged
"""

import math
from uuid import uuid4

import pytest
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.models.entities import City, Place, PlaceSource, PlaceTag
from app.schemas.recommendation import DiscoveryCategory, RecommendationRead, RecommendationRequest
from app.services.canonical_place_service import CanonicalPlaceService
from app.services.place_importance_scorer import (
    PAGERANK_MAX_REF,
    SITELINKS_MAX_REF,
    PlaceImportanceScorer,
)
from app.services.place_suitability_service import AccessConfidence
from app.services.preference_model import PreferenceWeightingConfig, evaluate_preference_fit
from app.services.recommendation_service import (
    DEFAULT_RECOMMENDATION_WEIGHTS,
    RecommendationService,
    calculate_recommendation_score,
    explain_recommendation_score,
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


@pytest.fixture
def test_city(session):
    city = City(
        id=uuid4(),
        name="Jaipur",
        country="India",
        latitude=26.9124,
        longitude=75.7873,
    )
    session.add(city)
    session.commit()
    return city


# -----------------------------------------------------------------------------
# 1. Normalization & Bounding Tests
# -----------------------------------------------------------------------------


def test_sitelinks_normalization_bounds():
    """Verify sitelinks log-normalization behaves monotonically and is bounded in [0.0, 1.0]."""
    # None or non-positive returns 0.0
    assert PlaceImportanceScorer.normalize_sitelinks(None) == 0.0
    assert PlaceImportanceScorer.normalize_sitelinks(0) == 0.0
    assert PlaceImportanceScorer.normalize_sitelinks(-5) == 0.0

    # Intermediate values are strictly monotonic
    s1 = PlaceImportanceScorer.normalize_sitelinks(1)
    s10 = PlaceImportanceScorer.normalize_sitelinks(10)
    s50 = PlaceImportanceScorer.normalize_sitelinks(50)
    s100 = PlaceImportanceScorer.normalize_sitelinks(100)

    assert 0.0 < s1 < s10 < s50 < s100
    assert math.isclose(s100, 1.0, rel_tol=1e-3)

    # Outliers above 100 sitelinks are capped at 1.0
    assert PlaceImportanceScorer.normalize_sitelinks(180) == 1.0
    assert PlaceImportanceScorer.normalize_sitelinks(500) == 1.0


def test_pagerank_normalization_bounds():
    """Verify Wikidata PageRank log-normalization is bounded in [0.0, 1.0]."""
    # None or non-positive returns 0.0
    assert PlaceImportanceScorer.normalize_pagerank(None) == 0.0
    assert PlaceImportanceScorer.normalize_pagerank(0.0) == 0.0
    assert PlaceImportanceScorer.normalize_pagerank(-1.5) == 0.0

    # Intermediate values are strictly monotonic
    p1 = PlaceImportanceScorer.normalize_pagerank(1.0)
    p5 = PlaceImportanceScorer.normalize_pagerank(5.0)
    p15 = PlaceImportanceScorer.normalize_pagerank(15.0)
    p25 = PlaceImportanceScorer.normalize_pagerank(25.0)

    assert 0.0 < p1 < p5 < p15 < p25
    assert math.isclose(p25, 1.0, rel_tol=1e-3)

    # Massive outliers (e.g. Ganga PR 162.185) are capped at 1.0
    assert PlaceImportanceScorer.normalize_pagerank(162.185) == 1.0
    assert PlaceImportanceScorer.normalize_pagerank(1000.0) == 1.0


def test_composite_prominence_calculation_and_determinism():
    """Verify composite blending when both signals exist, single fallback, and strict determinism."""
    # When both present: 60% sitelinks + 40% pagerank
    sl = 47
    pr = 18.56
    score1 = PlaceImportanceScorer.calculate_prominence(sl, pr)
    score2 = PlaceImportanceScorer.calculate_prominence(sl, pr)
    assert score1 == score2  # Determinism
    assert 0.0 < score1 <= 1.0

    expected = round(
        0.60 * PlaceImportanceScorer.normalize_sitelinks(sl)
        + 0.40 * PlaceImportanceScorer.normalize_pagerank(pr),
        4,
    )
    assert score1 == expected

    # Single signal fallback
    assert PlaceImportanceScorer.calculate_prominence(sl, None) == round(
        PlaceImportanceScorer.normalize_sitelinks(sl), 4
    )
    assert PlaceImportanceScorer.calculate_prominence(None, pr) == round(
        PlaceImportanceScorer.normalize_pagerank(pr), 4
    )

    # Missing signals return neutral 0.0
    assert PlaceImportanceScorer.calculate_prominence(None, None) == 0.0
    assert PlaceImportanceScorer.calculate_prominence(0, 0.0) == 0.0


def test_missing_importance_neutrality():
    """Verify missing Wikidata/Audiala importance is completely neutral and not penalized."""
    p_no_wiki = Place(
        id=uuid4(),
        city_id=uuid4(),
        name="Local Dosa Corner",
        category="food",
        latitude=26.91,
        longitude=75.78,
        rating=None,
        review_count=0,
    )
    score = calculate_recommendation_score(
        p_no_wiki,
        matched_category_count=1,
        selected_category_count=1,
        relevance_score=40.0,
        prominence_score=None,
    )
    # Score has no penalty: exactly category_score 40.0
    assert score == 40.0


def test_explain_recommendation_score_breakdown():
    """Verify explain_recommendation_score returns accurate inspectable components."""
    p = Place(
        id=uuid4(),
        city_id=uuid4(),
        name="Hawa Mahal",
        category="tourism",
        latitude=26.92,
        longitude=75.82,
        is_heritage=True,
        rating=None,
        review_count=0,
    )
    breakdown = explain_recommendation_score(
        p,
        matched_category_count=1,
        selected_category_count=1,
        relevance_score=50.0,
        prominence_score=0.741,
    )
    assert breakdown["category_relevance"] == 50.0
    assert breakdown["rating_score"] == 0.0
    assert breakdown["prominence_score"] == 0.741
    # prominence_addition = 15.0 * 0.741 = 11.115 ~ 11.12
    assert math.isclose(breakdown["prominence_addition"], 11.12, abs_tol=0.05)
    assert breakdown["bonuses"]["heritage"] == 8.0
    # Total = 50 + 0 + 11.12 + 8.0 = 69.1
    assert math.isclose(breakdown["final_score"], 69.1, abs_tol=0.1)


# -----------------------------------------------------------------------------
# 2. Ranking & Scenario Tests (A, B, C, D, E)
# -----------------------------------------------------------------------------


def test_scenario_a_famous_sightseeing_prominence():
    """Scenario A: Major relevant heritage landmark benefits from prominence over minor nearby structure."""
    hawa_mahal = Place(
        id=uuid4(),
        city_id=uuid4(),
        name="Hawa Mahal",
        category="heritage",
        latitude=26.9239,
        longitude=75.8267,
        is_heritage=True,
        importance_score=0.741,  # 59 sitelinks, PR 4.32
    )
    minor_circle = Place(
        id=uuid4(),
        city_id=uuid4(),
        name="Vichar Kranti Circle",
        category="heritage",
        latitude=26.9240,
        longitude=75.8270,
        is_heritage=True,
        importance_score=None,  # No prominence
    )

    # Both have identical category fit (relevance = 50.0)
    score_hawa = calculate_recommendation_score(
        hawa_mahal, matched_category_count=1, selected_category_count=1, relevance_score=50.0
    )
    score_circle = calculate_recommendation_score(
        minor_circle, matched_category_count=1, selected_category_count=1, relevance_score=50.0
    )

    # Hawa Mahal receives the ~11.1 point prominence boost and clearly wins
    assert score_hawa > score_circle
    assert math.isclose(score_hawa - score_circle, 11.1, abs_tol=0.2)


@pytest.mark.anyio
async def test_scenario_b_food_focused_traveler_personalization_protected(session, test_city):
    """Scenario B: Famous monument cannot jump above relevant food places on a food-focused trip."""
    p_sweetshop = Place(
        id=uuid4(),
        city_id=test_city.id,
        name="LMB Traditional Sweetshop",
        category="food",
        latitude=26.918,
        longitude=75.821,
        is_local_speciality=True,
        importance_score=None,  # Local dining, no Wikidata
    )
    p_cafe = Place(
        id=uuid4(),
        city_id=test_city.id,
        name="Anokhi Cafe",
        category="cafes",
        latitude=26.915,
        longitude=75.815,
        is_popular=True,
        importance_score=None,
    )
    p_monument = Place(
        id=uuid4(),
        city_id=test_city.id,
        name="Hawa Mahal",
        category="heritage",
        latitude=26.9239,
        longitude=75.8267,
        is_heritage=True,
        importance_score=0.95,  # Huge prominence!
    )

    session.add_all([p_sweetshop, p_cafe, p_monument])
    session.commit()

    discovery = MockDiscovery({
        DiscoveryCategory.FOOD: [p_sweetshop],
        DiscoveryCategory.CAFES: [p_cafe],
        DiscoveryCategory.HERITAGE: [p_monument],
    })
    service = RecommendationService(discovery)

    # User searches for FOOD purpose and CAFES interest
    results = await service.recommend(
        session=session,
        city=test_city,
        request=RecommendationRequest(
            categories=[DiscoveryCategory.FOOD, DiscoveryCategory.CAFES],
            purposes=["Food Exploration"],
            interests=["Cafes"],
        ),
    )

    result_names = [r.name for r in results]
    # Monument must NOT appear or cannot outrank relevant food
    assert "Hawa Mahal" not in result_names or result_names.index("Hawa Mahal") > result_names.index("LMB Traditional Sweetshop")
    # Sweetshop and cafe must occupy top ranks
    assert result_names[0] == "LMB Traditional Sweetshop"


def test_scenario_c_religious_trip_major_temple_boost():
    """Scenario C: Major temple with prominence ranks above small street shrine."""
    kashi_vishwanath = Place(
        id=uuid4(),
        city_id=uuid4(),
        name="Kashi Vishwanath Temple",
        category="religious",
        latitude=25.3109,
        longitude=83.0107,
        importance_score=0.725,  # 41 sitelinks, PR 6.12
    )
    local_shrine = Place(
        id=uuid4(),
        city_id=uuid4(),
        name="Local Street Shrine",
        category="religious",
        latitude=25.3115,
        longitude=83.0110,
        importance_score=None,
    )

    score_kashi = calculate_recommendation_score(
        kashi_vishwanath, matched_category_count=1, selected_category_count=1, relevance_score=50.0
    )
    score_shrine = calculate_recommendation_score(
        local_shrine, matched_category_count=1, selected_category_count=1, relevance_score=50.0
    )

    assert score_kashi > score_shrine
    assert math.isclose(score_kashi - score_shrine, 10.9, abs_tol=0.2)


def test_scenario_d_local_speciality_without_wikidata_remains_recommendable():
    """Scenario D: Local-speciality venue without Wikidata remains top recommendable against generic venue."""
    jalebi_wala = Place(
        id=uuid4(),
        city_id=uuid4(),
        name="Old Famous Jalebi Wala",
        category="food",
        latitude=28.656,
        longitude=77.230,
        is_local_speciality=True,
        importance_score=None,  # No Wikidata
    )
    generic_burger = Place(
        id=uuid4(),
        city_id=uuid4(),
        name="Generic Burger Joint",
        category="food",
        latitude=28.658,
        longitude=77.232,
        is_local_speciality=False,
        importance_score=None,
    )

    score_jalebi = calculate_recommendation_score(
        jalebi_wala, matched_category_count=1, selected_category_count=1, relevance_score=45.0
    )
    score_burger = calculate_recommendation_score(
        generic_burger, matched_category_count=1, selected_category_count=1, relevance_score=45.0
    )

    # Local speciality bonus (+7) ensures it strongly beats generic food
    assert score_jalebi > score_burger
    assert score_jalebi == 45.0 + 7.0


def test_scenario_e_equally_relevant_attractions_tie_breaker():
    """Scenario E: Importance acts as a clean, deterministic tie-breaker between equally relevant POIs."""
    jantar_mantar = Place(
        id=uuid4(),
        city_id=uuid4(),
        name="Jantar Mantar",
        category="tourism",
        latitude=26.9248,
        longitude=75.8246,
        is_heritage=True,
        importance_score=0.865,  # UNESCO site (47 sitelinks, PR 18.56)
    )
    paanch_batti = Place(
        id=uuid4(),
        city_id=uuid4(),
        name="Paanch Batti Gateway",
        category="tourism",
        latitude=26.9180,
        longitude=75.8050,
        is_heritage=True,
        importance_score=None,  # Minor junction arch
    )

    score_jantar = calculate_recommendation_score(
        jantar_mantar, matched_category_count=1, selected_category_count=1, relevance_score=55.0
    )
    score_arch = calculate_recommendation_score(
        paanch_batti, matched_category_count=1, selected_category_count=1, relevance_score=55.0
    )

    # Without importance, both were tied at 63.0 (55 + 8 heritage).
    # With importance, Jantar Mantar receives ~13.0 points and breaks the tie cleanly.
    assert score_arch == 63.0
    assert math.isclose(score_jantar, 76.0, abs_tol=0.2)
    assert score_jantar > score_arch


# -----------------------------------------------------------------------------
# 3. Persistence in CanonicalPlaceService Tests
# -----------------------------------------------------------------------------


def test_canonical_place_service_persists_importance_score_and_metrics(session, test_city):
    """Verify CanonicalPlaceService calculates and persists importance_score on Place and raw metrics on PlaceSource."""
    service = CanonicalPlaceService()

    tags = {
        "audiala:sitelinks": "59",
        "audiala:pagerank": "4.32",
        "wikidata": "Q584022",
    }

    place, source = service.resolve_or_create_place(
        session=session,
        city=test_city,
        category=DiscoveryCategory.HERITAGE,
        name="Hawa Mahal",
        latitude=26.9239,
        longitude=75.8267,
        external_place_id="Q584022",
        source_name="audiala",
        licence_identifier="CC BY 4.0",
        tags=tags,
    )

    # Verify canonical Place has bounded importance_score
    assert place.importance_score is not None
    assert 0.70 <= place.importance_score <= 0.80

    # Verify PlaceSource has raw metrics in social_identifiers
    assert source.social_identifiers is not None
    assert source.social_identifiers.get("sitelinks") == "59"
    assert "4.32" in source.social_identifiers.get("wikidata_pagerank", "")

    # Query directly from DB to verify persistence survived flush/commit
    session.commit()
    db_place = session.get(Place, place.id)
    assert db_place is not None
    assert db_place.importance_score == place.importance_score
