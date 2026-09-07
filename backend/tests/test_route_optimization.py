"""Route caching, constraints, start location, and offline reuse tests."""

import asyncio
import json
from collections.abc import Generator
from datetime import datetime, timedelta, timezone
from uuid import UUID, uuid4

import httpx
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import event
from sqlalchemy.engine import Engine
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.database import get_session
from app.main import app
from app.models import RouteMatrixCache, Trip, TripItinerary, UserSavedPlace
from app.routers.route_optimization import get_route_provider
from app.services.google_routes_service import (
    GoogleRoutesConfigurationError,
    GoogleRoutesService,
    GoogleRoutesTimeoutError,
    RouteCoordinate,
    RouteMatrixLeg,
)
from app.services.local_routes_service import LocalRoutesService


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


class CountingLocalRoutesService(LocalRoutesService):
    def __init__(self) -> None:
        self.calls = 0

    async def compute_matrix(
        self,
        origins: list[RouteCoordinate],
        destinations: list[RouteCoordinate],
    ) -> dict[tuple[int, int], RouteMatrixLeg]:
        self.calls += 1
        return await super().compute_matrix(origins, destinations)


def test_local_route_provider_returns_offline_estimates() -> None:
    matrix = asyncio.run(
        LocalRoutesService().compute_matrix(
            [RouteCoordinate(24.578721, 73.6862571)],
            [RouteCoordinate(24.5904609, 73.6747719)],
        )
    )

    leg = matrix[(0, 0)]
    assert leg.distance_meters > 0
    assert leg.static_duration_seconds >= 60
    assert leg.traffic_duration_seconds is None


@pytest.fixture
def client_engine_routes() -> Generator[
    tuple[TestClient, Engine, FakeGoogleRoutesService], None, None
]:
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
    app.dependency_overrides[get_route_provider] = lambda: routes
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
            start_location_name=("Ujjain Railway Station" if start_selected else None),
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
    assert (
        client.delete(f"/trips/{trip_id}/saved-places/{places[2]['id']}").status_code
        == 204
    )
    assert client.post(f"/trips/{trip_id}/optimize-route").status_code == 200
    assert len(routes.calls) == 4
    with Session(engine) as session:
        assert len(session.exec(select(RouteMatrixCache)).all()) == 12

    place_d = _create_place(client, str(city["id"]), "Place D", 23.21)
    assert (
        client.post(
            f"/trips/{trip_id}/saved-places",
            json={"place_id": place_d["id"]},
        ).status_code
        == 201
    )
    assert client.post(f"/trips/{trip_id}/optimize-route").status_code == 200
    assert len(routes.calls) == 8
    with Session(engine) as session:
        assert len(session.exec(select(RouteMatrixCache)).all()) == 18


def test_complete_static_local_matrix_is_reused_without_refresh(
    client_engine_routes: tuple[TestClient, Engine, FakeGoogleRoutesService],
) -> None:
    client, engine, _ = client_engine_routes
    routes = CountingLocalRoutesService()
    app.dependency_overrides[get_route_provider] = lambda: routes
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

    statements: list[str] = []

    def capture_statement(
        _connection: object,
        _cursor: object,
        statement: str,
        _parameters: object,
        _context: object,
        _executemany: bool,
    ) -> None:
        statements.append(statement.lower())

    event.listen(engine, "before_cursor_execute", capture_statement)
    try:
        assert client.post(f"/trips/{trip_id}/optimize-route").status_code == 200
        first_call_count = routes.calls
        assert first_call_count == 3
        assert sum("insert into route_matrix_cache" in sql for sql in statements) == 1

        statements.clear()
        assert client.post(f"/trips/{trip_id}/optimize-route").status_code == 200
        assert routes.calls == first_call_count
        assert sum("from route_matrix_cache" in sql for sql in statements) == 1
    finally:
        event.remove(engine, "before_cursor_execute", capture_statement)


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
    stops = response.json()["optimized_places"]
    assert stops[0]["name"] == "Locked A"
    assert {item["name"] for item in stops} == {"Locked A", "Priority B", "Nearby C"}
    # Priority affects retention; it must not impose infeasible visit precedence.


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
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
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
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            service = GoogleRoutesService("routes-key", client=client)
            with pytest.raises(GoogleRoutesTimeoutError):
                await service.compute_matrix(
                    [RouteCoordinate(23.17, 75.78)],
                    [RouteCoordinate(23.18, 75.77)],
                )

    asyncio.run(run())


def test_missing_google_routes_key_fails_without_a_request() -> None:
    with pytest.raises(GoogleRoutesConfigurationError) as captured:
        asyncio.run(
            GoogleRoutesService(None).compute_matrix(
                [RouteCoordinate(23.1765, 75.7885)],
                [RouteCoordinate(23.1828, 75.7682)],
            )
        )

    assert str(captured.value) == ("Google Routes is not configured on the backend.")


def test_multi_day_chunking_respects_time_budget(
    client_engine_routes: tuple[TestClient, Engine, FakeGoogleRoutesService],
) -> None:
    client, engine, routes = client_engine_routes
    city = _create_city(client)
    
    # Create 5 places
    places = []
    for i in range(5):
        places.append(_create_place(client, str(city["id"]), f"Place {i}", 23.18 + (i * 0.01)))
        
    # Travel time will be long to force chunking
    # DEFAULT_VISIT_DURATION_MINUTES = 120
    # DEFAULT_DAILY_BUDGET_MINUTES = 600
    # If travel time is 300 minutes, 1 place = 420 mins (fits), 2 places = 840 mins (exceeds budget)
    # This forces exactly 1 place per day. If trip.days = 5, they should perfectly fit 1 per day.
    for p in places:
        routes.costs[(23.17, p["latitude"])] = 300 * 60  # from start
        routes.costs[(p["latitude"], 23.17)] = 300 * 60
        for p2 in places:
            if p != p2:
                routes.costs[(p["latitude"], p2["latitude"])] = 300 * 60

    trip_id = _seed_trip_and_saved_places(
        engine,
        str(city["id"]),
        [str(p["id"]) for p in places],
    )
    with Session(engine) as session:
        trip = session.get(Trip, trip_id)
        trip.days = 5
        session.commit()

    response = client.post(f"/trips/{trip_id}/optimize-route")
    assert response.status_code == 200
    optimized = response.json()["optimized_places"]
    assert len(optimized) == 5
    # Should be partitioned across 5 days
    assert [p["day_number"] for p in optimized] == [1, 2, 3, 4, 5]


def test_infeasible_trip_returns_unscheduled_must_visits(
    client_engine_routes: tuple[TestClient, Engine, FakeGoogleRoutesService],
) -> None:
    client, engine, routes = client_engine_routes
    city = _create_city(client)
    
    places = []
    for i in range(5):
        places.append(_create_place(client, str(city["id"]), f"Place {i}", 23.18 + (i * 0.01)))
        
    # Same high travel times, but trip is only 2 days!
    for p in places:
        routes.costs[(23.17, p["latitude"])] = 300 * 60
        routes.costs[(p["latitude"], 23.17)] = 300 * 60
        for p2 in places:
            if p != p2:
                routes.costs[(p["latitude"], p2["latitude"])] = 300 * 60

    trip_id = _seed_trip_and_saved_places(
        engine,
        str(city["id"]),
        [str(p["id"]) for p in places],
        saved_settings=[{"must_visit": True} for _ in places]
    )
    with Session(engine) as session:
        trip = session.get(Trip, trip_id)
        trip.days = 2
        session.commit()

    response = client.post(f"/trips/{trip_id}/optimize-route")
    assert response.status_code == 200
    body = response.json()
    assert body["optimized_places"]
    assert body["unscheduled_places"]
    assert len(body["optimized_places"]) + len(body["unscheduled_places"]) == 5


def test_fewer_places_than_days_preserves_empty_days(
    client_engine_routes: tuple[TestClient, Engine, FakeGoogleRoutesService],
) -> None:
    client, engine, _ = client_engine_routes
    city = _create_city(client)
    places = [_create_place(client, str(city["id"]), "Place 0", 23.18)]
    
    trip_id = _seed_trip_and_saved_places(engine, str(city["id"]), [str(places[0]["id"])])
    
    with Session(engine) as session:
        trip = session.get(Trip, trip_id)
        trip.days = 5
        session.commit()
        
    response = client.post(f"/trips/{trip_id}/optimize-route")
    assert response.status_code == 200
    assert response.json()["total_days"] == 5
    assert len(response.json()["optimized_places"]) == 1


def test_persisted_days_hours_and_preview_use_same_constraints(client_engine_routes):
    from datetime import date, time
    from app.models.entities import TripDay, PlaceOpeningHours
    from app.services.smart_replanning_service import SmartReplanningService
    from app.services.route_matrix_service import RouteMatrixService
    import asyncio

    client, engine, provider = client_engine_routes
    city = _create_city(client)
    places = [_create_place(client, str(city["id"]), f"Stored {i}", 23.18+i*.01) for i in range(3)]
    trip_id = _seed_trip_and_saved_places(engine, str(city["id"]), [p["id"] for p in places])
    with Session(engine) as session:
        trip = session.get(Trip, trip_id)
        trip.days = 3
        days = [TripDay(trip_id=trip.id, day_number=n, date=date(2026,9,6+n),
                        day_type="REST" if n==2 else "HALF_DAY",
                        start_time=time(14), end_time=time(17)) for n in range(1,4)]
        session.add_all(days)
        row = session.exec(select(UserSavedPlace).where(UserSavedPlace.trip_id==trip.id,
                    UserSavedPlace.place_id==UUID(places[0]["id"]))).one()
        row.assignment_mode, row.assigned_day_id = "LOCKED", days[2].id
        for weekday in (0,2):
            session.add(PlaceOpeningHours(place_id=UUID(places[1]["id"]),
                        day_of_week=weekday,status="CLOSED"))
            session.add(PlaceOpeningHours(place_id=UUID(places[0]["id"]),
                        day_of_week=weekday,status="KNOWN",intervals=[{"open":"15:00","close":"17:00"}]))
        session.add(trip)
        session.commit()
        preview = asyncio.run(SmartReplanningService().get_replan_preview(
            session, trip.id, provider, RouteMatrixService()))
        assert session.exec(select(TripItinerary).where(TripItinerary.trip_id==trip.id)).all()==[]
        assert preview.unscheduled_places[0].reason=="CLOSED_ON_AVAILABLE_DAYS"
        locked=next(p for p in preview.proposed_itinerary if str(p.place_id)==places[0]["id"])
        assert locked.day_number==3 and locked.planned_arrival_time>=time(15)
    response=client.post(f"/trips/{trip_id}/optimize-route")
    assert response.status_code==200
    body=response.json()
    assert body["unscheduled_places"][0]["reason"]=="CLOSED_ON_AVAILABLE_DAYS"
    assert {p["day_number"] for p in body["optimized_places"]} <= {1,3}
    assert next(p for p in body["optimized_places"] if p["place_id"]==places[0]["id"])["is_opening_hours_known"]
    with Session(engine) as session:
        stored=session.exec(select(TripItinerary).where(TripItinerary.trip_id==trip_id)).all()
        assert len(stored)==len(body["optimized_places"])
        assert all(p.planned_arrival_time is not None and p.planned_departure_time<=time(17) for p in stored)
