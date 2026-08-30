"""Route caching, constraints, start location, and offline reuse tests."""

import asyncio
from collections.abc import Generator
from datetime import datetime, timedelta, timezone
import json
from uuid import UUID, uuid4

import httpx
import pytest
from fastapi.testclient import TestClient
from sqlalchemy.engine import Engine
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.database import get_session
from app.main import app
from app.models import RouteMatrixCache, Trip, TripItinerary, UserSavedPlace
from app.routers.route_optimization import get_google_routes_service
from app.services.google_routes_service import (
    GoogleRoutesService,
    GoogleRoutesTimeoutError,
    RouteCoordinate,
    RouteMatrixLeg,
)


class FakeGoogleRoutesService:
    def __init__(self) -> None:
        self.calls: list[tuple[float, list[float]]] = []
        self.fail = False
        self.costs: dict[tuple[float, float], int] = {}

    async def compute_matrix(
        self,
        origins: list[RouteCoordinate],
        destinations: list[RouteCoordinate],
    ) -> dict[tuple[int, int], RouteMatrixLeg]:
        assert len(origins) == 1
        if self.fail:
            raise GoogleRoutesTimeoutError("Google Routes did not respond in time.")
        origin = round(origins[0].latitude, 2)
        destination_values = [round(item.latitude, 2) for item in destinations]
        self.calls.append((origin, destination_values))
        result: dict[tuple[int, int], RouteMatrixLeg] = {}
        for index, destination in enumerate(destination_values):
            seconds = self.costs.get(
                (origin, destination),
                int(abs(origin - destination) * 10000) + 60,
            )
            result[(0, index)] = RouteMatrixLeg(
                distance_meters=seconds * 10,
                static_duration_seconds=seconds,
                traffic_duration_seconds=seconds + 30,
            )
        return result


@pytest.fixture
def client_engine_routes(
) -> Generator[tuple[TestClient, Engine, FakeGoogleRoutesService], None, None]:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)

    def override_session() -> Generator[Session, None, None]:
        with Session(engine) as session:
            yield session

    routes = FakeGoogleRoutesService()
    app.dependency_overrides[get_session] = override_session
    app.dependency_overrides[get_google_routes_service] = lambda: routes
    client = TestClient(app)
    yield client, engine, routes
    client.close()
    app.dependency_overrides.clear()
    SQLModel.metadata.drop_all(engine)


def _create_city(client: TestClient) -> dict[str, object]:
    response = client.post(
        "/cities",
        json={
            "name": "Ujjain",
            "state": "Madhya Pradesh",
            "country": "India",
            "latitude": 23.1765,
            "longitude": 75.7885,
            "google_place_id": f"google-ujjain-route-{uuid4()}",
        },
    )
    assert response.status_code == 201
    return response.json()


def _create_place(
    client: TestClient,
    city_id: str,
    name: str,
    latitude: float,
) -> dict[str, object]:
    response = client.post(
        "/places",
        json={
            "city_id": city_id,
            "name": name,
            "category": "religious",
            "latitude": latitude,
            "longitude": 75.77,
            "rating": 4.7,
            "review_count": 1000,
            "is_popular": True,
            "is_heritage": False,
            "is_local_speciality": False,
            "last_fetched_at": None,
        },
    )
    assert response.status_code == 201
    return response.json()


def _seed_trip_and_saved_places(
    engine: Engine,
    city_id: str,
    place_ids: list[str],
    *,
    start_selected: bool = True,
    saved_settings: list[dict[str, object]] | None = None,
) -> UUID:
    with Session(engine) as session:
        trip = Trip(
            user_id=uuid4(),
            city_id=UUID(city_id),
            trip_name="Ujjain route",
            days=2,
            arrival_place="Ujjain Railway Station",
            arrival_latitude=23.17,
            arrival_longitude=75.78,
            start_location_type="arrival" if start_selected else None,
            start_location_name=(
                "Ujjain Railway Station" if start_selected else None
            ),
            start_latitude=23.17 if start_selected else None,
            start_longitude=75.78 if start_selected else None,
        )
        session.add(trip)
        session.flush()
        for index, place_id in enumerate(place_ids):
            settings = (saved_settings or [{} for _ in place_ids])[index]
            session.add(
                UserSavedPlace(
                    trip_id=trip.id,
                    place_id=UUID(place_id),
                    custom_order=index + 1,
                    priority=int(settings.get("priority", 0)),
                    is_locked=bool(settings.get("is_locked", False)),
                    must_visit=bool(settings.get("must_visit", False)),
                )
            )
        session.commit()
        return trip.id


def test_matrix_cache_reuses_removed_places_and_fetches_only_new_edges(
    client_engine_routes: tuple[TestClient, Engine, FakeGoogleRoutesService],
) -> None:
    client, engine, routes = client_engine_routes
    city = _create_city(client)
    places = [
        _create_place(client, str(city["id"]), "Place A", 23.18),
        _create_place(client, str(city["id"]), "Place B", 23.19),
        _create_place(client, str(city["id"]), "Place C", 23.20),
    ]
    routes.costs.update(
        {
            (23.17, 23.18): 900,
            (23.17, 23.19): 300,
            (23.17, 23.20): 600,
            (23.19, 23.20): 120,
            (23.20, 23.18): 240,
        }
    )
    trip_id = _seed_trip_and_saved_places(
        engine,
        str(city["id"]),
        [str(place["id"]) for place in places],
    )

    response = client.post(f"/trips/{trip_id}/optimize-route")
    assert response.status_code == 200
    assert [item["name"] for item in response.json()["optimized_places"]] == [
        "Place B",
        "Place C",
        "Place A",
    ]
    assert len(routes.calls) == 4
    with Session(engine) as session:
        assert len(session.exec(select(RouteMatrixCache)).all()) == 12
        assert len(session.exec(select(TripItinerary)).all()) == 3

    assert client.post(f"/trips/{trip_id}/optimize-route").status_code == 200
    assert client.delete(
        f"/trips/{trip_id}/saved-places/{places[2]['id']}"
    ).status_code == 204
    assert client.post(f"/trips/{trip_id}/optimize-route").status_code == 200
    assert len(routes.calls) == 4
    with Session(engine) as session:
        assert len(session.exec(select(RouteMatrixCache)).all()) == 12

    place_d = _create_place(client, str(city["id"]), "Place D", 23.21)
    assert client.post(
        f"/trips/{trip_id}/saved-places",
        json={"place_id": place_d["id"]},
    ).status_code == 201
    assert client.post(f"/trips/{trip_id}/optimize-route").status_code == 200
    assert len(routes.calls) == 8
    with Session(engine) as session:
        assert len(session.exec(select(RouteMatrixCache)).all()) == 18


def test_locked_must_visit_and_priority_constraints_are_respected(
    client_engine_routes: tuple[TestClient, Engine, FakeGoogleRoutesService],
) -> None:
    client, engine, routes = client_engine_routes
    city = _create_city(client)
    places = [
        _create_place(client, str(city["id"]), "Locked A", 23.18),
        _create_place(client, str(city["id"]), "Priority B", 23.19),
        _create_place(client, str(city["id"]), "Nearby C", 23.20),
    ]
    trip_id = _seed_trip_and_saved_places(
        engine,
        str(city["id"]),
        [str(place["id"]) for place in places],
        saved_settings=[
            {"priority": 10, "is_locked": True, "must_visit": True},
            {"priority": 9},
            {"priority": 1},
        ],
    )
    routes.costs.update(
        {
            (23.17, 23.18): 1000,
            (23.17, 23.19): 500,
            (23.17, 23.20): 50,
            (23.18, 23.19): 500,
            (23.18, 23.20): 50,
        }
    )

    updated = client.patch(
        f"/trips/{trip_id}/saved-places/{places[0]['id']}",
        json={
            "priority": 10,
            "is_locked": True,
            "must_visit": True,
            "custom_order": 1,
        },
    )
    assert updated.status_code == 200
    assert updated.json()["priority"] == 10
    assert updated.json()["is_locked"] is True
    assert updated.json()["must_visit"] is True

    response = client.post(f"/trips/{trip_id}/optimize-route")
    assert response.status_code == 200
    assert [item["name"] for item in response.json()["optimized_places"]] == [
        "Locked A",
        "Priority B",
        "Nearby C",
    ]


def test_stale_complete_cache_supports_offline_static_reuse(
    client_engine_routes: tuple[TestClient, Engine, FakeGoogleRoutesService],
) -> None:
    client, engine, routes = client_engine_routes
    city = _create_city(client)
    places = [
        _create_place(client, str(city["id"]), "Place A", 23.18),
        _create_place(client, str(city["id"]), "Place B", 23.19),
    ]
    trip_id = _seed_trip_and_saved_places(
        engine,
        str(city["id"]),
        [str(place["id"]) for place in places],
    )
    assert client.post(f"/trips/{trip_id}/optimize-route").status_code == 200
    with Session(engine) as session:
        rows = session.exec(select(RouteMatrixCache)).all()
        for row in rows:
            row.expires_at = datetime.now(timezone.utc) - timedelta(minutes=1)
        session.commit()

    routes.fail = True
    offline = client.post(f"/trips/{trip_id}/optimize-route")
    assert offline.status_code == 200
    assert len(offline.json()["optimized_places"]) == 2


def test_start_location_endpoint_and_route_validation(
    client_engine_routes: tuple[TestClient, Engine, FakeGoogleRoutesService],
) -> None:
    client, engine, routes = client_engine_routes
    assert client.post(f"/trips/{uuid4()}/optimize-route").status_code == 404
    city = _create_city(client)
    places = [
        _create_place(client, str(city["id"]), "Place A", 23.18),
        _create_place(client, str(city["id"]), "Place B", 23.19),
    ]
    trip_id = _seed_trip_and_saved_places(
        engine,
        str(city["id"]),
        [str(place["id"]) for place in places],
        start_selected=False,
    )
    response = client.post(f"/trips/{trip_id}/optimize-route")
    assert response.status_code == 422
    assert "start location" in response.json()["detail"]

    arrival = client.patch(
        f"/trips/{trip_id}/start-location",
        json={"start_location_type": "arrival"},
    )
    assert arrival.status_code == 200
    assert arrival.json()["start_location_name"] == "Ujjain Railway Station"
    hotel = client.patch(
        f"/trips/{trip_id}/start-location",
        json={
            "start_location_type": "hotel",
            "start_location_name": "Hotel Imperial Ujjain",
            "start_latitude": 23.16,
            "start_longitude": 75.79,
        },
    )
    assert hotel.status_code == 200
    assert client.get(f"/trips/{trip_id}/start-location").json() == hotel.json()
    assert client.post(f"/trips/{trip_id}/optimize-route").status_code == 200
    assert routes.calls


def test_google_routes_service_builds_and_parses_static_and_traffic() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/distanceMatrix/v2:computeRouteMatrix"
        assert request.headers["X-Goog-Api-Key"] == "routes-key"
        assert "staticDuration" in request.headers["X-Goog-FieldMask"]
        body = json.loads(request.content)
        assert body["routingPreference"] == "TRAFFIC_AWARE"
        return httpx.Response(
            200,
            json=[
                {
                    "status": {},
                    "condition": "ROUTE_EXISTS",
                    "distanceMeters": 2100,
                    "duration": "480.5s",
                    "staticDuration": "420s",
                }
            ],
        )

    async def run() -> None:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(handler)
        ) as client:
            service = GoogleRoutesService("routes-key", client=client)
            matrix = await service.compute_matrix(
                [RouteCoordinate(23.17, 75.78)],
                [RouteCoordinate(23.18, 75.77)],
            )
        assert matrix[(0, 0)] == RouteMatrixLeg(2100, 420, 481)

    asyncio.run(run())


def test_google_routes_timeout_is_normalized() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("timed out", request=request)

    async def run() -> None:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(handler)
        ) as client:
            service = GoogleRoutesService("routes-key", client=client)
            with pytest.raises(GoogleRoutesTimeoutError):
                await service.compute_matrix(
                    [RouteCoordinate(23.17, 75.78)],
                    [RouteCoordinate(23.18, 75.77)],
                )

    asyncio.run(run())
