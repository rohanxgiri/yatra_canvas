"""Tests for real road-route geometry service, providers, and endpoint."""

from collections.abc import Generator
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import httpx
import pytest
from fastapi.testclient import TestClient
from sqlalchemy.engine import Engine
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine

from app.database import get_session
from app.main import app
from app.models import City, Place, Trip, TripItinerary
from app.routers.route_geometry import (
    get_route_geometry_provider,
    get_route_geometry_service,
)
from app.services.route_geometry_service import (
    LegData,
    OpenRouteServiceGeometryProvider,
    OSRMGeometryProvider,
    RouteGeometryConfigurationError,
    RouteGeometryData,
    RouteGeometryProvider,
    RouteGeometryService,
    RouteGeometryTimeoutError,
    RouteGeometryTripNotFoundError,
    RouteGeometryUnavailableError,
    RouteGeometryValidationError,
    RoutePoint,
)


@pytest.fixture(name="engine")
def engine_fixture() -> Generator[Engine, None, None]:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)
    yield engine


@pytest.fixture(name="session")
def session_fixture(engine: Engine) -> Generator[Session, None, None]:
    with Session(engine) as session:
        yield session


@pytest.fixture(name="client")
def client_fixture(session: Session) -> Generator[TestClient, None, None]:
    def override_get_session() -> Generator[Session, None, None]:
        yield session

    app.dependency_overrides[get_session] = override_get_session
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


class FakeGeometryProvider:
    def __init__(self, coordinates: list[list[float]] | None = None) -> None:
        self.calls: list[list[RoutePoint]] = []
        self._custom_coords = coordinates
        self.raise_timeout = False
        self.raise_unavailable = False
        self.raise_config = False

    async def get_route_geometry(
        self,
        waypoints: list[RoutePoint],
    ) -> RouteGeometryData:
        self.calls.append(waypoints)
        if self.raise_timeout:
            raise RouteGeometryTimeoutError("Routing provider timed out.")
        if self.raise_unavailable:
            raise RouteGeometryUnavailableError("Routing provider unavailable.")
        if self.raise_config:
            raise RouteGeometryConfigurationError("Routing configuration invalid.")

        coords = self._custom_coords or [
            [p.latitude, p.longitude] for p in waypoints
        ]
        legs = [
            LegData(
                start_latitude=waypoints[i].latitude,
                start_longitude=waypoints[i].longitude,
                end_latitude=waypoints[i + 1].latitude,
                end_longitude=waypoints[i + 1].longitude,
                distance_meters=1500.0,
                duration_seconds=300.0,
            )
            for i in range(len(waypoints) - 1)
        ]
        return RouteGeometryData(
            coordinates=coords,
            distance_meters=1500.0 * max(1, len(waypoints) - 1),
            duration_seconds=300.0 * max(1, len(waypoints) - 1),
            legs=legs,
        )


def _create_trip_and_places(session: Session) -> tuple[Trip, list[Place]]:
    city = City(
        name="Jaipur",
        country="India",
        state="Rajasthan",
        latitude=26.9124,
        longitude=75.7873,
    )
    session.add(city)
    session.commit()
    session.refresh(city)

    trip = Trip(
        city_id=city.id,
        user_id=uuid4(),
        trip_name="Jaipur Exploration",
        days=2,
        start_date=datetime(2026, 8, 25, tzinfo=timezone.utc),
        start_location_type="hotel",
        start_location_name="Heritage Haveli",
        start_latitude=26.9124,
        start_longitude=75.7873,
    )
    session.add(trip)

    places = [
        Place(
            city_id=city.id,
            name="Hawa Mahal",
            category="sightseeing",
            latitude=26.9239,
            longitude=75.8267,
        ),
        Place(
            city_id=city.id,
            name="City Palace",
            category="sightseeing",
            latitude=26.9258,
            longitude=75.8236,
        ),
        Place(
            city_id=city.id,
            name="Amer Fort",
            category="historic",
            latitude=26.9855,
            longitude=75.8513,
        ),
    ]
    session.add_all(places)
    session.commit()
    session.refresh(trip)
    for p in places:
        session.refresh(p)
    return trip, places


# ---------------------------------------------------------------------------
# Provider Tests
# ---------------------------------------------------------------------------

@pytest.mark.anyio
async def test_ors_provider_requires_api_key_for_hosted_api() -> None:
    provider = OpenRouteServiceGeometryProvider(
        api_key=None,
        base_url="https://api.openrouteservice.org",
    )
    with pytest.raises(RouteGeometryConfigurationError, match="OPENROUTESERVICE_API_KEY is required"):
        await provider.get_route_geometry([RoutePoint(26.9, 75.8), RoutePoint(26.95, 75.85)])


@pytest.mark.anyio
async def test_ors_provider_normalizes_geojson(monkeypatch: pytest.MonkeyPatch) -> None:
    async def mock_post(*args, **kwargs) -> httpx.Response:
        # Check coordinates format: ORS expects [lon, lat]
        payload = kwargs.get("json", {})
        coords = payload.get("coordinates", [])
        assert coords == [[75.8, 26.9], [75.85, 26.95]]

        fake_body = {
            "type": "FeatureCollection",
            "features": [
                {
                    "type": "Feature",
                    "geometry": {
                        "type": "LineString",
                        "coordinates": [
                            [75.8000, 26.9000],
                            [75.8250, 26.9250],
                            [75.8500, 26.9500],
                        ],
                    },
                    "properties": {
                        "summary": {"distance": 5200.0, "duration": 720.0},
                        "segments": [{"distance": 5200.0, "duration": 720.0}],
                    },
                }
            ],
        }
        return httpx.Response(200, json=fake_body)

    monkeypatch.setattr(httpx.AsyncClient, "post", mock_post)

    provider = OpenRouteServiceGeometryProvider(api_key="test-key")
    result = await provider.get_route_geometry([
        RoutePoint(26.9, 75.8),
        RoutePoint(26.95, 75.85),
    ])

    # Coordinates must be converted to [latitude, longitude]
    assert result.coordinates == [
        [26.9000, 75.8000],
        [26.9250, 75.8250],
        [26.9500, 75.8500],
    ]
    assert result.distance_meters == 5200.0
    assert result.duration_seconds == 720.0
    assert len(result.legs) == 1
    assert result.legs[0].start_latitude == 26.9
    assert result.legs[0].end_latitude == 26.95


@pytest.mark.anyio
async def test_ors_provider_timeout(monkeypatch: pytest.MonkeyPatch) -> None:
    async def mock_post(*args, **kwargs) -> httpx.Response:
        raise httpx.ReadTimeout("Timeout")

    monkeypatch.setattr(httpx.AsyncClient, "post", mock_post)

    provider = OpenRouteServiceGeometryProvider(api_key="test-key")
    with pytest.raises(RouteGeometryTimeoutError):
        await provider.get_route_geometry([RoutePoint(26.9, 75.8), RoutePoint(26.95, 75.85)])


@pytest.mark.anyio
async def test_osrm_provider_normalizes_geojson(monkeypatch: pytest.MonkeyPatch) -> None:
    async def mock_get(self, url: str, *args, **kwargs) -> httpx.Response:
        assert "route/v1/driving/75.800000,26.900000;75.850000,26.950000" in str(url)
        fake_body = {
            "code": "Ok",
            "routes": [
                {
                    "geometry": {
                        "coordinates": [
                            [75.8000, 26.9000],
                            [75.8100, 26.9100],
                            [75.8500, 26.9500],
                        ],
                        "type": "LineString",
                    },
                    "distance": 4800.0,
                    "duration": 600.0,
                    "legs": [{"distance": 4800.0, "duration": 600.0}],
                }
            ],
        }
        return httpx.Response(200, json=fake_body)

    monkeypatch.setattr(httpx.AsyncClient, "get", mock_get)

    provider = OSRMGeometryProvider()
    result = await provider.get_route_geometry([
        RoutePoint(26.9, 75.8),
        RoutePoint(26.95, 75.85),
    ])

    assert result.coordinates == [
        [26.9000, 75.8000],
        [26.9100, 75.8100],
        [26.9500, 75.8500],
    ]
    assert result.distance_meters == 4800.0
    assert result.duration_seconds == 600.0
    assert len(result.legs) == 1


# ---------------------------------------------------------------------------
# Service Tests: Waypoint Ordering, Multi-Day, Caching
# ---------------------------------------------------------------------------

@pytest.mark.anyio
async def test_route_geometry_service_orders_waypoints_correctly(session: Session) -> None:
    trip, places = _create_trip_and_places(session)

    # Seed Day 1 itinerary: Place 2 first, then Place 1
    session.add(TripItinerary(trip_id=trip.id, place_id=places[1].id, day_number=1, visit_order=1))
    session.add(TripItinerary(trip_id=trip.id, place_id=places[0].id, day_number=1, visit_order=2))
    session.commit()

    provider = FakeGeometryProvider()
    service = RouteGeometryService()

    result = await service.get_trip_geometry(session, trip.id, provider)

    assert len(result.days) == 1
    day1 = result.days[0]
    assert day1.day_number == 1

    # Check waypoints received by provider:
    # 1. Start location: 26.9124, 75.7873
    # 2. Visit 1 (Place 2 - City Palace): 26.9258, 75.8236
    # 3. Visit 2 (Place 1 - Hawa Mahal): 26.9239, 75.8267
    assert len(provider.calls) == 1
    waypoints = provider.calls[0]
    assert len(waypoints) == 3
    assert waypoints[0].latitude == trip.start_latitude
    assert waypoints[0].longitude == trip.start_longitude
    assert waypoints[1].latitude == places[1].latitude
    assert waypoints[2].latitude == places[0].latitude


@pytest.mark.anyio
async def test_route_geometry_service_multi_day_partitioning(session: Session) -> None:
    trip, places = _create_trip_and_places(session)

    # Day 1: Place 0
    session.add(TripItinerary(trip_id=trip.id, place_id=places[0].id, day_number=1, visit_order=1))
    # Day 2: Place 1, Place 2
    session.add(TripItinerary(trip_id=trip.id, place_id=places[1].id, day_number=2, visit_order=1))
    session.add(TripItinerary(trip_id=trip.id, place_id=places[2].id, day_number=2, visit_order=2))
    session.commit()

    provider = FakeGeometryProvider()
    service = RouteGeometryService()

    result = await service.get_trip_geometry(session, trip.id, provider)

    assert len(result.days) == 2
    assert result.days[0].day_number == 1
    assert result.days[1].day_number == 2

    # Provider was called once for Day 1 and once for Day 2
    assert len(provider.calls) == 2
    # Day 1 waypoints: Start -> Place 0
    assert len(provider.calls[0]) == 2
    assert provider.calls[0][0].latitude == trip.start_latitude
    assert provider.calls[0][1].latitude == places[0].latitude

    # Day 2 waypoints: Start -> Place 1 -> Place 2
    assert len(provider.calls[1]) == 3
    assert provider.calls[1][0].latitude == trip.start_latitude
    assert provider.calls[1][1].latitude == places[1].latitude
    assert provider.calls[1][2].latitude == places[2].latitude


@pytest.mark.anyio
async def test_route_geometry_service_day_filtering(session: Session) -> None:
    trip, places = _create_trip_and_places(session)
    session.add(TripItinerary(trip_id=trip.id, place_id=places[0].id, day_number=1, visit_order=1))
    session.add(TripItinerary(trip_id=trip.id, place_id=places[1].id, day_number=2, visit_order=1))
    session.commit()

    provider = FakeGeometryProvider()
    service = RouteGeometryService()

    # Request only day 2
    result = await service.get_trip_geometry(session, trip.id, provider, day_number=2)
    assert len(result.days) == 1
    assert result.days[0].day_number == 2
    assert len(provider.calls) == 1
    assert provider.calls[0][1].latitude == places[1].latitude


@pytest.mark.anyio
async def test_route_geometry_service_cache_hit_and_eviction(session: Session) -> None:
    trip, places = _create_trip_and_places(session)
    session.add(TripItinerary(trip_id=trip.id, place_id=places[0].id, day_number=1, visit_order=1))
    session.commit()

    provider = FakeGeometryProvider()
    service = RouteGeometryService(cache_ttl_minutes=10)
    now = datetime(2026, 9, 2, 12, 0, 0, tzinfo=timezone.utc)

    # First call: cache miss
    await service.get_trip_geometry(session, trip.id, provider, now=now)
    assert len(provider.calls) == 1

    # Second call at same time: cache hit (no provider call)
    await service.get_trip_geometry(session, trip.id, provider, now=now)
    assert len(provider.calls) == 1

    # Call after TTL expired: cache miss
    later = now + timedelta(minutes=15)
    await service.get_trip_geometry(session, trip.id, provider, now=later)
    assert len(provider.calls) == 2

    # Invalidate cache
    service.invalidate_trip_cache(trip.id)
    await service.get_trip_geometry(session, trip.id, provider, now=later)
    assert len(provider.calls) == 3


@pytest.mark.anyio
async def test_route_geometry_service_empty_itinerary(session: Session) -> None:
    trip, _ = _create_trip_and_places(session)
    provider = FakeGeometryProvider()
    service = RouteGeometryService()

    result = await service.get_trip_geometry(session, trip.id, provider)
    assert result.days == []
    assert result.total_distance_meters == 0.0
    assert result.total_duration_seconds == 0.0
    assert len(provider.calls) == 0


@pytest.mark.anyio
async def test_route_geometry_service_invalid_coordinates(session: Session) -> None:
    service = RouteGeometryService()

    with pytest.raises(RouteGeometryValidationError, match="Invalid latitude"):
        service._validate_coordinate(999.0, 75.0)

    with pytest.raises(RouteGeometryValidationError, match="Invalid longitude"):
        service._validate_coordinate(26.0, 999.0)

    trip, _ = _create_trip_and_places(session)
    provider = FakeGeometryProvider()
    with pytest.raises(RouteGeometryValidationError, match="day_number"):
        await service.get_trip_geometry(session, trip.id, provider, day_number=0)


# ---------------------------------------------------------------------------
# API Endpoint Tests
# ---------------------------------------------------------------------------

def test_api_route_geometry_success(client: TestClient, session: Session) -> None:
    trip, places = _create_trip_and_places(session)
    session.add(TripItinerary(trip_id=trip.id, place_id=places[0].id, day_number=1, visit_order=1))
    session.commit()

    fake_provider = FakeGeometryProvider(
        coordinates=[[26.9124, 75.7873], [26.9150, 75.7900], [26.9239, 75.8267]]
    )
    app.dependency_overrides[get_route_geometry_provider] = lambda: fake_provider

    response = client.get(f"/trips/{trip.id}/route-geometry")
    assert response.status_code == 200
    data = response.json()
    assert data["trip_id"] == str(trip.id)
    assert len(data["days"]) == 1
    assert data["days"][0]["day_number"] == 1
    assert len(data["days"][0]["coordinates"]) == 3
    assert data["days"][0]["coordinates"][0] == [26.9124, 75.7873]


def test_api_route_geometry_trip_not_found(client: TestClient) -> None:
    unknown_id = uuid4()
    response = client.get(f"/trips/{unknown_id}/route-geometry")
    assert response.status_code == 404


def test_api_route_geometry_provider_timeout_maps_to_504(
    client: TestClient, session: Session
) -> None:
    trip, places = _create_trip_and_places(session)
    session.add(TripItinerary(trip_id=trip.id, place_id=places[0].id, day_number=1, visit_order=1))
    session.commit()

    fake_provider = FakeGeometryProvider()
    fake_provider.raise_timeout = True
    app.dependency_overrides[get_route_geometry_provider] = lambda: fake_provider

    response = client.get(f"/trips/{trip.id}/route-geometry")
    assert response.status_code == 504


def test_api_route_geometry_provider_unavailable_maps_to_502(
    client: TestClient, session: Session
) -> None:
    trip, places = _create_trip_and_places(session)
    session.add(TripItinerary(trip_id=trip.id, place_id=places[0].id, day_number=1, visit_order=1))
    session.commit()

    fake_provider = FakeGeometryProvider()
    fake_provider.raise_unavailable = True
    app.dependency_overrides[get_route_geometry_provider] = lambda: fake_provider

    response = client.get(f"/trips/{trip.id}/route-geometry")
    assert response.status_code == 502


def test_api_route_geometry_provider_config_error_maps_to_503(
    client: TestClient, session: Session
) -> None:
    trip, places = _create_trip_and_places(session)
    session.add(TripItinerary(trip_id=trip.id, place_id=places[0].id, day_number=1, visit_order=1))
    session.commit()

    fake_provider = FakeGeometryProvider()
    fake_provider.raise_config = True
    app.dependency_overrides[get_route_geometry_provider] = lambda: fake_provider

    response = client.get(f"/trips/{trip.id}/route-geometry")
    assert response.status_code == 503
