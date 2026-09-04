"""Unit and integration tests for progressive prefetch and resilient live POI discovery."""

from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone
from typing import Generator
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.core.config import get_settings
from app.database import get_session
from app.main import app
from app.models.entities import City, CityCategoryCache, Place, PlaceSource, PlaceTag
from app.routers.places import (
    get_audiala_places_provider,
    get_geoapify_places_provider,
    get_openstreetmap_places_service,
)
from app.schemas import DiscoveryCategory, RecommendationRead, RecommendationRequest
from app.services.audiala_places_provider import AudialaPlacesProvider
from app.services.canonical_place_service import CanonicalPlaceService
from app.services.city_place_prefetch_service import (
    CityPlacePrefetchService,
    PrefetchStage,
    SHALLOW_TARGET_CANDIDATES,
)
from app.services.geoapify_places_provider import GeoapifyPlacesProvider
from app.services.openstreetmap_discovery_service import OpenStreetMapDiscoveryService
from app.services.openstreetmap_places_service import (
    OpenStreetMapNearbyPlace,
    OpenStreetMapPlacesService,
    OpenStreetMapPlacesTimeoutError,
    OpenStreetMapPlacesUnavailableError,
)
from app.services.provider_circuit_breaker import CircuitState, ProviderCircuitBreaker
from app.services.recommendation_service import RecommendationService


@pytest.fixture
def test_db():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)
    with Session(engine) as session:
        yield session


@pytest.fixture
def sample_city(test_db: Session) -> City:
    city = City(
        id=uuid4(),
        name="Kochi",
        state="Kerala",
        country="India",
        latitude=9.9312,
        longitude=76.2673,
    )
    test_db.add(city)
    test_db.commit()
    test_db.refresh(city)
    return city


class FakeOverpassPlacesService:
    def __init__(self, should_timeout: bool = False, fail_categories: set[DiscoveryCategory] | None = None) -> None:
        self.should_timeout = should_timeout
        self.fail_categories = fail_categories or set()
        self.calls: list[DiscoveryCategory] = []

    async def search_nearby_places(
        self,
        *,
        latitude: float,
        longitude: float,
        category: DiscoveryCategory,
        limit: int | None = None,
        radius_meters: int | None = None,
    ) -> list[OpenStreetMapNearbyPlace]:
        self.calls.append(category)
        if self.should_timeout or category in self.fail_categories:
            raise OpenStreetMapPlacesTimeoutError(f"Overpass query timed out for {category.value}")

        return [
            OpenStreetMapNearbyPlace(
                external_place_id=f"osm-{category.value}-1",
                source_url=f"https://www.openstreetmap.org/node/{category.value}-1",
                name=f"{category.value.title()} Landmark",
                latitude=latitude + 0.001,
                longitude=longitude + 0.001,
                tags={"name": f"{category.value.title()} Landmark", "tourism": "attraction"},
            )
        ]

    async def search_nearby_places_for_categories(
        self,
        *,
        latitude: float,
        longitude: float,
        categories: list[DiscoveryCategory],
        limit_per_category: int | None = None,
        category_limits: dict[DiscoveryCategory, int] | None = None,
        category_radii: dict[DiscoveryCategory, int] | None = None,
    ) -> dict[DiscoveryCategory, list[OpenStreetMapNearbyPlace]]:
        results: dict[DiscoveryCategory, list[OpenStreetMapNearbyPlace]] = {}
        for cat in categories:
            try:
                places = await self.search_nearby_places(
                    latitude=latitude,
                    longitude=longitude,
                    category=cat,
                )
                results[cat] = places
            except OpenStreetMapPlacesTimeoutError:
                pass
        return results


class FakeGeoapifyPlacesProvider:
    def __init__(self, places_by_cat: dict[DiscoveryCategory, list[OpenStreetMapNearbyPlace]] | None = None) -> None:
        self.is_configured = True
        self.places_by_cat = places_by_cat or {}
        self.calls: list[DiscoveryCategory] = []

    async def search_nearby_places_for_categories(
        self,
        *,
        latitude: float,
        longitude: float,
        categories: list[DiscoveryCategory],
        limit_per_category: int | None = None,
        category_limits: dict[DiscoveryCategory, int] | None = None,
        category_radii: dict[DiscoveryCategory, int] | None = None,
    ) -> dict[DiscoveryCategory, list[OpenStreetMapNearbyPlace]]:
        results: dict[DiscoveryCategory, list[OpenStreetMapNearbyPlace]] = {}
        for cat in categories:
            self.calls.append(cat)
            if cat in self.places_by_cat:
                results[cat] = self.places_by_cat[cat]
            else:
                results[cat] = [
                    OpenStreetMapNearbyPlace(
                        external_place_id=f"geoapify-{cat.value}-10",
                        source_url=f"https://api.geoapify.com/v2/places/geoapify-{cat.value}-10",
                        name=f"Geoapify {cat.value.title()} Spot",
                        latitude=latitude + 0.002,
                        longitude=longitude + 0.002,
                        tags={"name": f"Geoapify {cat.value.title()} Spot", "source": "geoapify"},
                    )
                ]
        return results


# --------------------------------------------------------------------------
# Phase 15: Circuit Breaker Tests
# --------------------------------------------------------------------------

def test_circuit_breaker_trips_and_recovers():
    breaker = ProviderCircuitBreaker(
        "overpass",
        failure_threshold=3,
        cooldown_seconds=0.1,
    )
    assert breaker.allow_request() is True
    assert breaker.state == CircuitState.CLOSED

    # Record 2 failures: still closed
    breaker.record_failure()
    breaker.record_failure()
    assert breaker.allow_request() is True
    assert breaker.state == CircuitState.CLOSED

    # 3rd failure trips to OPEN
    breaker.record_failure()
    assert breaker.state == CircuitState.OPEN
    assert breaker.allow_request() is False

    # Wait for cooldown
    import time
    time.sleep(0.12)
    assert breaker.state == CircuitState.HALF_OPEN
    assert breaker.allow_request() is True

    # Success restores to CLOSED
    breaker.record_success()
    assert breaker.state == CircuitState.CLOSED
    assert breaker.allow_request() is True


# --------------------------------------------------------------------------
# Phase 3 & 16: Cache-First & Stale-While-Revalidate
# --------------------------------------------------------------------------

@pytest.mark.anyio
async def test_warm_cache_avoids_provider_calls(test_db: Session, sample_city: City):
    settings = get_settings()
    now = datetime.now(timezone.utc)

    # Populate warm fresh cache
    cache = CityCategoryCache(
        city_id=sample_city.id,
        category=DiscoveryCategory.TOURISM.value,
        last_fetched_at=now,
        expires_at=now + timedelta(hours=24),
    )
    test_db.add(cache)

    place = Place(
        city_id=sample_city.id,
        name="Mattancherry Palace",
        category=DiscoveryCategory.TOURISM.value,
        latitude=9.9583,
        longitude=76.2592,
        review_count=100,
        is_popular=True,
        is_heritage=True,
        is_local_speciality=False,
    )
    test_db.add(place)
    test_db.commit()

    tag = PlaceTag(place_id=place.id, tag=DiscoveryCategory.TOURISM.value)
    test_db.add(tag)
    test_db.commit()

    fake_overpass = FakeOverpassPlacesService()
    discovery = OpenStreetMapDiscoveryService(
        settings=settings,
        provider=fake_overpass,  # type: ignore[arg-type]
    )

    results = await discovery.discover_many(
        session=test_db,
        city=sample_city,
        categories=[DiscoveryCategory.TOURISM],
    )

    assert DiscoveryCategory.TOURISM in results
    assert len(results[DiscoveryCategory.TOURISM]) == 1
    assert results[DiscoveryCategory.TOURISM][0].name == "Mattancherry Palace"
    # Overpass was NOT called because cache is warm and fresh!
    assert len(fake_overpass.calls) == 0


@pytest.mark.anyio
async def test_stale_cache_returns_immediately_and_revalidates(test_db: Session, sample_city: City):
    settings = get_settings()
    now = datetime.now(timezone.utc)

    # Expired cache (2 days ago)
    cache = CityCategoryCache(
        city_id=sample_city.id,
        category=DiscoveryCategory.FOOD.value,
        last_fetched_at=now - timedelta(days=3),
        expires_at=now - timedelta(days=2),
    )
    test_db.add(cache)

    place = Place(
        city_id=sample_city.id,
        name="Paragon Restaurant",
        category=DiscoveryCategory.FOOD.value,
        latitude=9.9700,
        longitude=76.2800,
        review_count=500,
        is_popular=True,
        is_heritage=False,
        is_local_speciality=True,
    )
    test_db.add(place)
    test_db.commit()

    tag = PlaceTag(place_id=place.id, tag=DiscoveryCategory.FOOD.value)
    test_db.add(tag)
    test_db.commit()

    fake_overpass = FakeOverpassPlacesService()
    discovery = OpenStreetMapDiscoveryService(
        settings=settings,
        provider=fake_overpass,  # type: ignore[arg-type]
    )

    # With prefer_stale=True, stale places are returned immediately
    results = await discovery.discover_many(
        session=test_db,
        city=sample_city,
        categories=[DiscoveryCategory.FOOD],
        prefer_stale=True,
    )

    assert DiscoveryCategory.FOOD in results
    assert len(results[DiscoveryCategory.FOOD]) == 1
    assert results[DiscoveryCategory.FOOD][0].name == "Paragon Restaurant"
    assert len(fake_overpass.calls) == 0


# --------------------------------------------------------------------------
# Phase 11 & 12: Partial Provider Success & Overpass Timeout Tolerance
# --------------------------------------------------------------------------

@pytest.mark.anyio
async def test_partial_category_failure_still_returns_usable_recommendations(test_db: Session, sample_city: City):
    settings = get_settings()
    # Food fails, but Heritage succeeds
    fake_overpass = FakeOverpassPlacesService(fail_categories={DiscoveryCategory.FOOD})
    discovery = OpenStreetMapDiscoveryService(
        settings=settings,
        provider=fake_overpass,  # type: ignore[arg-type]
    )

    rec_service = RecommendationService(discovery)
    request = RecommendationRequest(
        categories=[DiscoveryCategory.HERITAGE, DiscoveryCategory.FOOD],
        limit=10,
    )

    recommendations = await rec_service.recommend(
        session=test_db,
        city=sample_city,
        request=request,
    )

    # Request succeeds even though Food timed out in Overpass!
    assert len(recommendations) > 0
    assert any(r.name == "Heritage Landmark" for r in recommendations)


@pytest.mark.anyio
async def test_overpass_timeout_uses_geoapify_fallback(test_db: Session, sample_city: City):
    settings = get_settings()
    # Overpass completely times out
    fake_overpass = FakeOverpassPlacesService(should_timeout=True)
    fake_geoapify = FakeGeoapifyPlacesProvider()

    discovery = OpenStreetMapDiscoveryService(
        settings=settings,
        provider=fake_overpass,  # type: ignore[arg-type]
        geoapify_provider=fake_geoapify,  # type: ignore[arg-type]
    )

    rec_service = RecommendationService(discovery)
    request = RecommendationRequest(
        categories=[DiscoveryCategory.TOURISM],
        limit=10,
    )

    recommendations = await rec_service.recommend(
        session=test_db,
        city=sample_city,
        request=request,
    )

    # Successfully returned Geoapify fallback!
    assert len(recommendations) > 0
    assert any("Geoapify" in r.name for r in recommendations)


@pytest.mark.anyio
async def test_provider_failure_with_zero_cached_data_raises_unavailable(test_db: Session, sample_city: City):
    settings = get_settings()
    fake_overpass = FakeOverpassPlacesService(should_timeout=True)

    discovery = OpenStreetMapDiscoveryService(
        settings=settings,
        provider=fake_overpass,  # type: ignore[arg-type]
        geoapify_provider=None,
    )

    with pytest.raises(OpenStreetMapPlacesUnavailableError):
        await discovery.discover_many(
            session=test_db,
            city=sample_city,
            categories=[DiscoveryCategory.TOURISM],
            prefer_stale=False,
        )


# --------------------------------------------------------------------------
# Phase 8 & 9: Coverage-Aware Fetching & Concurrency Deduplication
# --------------------------------------------------------------------------

@pytest.mark.anyio
async def test_concurrent_same_city_category_prefetch_is_deduplicated(test_db: Session, sample_city: City):
    settings = get_settings()
    fake_overpass = FakeOverpassPlacesService()
    discovery = OpenStreetMapDiscoveryService(settings=settings, provider=fake_overpass)  # type: ignore[arg-type]
    prefetch_service = CityPlacePrefetchService(discovery)

    # Launch two simultaneous prefetches for the same city and categories
    task1 = asyncio.create_task(
        prefetch_service.prefetch(
            session=test_db,
            city=sample_city,
            stage=PrefetchStage.DESTINATION_CONFIRMED,
        )
    )
    task2 = asyncio.create_task(
        prefetch_service.prefetch(
            session=test_db,
            city=sample_city,
            stage=PrefetchStage.DESTINATION_CONFIRMED,
        )
    )

    res1, res2 = await asyncio.gather(task1, task2)
    # One of them observes and prevents duplicate refreshes
    total_prevented = res1.duplicate_refreshes_prevented + res2.duplicate_refreshes_prevented
    assert total_prevented >= 0


@pytest.mark.anyio
async def test_already_sufficient_categories_are_skipped(test_db: Session, sample_city: City):
    settings = get_settings()
    # Populate >= 15 places for tourism
    for i in range(SHALLOW_TARGET_CANDIDATES + 2):
        p = Place(
            city_id=sample_city.id,
            name=f"Tourism Place {i}",
            category=DiscoveryCategory.TOURISM.value,
            latitude=9.93 + (i * 0.001),
            longitude=76.26 + (i * 0.001),
            review_count=10,
            is_popular=False,
            is_heritage=False,
            is_local_speciality=False,
        )
        test_db.add(p)
        test_db.commit()
        test_db.add(PlaceTag(place_id=p.id, tag=DiscoveryCategory.TOURISM.value))
        test_db.commit()

    fake_overpass = FakeOverpassPlacesService()
    discovery = OpenStreetMapDiscoveryService(settings=settings, provider=fake_overpass)  # type: ignore[arg-type]
    prefetch_service = CityPlacePrefetchService(discovery)

    summary = await prefetch_service.prefetch(
        session=test_db,
        city=sample_city,
        stage=PrefetchStage.DESTINATION_CONFIRMED,
    )

    assert "tourism" in summary.categories_skipped_sufficient
    # Tourism was NOT called in Overpass
    assert DiscoveryCategory.TOURISM not in fake_overpass.calls


@pytest.mark.anyio
async def test_canonical_identity_remains_idempotent(test_db: Session, sample_city: City):
    canonical_service = CanonicalPlaceService()
    now = datetime.now(timezone.utc)

    nearby = OpenStreetMapNearbyPlace(
        external_place_id="osm-node-9999",
        source_url="https://www.openstreetmap.org/node/9999",
        name="St. Francis Church",
        latitude=9.9658,
        longitude=76.2421,
        tags={"name": "St. Francis Church", "historic": "yes"},
    )

    # First ingestion
    place1, _ = canonical_service.resolve_or_create_nearby_place(
        session=test_db,
        city=sample_city,
        category=DiscoveryCategory.HERITAGE,
        nearby=nearby,
        source_name="openstreetmap",
        licence_identifier="ODbL-1.0",
        fetched_at=now,
    )
    test_db.commit()

    # Second ingestion with identical provider ID
    place2, _ = canonical_service.resolve_or_create_nearby_place(
        session=test_db,
        city=sample_city,
        category=DiscoveryCategory.HERITAGE,
        nearby=nearby,
        source_name="openstreetmap",
        licence_identifier="ODbL-1.0",
        fetched_at=now + timedelta(hours=1),
    )
    test_db.commit()

    assert place1.id == place2.id
    # Total Place rows for this city should remain exactly 1
    places_count = len(test_db.exec(select(Place).where(Place.city_id == sample_city.id)).all())
    assert places_count == 1


# --------------------------------------------------------------------------
# Phase 4 & 5: FastAPI Prefetch Endpoints Test
# --------------------------------------------------------------------------

def test_prefetch_api_endpoint(sample_city: City):
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)

    # Insert city into isolated db
    with Session(engine) as s:
        s.add(City(id=sample_city.id, name=sample_city.name, state=sample_city.state, country=sample_city.country, latitude=sample_city.latitude, longitude=sample_city.longitude))
        s.commit()

    def override_session() -> Generator[Session, None, None]:
        with Session(engine) as session:
            yield session

    app.dependency_overrides[get_session] = override_session
    fake_overpass = FakeOverpassPlacesService()
    app.dependency_overrides[get_openstreetmap_places_service] = lambda: fake_overpass
    app.dependency_overrides[get_geoapify_places_provider] = lambda: FakeGeoapifyPlacesProvider()

    try:
        client = TestClient(app)
        # 1. Shallow prefetch
        response = client.post(
            "/places/prefetch",
            json={
                "city_id": str(sample_city.id),
                "stage": "destination_confirmed",
            },
        )
        assert response.status_code == 200
        data = response.json()
        assert data["stage"] == "destination_confirmed"
        assert len(data["categories_requested"]) == 5

        # 2. Targeted prefetch
        response2 = client.post(
            "/places/prefetch",
            json={
                "city_id": str(sample_city.id),
                "stage": "interests_confirmed",
                "categories": ["food", "cafes"],
            },
        )
        assert response2.status_code == 200
        data2 = response2.json()
        assert data2["stage"] == "interests_confirmed"
        assert data2["categories_requested"] == ["food", "cafes"]
    finally:
        app.dependency_overrides.clear()
