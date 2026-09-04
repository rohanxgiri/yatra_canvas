"""Reliability and latency benchmark suite for live POI discovery.

Compares previous baseline architecture vs new cache-first + progressive prefetch pipeline.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import time
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import uuid4

from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine

from app.core.config import get_settings
from app.models.entities import City, CityCategoryCache, Place, PlaceTag
from app.schemas import DiscoveryCategory, RecommendationRequest
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
    OpenStreetMapPlacesTimeoutError,
)
from app.services.recommendation_service import RecommendationService

logger = logging.getLogger(__name__)


@dataclass
class ScenarioResult:
    scenario: str
    architecture: str  # "baseline" or "new_pipeline"
    time_to_first_usable_ms: float
    total_time_ms: float
    provider_calls: int
    cache_hit: bool
    failed_providers: int
    returned_recommendations: int
    status: str


class MockOverpassService:
    def __init__(self, delay_s: float = 0.0, timeout: bool = False, fail_categories: set[DiscoveryCategory] | None = None) -> None:
        self.delay_s = delay_s
        self.timeout = timeout
        self.fail_categories = fail_categories or set()
        self.calls = 0

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
        self.calls += len(categories)
        if self.delay_s > 0:
            await asyncio.sleep(self.delay_s)
        if self.timeout:
            raise OpenStreetMapPlacesTimeoutError("Overpass connection timed out")

        results: dict[DiscoveryCategory, list[OpenStreetMapNearbyPlace]] = {}
        for cat in categories:
            if cat in self.fail_categories:
                continue
            results[cat] = [
                OpenStreetMapNearbyPlace(
                    external_place_id=f"osm-{cat.value}-{i}",
                    source_url=f"https://osm.org/{cat.value}/{i}",
                    name=f"{cat.value.title()} Venue {i}",
                    latitude=latitude + (i * 0.001),
                    longitude=longitude + (i * 0.001),
                    tags={"name": f"{cat.value.title()} Venue {i}", "tourism": "attraction"},
                )
                for i in range(1, 15)
            ]
        return results


class MockGeoapifyProvider:
    def __init__(self, delay_s: float = 0.0, enabled: bool = True) -> None:
        self.delay_s = delay_s
        self.is_configured = enabled
        self.calls = 0

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
        if not self.is_configured:
            return {}
        self.calls += len(categories)
        if self.delay_s > 0:
            await asyncio.sleep(self.delay_s)

        results: dict[DiscoveryCategory, list[OpenStreetMapNearbyPlace]] = {}
        for cat in categories:
            results[cat] = [
                OpenStreetMapNearbyPlace(
                    external_place_id=f"geoapify-{cat.value}-{i}",
                    source_url=f"https://geoapify.com/{cat.value}/{i}",
                    name=f"Geoapify {cat.value.title()} {i}",
                    latitude=latitude + (i * 0.0012),
                    longitude=longitude + (i * 0.0012),
                    tags={"name": f"Geoapify {cat.value.title()} {i}", "source": "geoapify"},
                )
                for i in range(1, 12)
            ]
        return results


def setup_db() -> tuple[Session, City]:
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    SQLModel.metadata.create_all(engine)
    session = Session(engine)
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
    return session, city


async def run_scenario(
    name: str,
    *,
    is_warm: bool = False,
    is_stale: bool = False,
    overpass_delay: float = 0.05,
    overpass_timeout: bool = False,
    overpass_fails: set[DiscoveryCategory] | None = None,
    geoapify_enabled: bool = True,
    geoapify_delay: float = 0.02,
    categories: list[DiscoveryCategory] | None = None,
    use_prefetch: bool = True,
) -> ScenarioResult:
    target_cats = categories or [DiscoveryCategory.TOURISM, DiscoveryCategory.HERITAGE, DiscoveryCategory.FOOD]
    session, city = setup_db()
    settings = get_settings()

    now = datetime.now(timezone.utc)
    if is_warm:
        for cat in target_cats:
            session.add(CityCategoryCache(city_id=city.id, category=cat.value, last_fetched_at=now, expires_at=now + timedelta(hours=24)))
            for i in range(12):
                p = Place(city_id=city.id, name=f"Cached {cat.value} {i}", category=cat.value, latitude=9.93 + i*0.001, longitude=76.26 + i*0.001, review_count=10, is_popular=True, is_heritage=False, is_local_speciality=False)
                session.add(p)
                session.commit()
                session.add(PlaceTag(place_id=p.id, tag=cat.value))
                session.commit()
    elif is_stale:
        for cat in target_cats:
            session.add(CityCategoryCache(city_id=city.id, category=cat.value, last_fetched_at=now - timedelta(days=3), expires_at=now - timedelta(days=2)))
            for i in range(12):
                p = Place(city_id=city.id, name=f"Stale {cat.value} {i}", category=cat.value, latitude=9.93 + i*0.001, longitude=76.26 + i*0.001, review_count=10, is_popular=True, is_heritage=False, is_local_speciality=False)
                session.add(p)
                session.commit()
                session.add(PlaceTag(place_id=p.id, tag=cat.value))
                session.commit()

    overpass_mock = MockOverpassService(delay_s=overpass_delay, timeout=overpass_timeout, fail_categories=overpass_fails)
    geoapify_mock = MockGeoapifyProvider(delay_s=geoapify_delay, enabled=geoapify_enabled)

    discovery = OpenStreetMapDiscoveryService(
        settings=settings,
        provider=overpass_mock,  # type: ignore[arg-type]
        geoapify_provider=geoapify_mock,  # type: ignore[arg-type]
    )
    rec_service = RecommendationService(discovery)
    prefetch_service = CityPlacePrefetchService(discovery)

    t0 = time.monotonic()

    # If new pipeline with prefetch enabled and cold cache, simulate destination confirmation
    if use_prefetch and not is_warm and not is_stale:
        # Pre-warm starter categories
        await prefetch_service.prefetch(session=session, city=city, stage=PrefetchStage.DESTINATION_CONFIRMED)

    t_first_usable = 0.0
    status = "SUCCESS"
    recs = []

    try:
        recs = await rec_service.recommend(
            session=session,
            city=city,
            request=RecommendationRequest(categories=target_cats, limit=20),
        )
        t_first_usable = (time.monotonic() - t0) * 1000.0
    except Exception as exc:
        status = f"FAILED ({type(exc).__name__})"
        t_first_usable = (time.monotonic() - t0) * 1000.0

    total_time = (time.monotonic() - t0) * 1000.0
    provider_calls = overpass_mock.calls + geoapify_mock.calls
    failed_providers = 1 if overpass_timeout else (1 if overpass_fails else 0)

    return ScenarioResult(
        scenario=name,
        architecture="new_pipeline" if use_prefetch else "baseline",
        time_to_first_usable_ms=round(t_first_usable, 1),
        total_time_ms=round(total_time, 1),
        provider_calls=provider_calls,
        cache_hit=is_warm or is_stale,
        failed_providers=failed_providers,
        returned_recommendations=len(recs),
        status=status,
    )


async def main():
    results: list[ScenarioResult] = []

    scenarios = [
        ("warm_kochi_cache", dict(is_warm=True)),
        ("stale_kochi_cache", dict(is_stale=True)),
        ("cold_kochi_cache_with_prefetch", dict(is_warm=False, use_prefetch=True)),
        ("cold_kochi_baseline_no_prefetch", dict(is_warm=False, use_prefetch=False, geoapify_enabled=False)),
        ("overpass_slow_resilience", dict(is_warm=False, overpass_delay=0.25, use_prefetch=True)),
        ("overpass_unavailable_fallback", dict(is_warm=False, overpass_timeout=True, use_prefetch=True)),
        ("geoapify_slow_resilience", dict(is_warm=False, geoapify_delay=0.15, use_prefetch=True)),
        ("partial_category_failure", dict(is_warm=False, overpass_fails={DiscoveryCategory.FOOD}, use_prefetch=True)),
        ("five_interest_trip", dict(is_warm=True, categories=[DiscoveryCategory.TOURISM, DiscoveryCategory.HERITAGE, DiscoveryCategory.FOOD, DiscoveryCategory.RELIGIOUS, DiscoveryCategory.CAFES])),
    ]

    for name, kwargs in scenarios:
        res = await run_scenario(name, **kwargs)
        results.append(res)

    results_dir = Path("scripts/experiments/live_discovery_reliability/results")
    results_dir.mkdir(parents=True, exist_ok=True)
    out_file = results_dir / "benchmark_results.json"
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump([asdict(r) for r in results], f, indent=2)

    print("\n================ LIVE DISCOVERY RELIABILITY EXPERIMENT RESULTS ================")
    print(f"{'Scenario':<34} | {'Arch':<12} | {'Time to Usable':<14} | {'Calls':<6} | {'Recs':<5} | {'Status'}")
    print("-" * 90)
    for r in results:
        print(f"{r.scenario:<34} | {r.architecture:<12} | {r.time_to_first_usable_ms:>10.1f} ms | {r.provider_calls:>5} | {r.returned_recommendations:>4} | {r.status}")
    print("===============================================================================\n")


if __name__ == "__main__":
    asyncio.run(main())
