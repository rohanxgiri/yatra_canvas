"""Tests for cache-first discovery, progressive prefetch, deduplication, and provider resilience."""

import asyncio
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest
from sqlmodel import Session, SQLModel, create_engine, select
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.models import City, CityCategoryCache, Place, PlaceSource, PlaceTag
from app.schemas import DiscoveryCategory
from app.services.city_place_prefetch_service import (
    CityPlacePrefetchService,
    PrefetchStage,
    SHALLOW_TARGET_CANDIDATES,
)
from app.services.canonical_place_service import CanonicalPlaceService
from app.services.geoapify_places_provider import GeoapifyPlacesProvider
from app.services.openstreetmap_discovery_service import OpenStreetMapDiscoveryService
from app.services.openstreetmap_places_service import (
    OpenStreetMapNearbyPlace,
    OpenStreetMapPlacesTimeoutError,
    OpenStreetMapPlacesUnavailableError,
)
from app.services.provider_circuit_breaker import ProviderCircuitBreaker
from app.services.recommendation_service import RecommendationRequest, RecommendationService


class MockPlacesProvider:
    def __init__(self) -> None:
        self.call_count = 0
        self.categories_requested: list[DiscoveryCategory] = []
        self.simulate_timeout = False
        self.simulate_error = False
        self.delay_seconds: float = 0.0

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
        self.call_count += 1
        self.categories_requested.extend(categories)

        if self.delay_seconds > 0:
            await asyncio.sleep(self.delay_seconds)

        if self.simulate_timeout:
            raise OpenStreetMapPlacesTimeoutError("Provider timeout")
        if self.simulate_error:
            raise OpenStreetMapPlacesUnavailableError("Provider error")

        results: dict[DiscoveryCategory, list[OpenStreetMapNearbyPlace]] = {}
        for cat in categories:
            results[cat] = [
                OpenStreetMapNearbyPlace(
                    external_place_id=f"osm/{cat.value}_{i}",
                    source_url=f"https://osm.org/{cat.value}_{i}",
                    name=f"Place {cat.value.title()} {i}",
                    latitude=latitude + (i * 0.001),
                    longitude=longitude + (i * 0.001),
                    tags={"amenity": cat.value},
                )
                for i in range(1, 12)
            ]
        return results


@pytest.fixture
def session() -> Session:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)
    with Session(engine) as s:
        yield s
    SQLModel.metadata.drop_all(engine)


@pytest.fixture
def test_city(session: Session) -> City:
    city = City(
        id=uuid4(),
        name="Kochi",
        state="Kerala",
        country="India",
        latitude=9.9312,
        longitude=76.2673,
    )
    session.add(city)
    session.commit()
    session.refresh(city)
    return city


@pytest.mark.anyio
async def test_cold_cache_triggers_provider_discovery(session: Session, test_city: City):
    settings = Settings(DATABASE_URL="postgresql://user:pass@localhost:5432/test_db")
    provider = MockPlacesProvider()
    discovery = OpenStreetMapDiscoveryService(settings, provider)

    results = await discovery.discover_many(
        session=session,
        city=test_city,
        categories=[DiscoveryCategory.TOURISM, DiscoveryCategory.FOOD],
    )

    assert provider.call_count == 1
    assert set(provider.categories_requested) == {DiscoveryCategory.TOURISM, DiscoveryCategory.FOOD}
    assert len(results[DiscoveryCategory.TOURISM]) == 11
    assert len(results[DiscoveryCategory.FOOD]) == 11


@pytest.mark.anyio
async def test_warm_cache_avoids_provider_calls(session: Session, test_city: City):
    settings = Settings(DATABASE_URL="postgresql://user:pass@localhost:5432/test_db")
    provider = MockPlacesProvider()
    discovery = OpenStreetMapDiscoveryService(settings, provider)

    # First call: cold cache
    await discovery.discover_many(
        session=session,
        city=test_city,
        categories=[DiscoveryCategory.TOURISM],
    )
    assert provider.call_count == 1

    # Second call: warm cache
    results = await discovery.discover_many(
        session=session,
        city=test_city,
        categories=[DiscoveryCategory.TOURISM],
    )
    assert provider.call_count == 1  # No additional provider call!
    assert len(results[DiscoveryCategory.TOURISM]) == 11


@pytest.mark.anyio
async def test_stale_cache_returns_immediately(session: Session, test_city: City):
    settings = Settings(DATABASE_URL="postgresql://user:pass@localhost:5432/test_db")
    provider = MockPlacesProvider()
    discovery = OpenStreetMapDiscoveryService(settings, provider)

    # Pre-populate with expired cache
    now = datetime.now(timezone.utc)
    expired_time = now - timedelta(hours=48)
    place = Place(
        city_id=test_city.id,
        name="Historical Kochi Fort",
        category="heritage",
        latitude=9.965,
        longitude=76.242,
        last_fetched_at=expired_time,
    )
    session.add(place)
    session.flush()
    session.add(PlaceTag(place_id=place.id, tag="heritage"))
    session.add(
        CityCategoryCache(
            city_id=test_city.id,
            category="heritage",
            last_fetched_at=expired_time,
            expires_at=expired_time,
        )
    )
    session.commit()

    # Stale-usable returns existing stored places immediately without waiting
    results = await discovery.discover_many(
        session=session,
        city=test_city,
        categories=[DiscoveryCategory.HERITAGE],
        prefer_stale=True,
    )

    assert provider.call_count == 0  # Provider not called synchronously!
    assert len(results[DiscoveryCategory.HERITAGE]) == 1
    assert results[DiscoveryCategory.HERITAGE][0].name == "Historical Kochi Fort"


@pytest.mark.anyio
async def test_partial_provider_failure_returns_usable_recommendations(session: Session, test_city: City):
    class PartialFailureProvider:
        async def search_nearby_places_for_categories(self, **kwargs):
            # food succeeds, heritage fails
            return {
                DiscoveryCategory.FOOD: [
                    OpenStreetMapNearbyPlace(
                        external_place_id="osm/food_1",
                        source_url="https://osm.org/food_1",
                        name="Kochi Seafood Haven",
                        latitude=9.932,
                        longitude=76.268,
                        tags={"amenity": "restaurant"},
                    )
                ]
            }

    settings = Settings(DATABASE_URL="postgresql://user:pass@localhost:5432/test_db")
    provider = PartialFailureProvider()
    discovery = OpenStreetMapDiscoveryService(settings, provider)  # type: ignore[arg-type]
    rec_service = RecommendationService(discovery)

    recs = await rec_service.recommend(
        session=session,
        city=test_city,
        request=RecommendationRequest(
            categories=[DiscoveryCategory.FOOD, DiscoveryCategory.HERITAGE],
            limit=10,
        ),
    )

    # Request MUST NOT fail with 500 or timeout: returns available food place!
    assert len(recs) == 1
    assert recs[0].name == "Kochi Seafood Haven"


@pytest.mark.anyio
async def test_overpass_timeout_uses_fallback(session: Session, test_city: City):
    settings = Settings(DATABASE_URL="postgresql://user:pass@localhost:5432/test_db")
    provider = MockPlacesProvider()
    provider.simulate_timeout = True

    # Pre-seed one place in DB
    place = Place(
        city_id=test_city.id,
        name="Cached Temple",
        category="religious",
        latitude=9.93,
        longitude=76.26,
    )
    session.add(place)
    session.flush()
    session.add(PlaceTag(place_id=place.id, tag="religious"))
    session.commit()

    discovery = OpenStreetMapDiscoveryService(settings, provider)  # type: ignore[arg-type]
    results = await discovery.discover_many(
        session=session,
        city=test_city,
        categories=[DiscoveryCategory.RELIGIOUS],
        prefer_stale=False,  # Force refresh attempt
    )

    # Overpass timed out, but DB fallback succeeded!
    assert len(results[DiscoveryCategory.RELIGIOUS]) == 1
    assert results[DiscoveryCategory.RELIGIOUS][0].name == "Cached Temple"


@pytest.mark.anyio
async def test_destination_prefetch_shallow_and_targeted_enrichment(session: Session, test_city: City):
    settings = Settings(DATABASE_URL="postgresql://user:pass@localhost:5432/test_db")
    provider = MockPlacesProvider()
    discovery = OpenStreetMapDiscoveryService(settings, provider)
    prefetch_service = CityPlacePrefetchService(discovery)

    # Stage 1: Destination confirmed -> broad shallow prefetch
    summary1 = await prefetch_service.prefetch(
        session=session,
        city=test_city,
        stage=PrefetchStage.DESTINATION_CONFIRMED,
    )
    assert summary1.stage == PrefetchStage.DESTINATION_CONFIRMED
    assert provider.call_count == 1
    assert len(summary1.categories_enriched) == 5

    # Stage 2: User selects Food and Cafes
    # Food is already sufficiently covered from stage 1 (if >= 11 candidates)
    # Stage 2 targeted deep prefetch skips already sufficient categories
    summary2 = await prefetch_service.prefetch(
        session=session,
        city=test_city,
        stage=PrefetchStage.INTERESTS_CONFIRMED,
        categories=[DiscoveryCategory.FOOD],
    )
    # Checks coverage and handles appropriately
    assert summary2.stage == PrefetchStage.INTERESTS_CONFIRMED


@pytest.mark.anyio
async def test_concurrent_same_city_prefetch_deduplication(session: Session, test_city: City):
    settings = Settings(DATABASE_URL="postgresql://user:pass@localhost:5432/test_db")
    provider = MockPlacesProvider()
    provider.delay_seconds = 0.05
    discovery = OpenStreetMapDiscoveryService(settings, provider)
    prefetch_service = CityPlacePrefetchService(discovery)

    # Simulate 3 concurrent prefetch requests for the same city
    task1 = prefetch_service.prefetch(
        session=session,
        city=test_city,
        stage=PrefetchStage.DESTINATION_CONFIRMED,
    )
    task2 = prefetch_service.prefetch(
        session=session,
        city=test_city,
        stage=PrefetchStage.DESTINATION_CONFIRMED,
    )
    task3 = prefetch_service.prefetch(
        session=session,
        city=test_city,
        stage=PrefetchStage.DESTINATION_CONFIRMED,
    )

    summaries = await asyncio.gather(task1, task2, task3)

    # At least one had duplicate refreshes prevented
    total_prevented = sum(s.duplicate_refreshes_prevented for s in summaries)
    assert total_prevented >= 1
