"""Regression coverage for provider-free Discover recommendation reads."""

from __future__ import annotations

from collections.abc import Generator
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine

from app.core.config import get_settings
from app.database import get_session
from app.main import app
from app.models import City, CityCategoryCache, Place, PlaceSource, PlaceTag
from app.routers.places import (
    get_durable_place_refresh_service,
    get_recommendation_service,
)
from app.schemas import DiscoveryCategory
from app.services.openstreetmap_discovery_service import OpenStreetMapDiscoveryService
from app.services.openstreetmap_places_service import (
    OpenStreetMapPlacesUnavailableError,
)
from app.services.recommendation_service import RecommendationService

DISCOVERY_CATEGORIES = list(DiscoveryCategory)


class _UnavailableOverpass:
    def __init__(self) -> None:
        self.search_nearby_places_for_categories = AsyncMock(
            side_effect=OpenStreetMapPlacesUnavailableError("overpass unavailable")
        )
        self.search_nearby_places = AsyncMock(
            side_effect=OpenStreetMapPlacesUnavailableError("overpass unavailable")
        )


class _UnavailableAudiala:
    def __init__(self) -> None:
        self.search_nearby_places_for_categories = AsyncMock(
            side_effect=RuntimeError("audiala unavailable")
        )


class _UnavailableGeoapify:
    is_configured = True

    def __init__(self) -> None:
        self.search_nearby_places_for_categories = AsyncMock(
            side_effect=RuntimeError("geoapify unavailable")
        )


class _RecordingRefreshService:
    """Observe refresh requests without executing provider work in the request."""

    def __init__(self) -> None:
        self.enqueued: list[tuple[UUID, tuple[str, ...]]] = []

    def request_refresh(self, *, city_id, categories, **_kwargs):
        self.enqueued.append(
            (city_id, tuple(category.value for category in categories))
        )
        return SimpleNamespace(
            state="queued",
            queued_categories=[category.value for category in categories],
            reused_categories=[],
        )


@pytest.fixture
def cache_first_api(monkeypatch):
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)

    city_id = uuid4()
    city = City(
        id=city_id,
        name="Shillong",
        state="Meghalaya",
        country="India",
        latitude=25.5788,
        longitude=91.8933,
    )
    with Session(engine) as session:
        session.add(city)
        session.commit()

    overpass = _UnavailableOverpass()
    audiala = _UnavailableAudiala()
    geoapify = _UnavailableGeoapify()
    discovery = OpenStreetMapDiscoveryService(
        settings=get_settings(),
        provider=overpass,  # type: ignore[arg-type]
        audiala_provider=audiala,  # type: ignore[arg-type]
        geoapify_provider=geoapify,  # type: ignore[arg-type]
    )
    recommendation = RecommendationService(discovery)
    refresh_service = _RecordingRefreshService()

    def override_session() -> Generator[Session, None, None]:
        with Session(engine) as session:
            yield session

    app.dependency_overrides[get_session] = override_session
    app.dependency_overrides[get_recommendation_service] = lambda: recommendation
    app.dependency_overrides[get_durable_place_refresh_service] = lambda: (
        refresh_service
    )

    yield {
        "client": TestClient(app),
        "engine": engine,
        "city_id": city_id,
        "overpass": overpass,
        "audiala": audiala,
        "geoapify": geoapify,
        "refresh_service": refresh_service,
    }

    app.dependency_overrides.clear()
    SQLModel.metadata.drop_all(engine)
    engine.dispose()


def _seed_places(
    engine, city_id: UUID, *, count: int, cache_age_hours: int = 229
) -> None:
    now = datetime.now(timezone.utc)
    with Session(engine) as session:
        for category in DISCOVERY_CATEGORIES:
            session.add(
                CityCategoryCache(
                    city_id=city_id,
                    category=category.value,
                    last_fetched_at=now - timedelta(hours=cache_age_hours),
                    expires_at=now - timedelta(hours=cache_age_hours - 24),
                )
            )

        for index in range(count):
            category = DISCOVERY_CATEGORIES[index % len(DISCOVERY_CATEGORIES)]
            place = Place(
                city_id=city_id,
                name=f"Shillong {category.value.title()} {index:02d}",
                category=category.value,
                latitude=25.45 + ((index // 10) * 0.004),
                longitude=91.75 + ((index % 10) * 0.004),
                review_count=index,
                moderation_status="ACTIVE",
            )
            session.add(place)
            session.flush()
            session.add(PlaceTag(place_id=place.id, tag=category.value))
            session.add(
                PlaceSource(
                    place_id=place.id,
                    source="fixture",
                    external_place_id=f"fixture-{index}",
                    licence_identifier="test-only",
                    last_fetched_at=now,
                )
            )
        session.commit()


def _post_recommendations(api, *, limit: int = 10):
    return api["client"].post(
        f"/cities/{api['city_id']}/recommendations",
        json={
            "categories": [category.value for category in DISCOVERY_CATEGORIES],
            "limit": limit,
        },
    )


def _assert_no_place_provider_calls(api) -> None:
    api["audiala"].search_nearby_places_for_categories.assert_not_awaited()
    api["geoapify"].search_nearby_places_for_categories.assert_not_awaited()
    api["overpass"].search_nearby_places_for_categories.assert_not_awaited()
    api["overpass"].search_nearby_places.assert_not_awaited()


def test_over_age_shillong_returns_persisted_first_page_with_providers_down(
    cache_first_api,
) -> None:
    _seed_places(
        cache_first_api["engine"],
        cache_first_api["city_id"],
        count=73,
    )

    response = _post_recommendations(cache_first_api)

    assert response.status_code == 200
    assert len(response.json()) == 10
    _assert_no_place_provider_calls(cache_first_api)


def test_foreground_recommendation_calls_zero_place_providers(cache_first_api) -> None:
    _seed_places(cache_first_api["engine"], cache_first_api["city_id"], count=7)

    response = _post_recommendations(cache_first_api)

    assert response.status_code == 200
    _assert_no_place_provider_calls(cache_first_api)


def test_three_over_age_stored_rows_return_immediately(cache_first_api) -> None:
    _seed_places(cache_first_api["engine"], cache_first_api["city_id"], count=3)

    response = _post_recommendations(cache_first_api)

    assert response.status_code == 200
    assert len(response.json()) == 3
    _assert_no_place_provider_calls(cache_first_api)


def test_empty_city_returns_200_and_non_blocking_refresh_state(cache_first_api) -> None:
    response = _post_recommendations(cache_first_api)

    assert response.status_code == 200
    assert response.json() == []
    assert response.headers["x-refresh-state"] in {
        "queued",
        "refreshing",
        "unavailable",
    }
    assert cache_first_api["refresh_service"].enqueued
    _assert_no_place_provider_calls(cache_first_api)


def test_shillong_first_page_is_ten_without_provider_io(cache_first_api) -> None:
    _seed_places(
        cache_first_api["engine"],
        cache_first_api["city_id"],
        count=73,
    )

    response = _post_recommendations(cache_first_api, limit=10)

    assert response.status_code == 200
    assert len(response.json()) == 10
    assert response.headers.get("x-next-cursor")
    _assert_no_place_provider_calls(cache_first_api)
