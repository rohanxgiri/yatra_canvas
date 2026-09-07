"""Integrated, provider-isolated tests for the core trip lifecycle."""

from __future__ import annotations

from collections.abc import Generator
from datetime import date
from time import perf_counter
from uuid import UUID, uuid4

import pytest
from app.database import get_session
from app.main import app
from app.models import (
    City,
    Place,
    PlaceOpeningHours,
    RouteMatrixCache,
    TripItinerary,
    UserSavedPlace,
)
from app.routers.route_optimization import get_route_provider as get_optimizer_provider
from app.routers.smart_replanning import get_route_provider as get_replanner_provider
from app.services.google_routes_service import RouteCoordinate, RouteMatrixLeg
from app.services.local_routes_service import LocalRoutesService
from fastapi.testclient import TestClient
from sqlalchemy.engine import Engine
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select


class CountingRoutes(LocalRoutesService):
    """Deterministic offline route provider with observable call counts."""

    def __init__(self) -> None:
        self.calls = 0
        self.requested_legs = 0

    async def compute_matrix(
        self,
        origins: list[RouteCoordinate],
        destinations: list[RouteCoordinate],
    ) -> dict[tuple[int, int], RouteMatrixLeg]:
        self.calls += 1
        self.requested_legs += len(origins) * len(destinations)
        return await super().compute_matrix(origins, destinations)


@pytest.fixture
def flow_env() -> Generator[tuple[TestClient, Engine, CountingRoutes], None, None]:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)

    def override_session() -> Generator[Session, None, None]:
        with Session(engine) as session:
            yield session

    routes = CountingRoutes()
    app.dependency_overrides[get_session] = override_session
    app.dependency_overrides[get_optimizer_provider] = lambda: routes
    app.dependency_overrides[get_replanner_provider] = lambda: routes
    client = TestClient(app)
    yield client, engine, routes
    client.close()
    app.dependency_overrides.clear()
    SQLModel.metadata.drop_all(engine)


def _create_trip(client: TestClient, engine: Engine, *, days: int) -> tuple[str, str]:
    with Session(engine) as session:
        city = City(
            id=uuid4(),
            name=f"Flow City {uuid4()}",
            state="Kerala",
            country="India",
            latitude=9.9312,
            longitude=76.2673,
        )
        session.add(city)
        session.commit()
        city_id = str(city.id)

    start = date(2026, 9, 14)
    end = date.fromordinal(start.toordinal() + days - 1)
    response = client.post(
        "/trips",
        json={
            "city_id": city_id,
            "trip_name": "Integrated core flow",
            "start_date": start.isoformat(),
            "end_date": end.isoformat(),
            "days": days,
            "arrival_place": "Central Station",
            "arrival_latitude": 9.9312,
            "arrival_longitude": 76.2673,
            "start_location_type": "arrival",
            "purposes": ["sightseeing"],
            "preferences": ["heritage"],
        },
    )
    assert response.status_code == 201, response.text
    return response.json()["trip_id"], city_id


def _add_places(
    client: TestClient,
    engine: Engine,
    trip_id: str,
    city_id: str,
    count: int,
    *,
    locked_day_id: str | None = None,
) -> list[UUID]:
    place_ids: list[UUID] = []
    with Session(engine) as session:
        for index in range(count):
            place = Place(
                id=uuid4(),
                city_id=UUID(city_id),
                name=f"Flow Place {index + 1}",
                category="park",
                latitude=9.94 + index * 0.001,
                longitude=76.27 + index * 0.001,
                opening_hours_status="UNKNOWN" if index % 3 == 1 else "KNOWN",
            )
            session.add(place)
            session.flush()
            place_ids.append(place.id)

            if index % 3 != 1:
                intervals = (
                    [
                        {"open": "09:00", "close": "11:00"},
                        {"open": "14:00", "close": "22:00"},
                    ]
                    if index % 3 == 2
                    else [{"open": "09:00", "close": "19:00"}]
                )
                for weekday in range(7):
                    session.add(
                        PlaceOpeningHours(
                            place_id=place.id,
                            day_of_week=weekday,
                            status="KNOWN",
                            intervals=intervals,
                        )
                    )
        session.commit()

    for index, place_id in enumerate(place_ids):
        payload: dict[str, object] = {"place_id": str(place_id)}
        if index == 0 and locked_day_id is not None:
            payload.update(
                {
                    "assignment_mode": "LOCKED",
                    "assigned_day_id": locked_day_id,
                    "must_visit": True,
                    "priority": 10,
                }
            )
        response = client.post(f"/trips/{trip_id}/saved-places", json=payload)
        assert response.status_code == 201, response.text
    return place_ids


def _minutes(value: str) -> int:
    hour, minute, *_ = map(int, value.split(":"))
    return hour * 60 + minute


def _assert_route_invariants(
    route: dict[str, object],
    *,
    day_windows: dict[int, tuple[int, int]],
) -> None:
    stops = route["optimized_places"]
    assert isinstance(stops, list)
    seen_places: set[str] = set()
    seen_orders: set[tuple[int, int]] = set()
    for stop in stops:
        assert isinstance(stop, dict)
        place_id = str(stop["place_id"])
        day_number = int(stop["day_number"])
        visit_order = int(stop["visit_order"])
        arrival = _minutes(str(stop["planned_arrival_time"]))
        departure = _minutes(str(stop["planned_departure_time"]))
        day_start, day_end = day_windows[day_number]
        assert day_start <= arrival < departure <= day_end
        assert departure - arrival == int(stop["visit_duration_minutes"])
        assert place_id not in seen_places
        assert (day_number, visit_order) not in seen_orders
        seen_places.add(place_id)
        seen_orders.add((day_number, visit_order))


def test_normal_trip_execution_move_and_cache_are_integrated(flow_env) -> None:
    client, engine, routes = flow_env
    trip_id, city_id = _create_trip(client, engine, days=5)
    days = client.get(f"/trips/{trip_id}/days").json()
    assert [day["day_number"] for day in days] == [1, 2, 3, 4, 5]

    assert (
        client.patch(f"/trips/{trip_id}/days/3", json={"day_type": "REST"}).status_code
        == 200
    )
    assert (
        client.patch(
            f"/trips/{trip_id}/days/4",
            json={"day_type": "HALF_DAY", "start_time": "09:00", "end_time": "13:00"},
        ).status_code
        == 200
    )
    assert (
        client.patch(
            f"/trips/{trip_id}/days/5",
            json={"day_type": "TRAVEL", "start_time": "15:00", "end_time": "18:00"},
        ).status_code
        == 200
    )
    days = client.get(f"/trips/{trip_id}/days").json()
    locked_day = next(day for day in days if day["day_number"] == 4)
    place_ids = _add_places(
        client,
        engine,
        trip_id,
        city_id,
        15,
        locked_day_id=locked_day["id"],
    )

    started = perf_counter()
    optimized = client.post(f"/trips/{trip_id}/optimize-route")
    elapsed = perf_counter() - started
    assert optimized.status_code == 200, optimized.text
    route = optimized.json()
    assert route["total_days"] == 5
    assert all(stop["day_number"] != 3 for stop in route["optimized_places"])
    locked = next(
        stop
        for stop in route["optimized_places"]
        if stop["place_id"] == str(place_ids[0])
    )
    assert locked["day_number"] == 4
    _assert_route_invariants(
        route,
        day_windows={1: (540, 1140), 2: (540, 1140), 4: (540, 780), 5: (900, 1080)},
    )

    with Session(engine) as session:
        hours = {
            (str(row.place_id), row.day_of_week): row.intervals
            for row in session.exec(select(PlaceOpeningHours)).all()
        }
    trip_start = date(2026, 9, 14)
    for stop in route["optimized_places"]:
        key = (
            stop["place_id"],
            (trip_start.toordinal() - 1 + stop["day_number"] - 1) % 7,
        )
        if key not in hours:
            assert stop["is_opening_hours_known"] is False
            continue
        arrival = _minutes(stop["planned_arrival_time"])
        departure = _minutes(stop["planned_departure_time"])
        assert any(
            _minutes(interval["open"]) <= arrival
            and departure <= _minutes(interval["close"])
            for interval in hours[key]
        )

    day_one = [stop for stop in route["optimized_places"] if stop["day_number"] == 1]
    assert len(day_one) >= 2
    completed, missed = day_one[:2]
    calls_after_plan = routes.calls
    assert (
        client.patch(
            f"/trips/{trip_id}/itinerary/stops/{completed['id']}",
            json={"status": "COMPLETED"},
        ).status_code
        == 200
    )
    assert (
        client.patch(
            f"/trips/{trip_id}/itinerary/stops/{missed['id']}",
            json={"status": "MISSED"},
        ).status_code
        == 200
    )
    assert routes.calls == calls_after_plan

    before_move = client.get(f"/trips/{trip_id}/itinerary").json()
    unaffected = [
        stop for stop in before_move["optimized_places"] if stop["day_number"] in (4, 5)
    ]
    started = perf_counter()
    moved = client.post(
        f"/trips/{trip_id}/itinerary/move-place",
        json={"place_id": missed["place_id"], "target_day_number": 2},
    )
    move_elapsed = perf_counter() - started
    assert moved.status_code == 200, moved.text
    assert moved.json()["success"] is True
    assert routes.calls == calls_after_plan
    after_move = moved.json()["updated_itinerary"]
    assert any(
        stop["place_id"] == missed["place_id"] and stop["day_number"] == 2
        for stop in after_move["optimized_places"]
    )
    completed_after = next(
        stop
        for stop in after_move["optimized_places"]
        if stop["place_id"] == completed["place_id"]
    )
    assert completed_after == {**completed, "status": "COMPLETED"}
    assert [
        stop for stop in after_move["optimized_places"] if stop["day_number"] in (4, 5)
    ] == unaffected

    with Session(engine) as session:
        assert len(session.exec(select(RouteMatrixCache)).all()) == 15 * 16
        assignments = session.exec(
            select(UserSavedPlace).where(UserSavedPlace.trip_id == UUID(trip_id))
        ).all()
        assert all(
            (row.assignment_mode == "AUTO" and row.assigned_day_id is None)
            or (row.assignment_mode == "LOCKED" and row.assigned_day_id is not None)
            for row in assignments
        )
        itinerary = session.exec(
            select(TripItinerary).where(TripItinerary.trip_id == UUID(trip_id))
        ).all()
        assert len({(row.day_number, row.visit_order) for row in itinerary}) == len(
            itinerary
        )

    print(
        f"E2E normal 5d/15: optimize={elapsed:.3f}s, move={move_elapsed:.3f}s, "
        f"provider_calls={routes.calls}, requested_legs={routes.requested_legs}"
    )


def test_underfilled_trip_keeps_empty_days_without_fetching_pois(flow_env) -> None:
    client, engine, routes = flow_env
    trip_id, city_id = _create_trip(client, engine, days=5)
    assert (
        client.patch(f"/trips/{trip_id}/days/3", json={"day_type": "REST"}).status_code
        == 200
    )
    selected = _add_places(client, engine, trip_id, city_id, 2)

    response = client.post(f"/trips/{trip_id}/optimize-route")
    assert response.status_code == 200, response.text
    route = response.json()
    assert route["total_days"] == 5
    assert {stop["place_id"] for stop in route["optimized_places"]} == {
        str(place_id) for place_id in selected
    }
    assert all(stop["day_number"] != 3 for stop in route["optimized_places"])
    assert route["unscheduled_places"] == []
    assert routes.requested_legs == 2 * 3


def test_overpacked_trip_returns_explicit_unscheduled_results(flow_env) -> None:
    client, engine, routes = flow_env
    trip_id, city_id = _create_trip(client, engine, days=5)
    for day_number in range(1, 6):
        response = client.patch(
            f"/trips/{trip_id}/days/{day_number}",
            json={
                "day_type": "HALF_DAY",
                "start_time": "09:00",
                "end_time": "11:00",
            },
        )
        assert response.status_code == 200
    _add_places(client, engine, trip_id, city_id, 30)

    started = perf_counter()
    response = client.post(f"/trips/{trip_id}/optimize-route")
    elapsed = perf_counter() - started
    assert response.status_code == 200, response.text
    route = response.json()
    assert route["optimized_places"]
    assert route["unscheduled_places"]
    assert len(route["optimized_places"]) + len(route["unscheduled_places"]) == 30
    assert all(item["reason"] for item in route["unscheduled_places"])
    _assert_route_invariants(
        route,
        day_windows={day: (540, 660) for day in range(1, 6)},
    )
    print(
        f"E2E overpacked 5d/30: optimize={elapsed:.3f}s, "
        f"scheduled={len(route['optimized_places'])}, unscheduled={len(route['unscheduled_places'])}, "
        f"provider_calls={routes.calls}, requested_legs={routes.requested_legs}"
    )
