"""Comprehensive test suite for Google OR-Tools VRPTW solver engine and pipeline.

Covers:
1. Opening hours time window enforcement and closed-day restrictions
2. Category-based visit durations and service time accounting
3. Multi-day vehicle partitioning across daily touring budgets
4. Midday lunch break scheduling (12:30–14:00)
5. Locked place positioning and ordering
6. Priority and must-visit rules (must-visit preservation, low-priority dropping)
7. Final route geometry fetching and response integration
"""

from datetime import date, time, timedelta
from uuid import UUID, uuid4

import pytest
from sqlalchemy.engine import Engine
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select
from fastapi.testclient import TestClient

from app.database import get_session
from app.main import app
from app.models.entities import City, Place, Trip, TripItinerary, UserSavedPlace
from app.routers.route_optimization import get_route_provider
from app.routers.route_geometry import get_route_geometry_provider
from app.services.google_routes_service import RouteCoordinate, RouteMatrixLeg
from app.services.itinerary_timing_service import PlaceOpeningHours
from app.services.local_routes_service import LocalRoutesService
from app.services.route_geometry_service import (
    LegData,
    RouteGeometryData,
    RouteGeometryProvider,
    RoutePoint,
)
from app.services.route_matrix_service import RouteNode
from app.services.vrptw_solver_service import VrptwSolution, VrptwSolverService


class FakeGeometryProvider(RouteGeometryProvider):
    async def get_route_geometry(
        self,
        waypoints: list[RoutePoint],
    ) -> RouteGeometryData:
        coords = [[p.latitude, p.longitude] for p in waypoints]
        legs = []
        for i in range(len(waypoints) - 1):
            legs.append(
                LegData(
                    start_latitude=waypoints[i].latitude,
                    start_longitude=waypoints[i].longitude,
                    end_latitude=waypoints[i + 1].latitude,
                    end_longitude=waypoints[i + 1].longitude,
                    distance_meters=1500.0,
                    duration_seconds=300.0,
                )
            )
        return RouteGeometryData(
            coordinates=coords,
            distance_meters=1500.0 * max(1, len(waypoints) - 1),
            duration_seconds=300.0 * max(1, len(waypoints) - 1),
            legs=legs,
        )


def _make_node(name: str, lat: float, lon: float, place_id: UUID | None = None) -> RouteNode:
    pid = place_id or uuid4()
    return RouteNode(
        key=f"place:{pid}",
        location_type="place",
        name=name,
        latitude=lat,
        longitude=lon,
        place_id=pid,
    )


def _make_leg(duration_seconds: int, distance_meters: int) -> RouteMatrixLeg:
    return RouteMatrixLeg(
        distance_meters=distance_meters,
        static_duration_seconds=duration_seconds,
        traffic_duration_seconds=duration_seconds,
    )


# ---------------------------------------------------------------------------
# 1. Opening Hours Tests
# ---------------------------------------------------------------------------


def test_vrptw_respects_opening_hours_time_windows() -> None:
    """A place opening at 11:00 AM must not have an arrival time before 11:00 AM."""
    start = RouteNode(
        key="start",
        location_type="arrival",
        name="Hotel",
        latitude=23.17,
        longitude=75.78,
    )
    p1 = Place(
        id=uuid4(),
        city_id=uuid4(),
        name="Late Museum",
        category="museum",  # 120 mins duration
        latitude=23.18,
        longitude=75.78,
    )
    p2 = Place(
        id=uuid4(),
        city_id=uuid4(),
        name="Early Temple",
        category="religious",  # 120 mins duration
        latitude=23.19,
        longitude=75.78,
    )
    places = [p1, p2]
    place_nodes = [_make_node(p.name, p.latitude, p.longitude, p.id) for p in places]
    saved_rows = [
        UserSavedPlace(trip_id=uuid4(), place_id=p1.id),
        UserSavedPlace(trip_id=uuid4(), place_id=p2.id),
    ]

    # Travel time between start and places is short (10 min)
    matrix = {
        (start.key, place_nodes[0].key): _make_leg(600, 5000),
        (start.key, place_nodes[1].key): _make_leg(600, 5000),
        (place_nodes[0].key, place_nodes[1].key): _make_leg(600, 5000),
        (place_nodes[1].key, place_nodes[0].key): _make_leg(600, 5000),
    }

    # Museum opens at 11:00 AM and closes at 17:00
    opening_map = {
        p1.id: PlaceOpeningHours(
            open_time=time(11, 0),
            close_time=time(17, 0),
        ),
    }

    solver = VrptwSolverService()
    solution = solver.solve(
        start_node=start,
        place_nodes=place_nodes,
        places=places,
        saved_rows=saved_rows,
        matrix=matrix,
        trip_days=1,
        start_date=date(2026, 9, 3),
        opening_hours_map=opening_map,
    )

    assert len(solution.optimized_places) == 2
    museum_stop = next(s for s in solution.optimized_places if s.name == "Late Museum")
    assert museum_stop.planned_arrival_time is not None
    # Arrival must be at or after 11:00
    assert museum_stop.planned_arrival_time >= time(11, 0)
    assert museum_stop.is_opening_hours_known is True


def test_vrptw_respects_closed_day_of_week() -> None:
    """A place closed on Thursday must be scheduled on Friday in a 2-day trip."""
    # 2026-09-03 is a Thursday (weekday 3)
    start_date = date(2026, 9, 3)
    start = RouteNode(
        key="start",
        location_type="arrival",
        name="Hotel",
        latitude=23.17,
        longitude=75.78,
    )
    p1 = Place(
        id=uuid4(),
        city_id=uuid4(),
        name="Thursday-Closed Gallery",
        category="museum",
        latitude=23.18,
        longitude=75.78,
    )
    p2 = Place(
        id=uuid4(),
        city_id=uuid4(),
        name="Open Park",
        category="park",
        latitude=23.19,
        longitude=75.78,
    )
    places = [p1, p2]
    place_nodes = [_make_node(p.name, p.latitude, p.longitude, p.id) for p in places]
    saved_rows = [
        UserSavedPlace(trip_id=uuid4(), place_id=p1.id),
        UserSavedPlace(trip_id=uuid4(), place_id=p2.id),
    ]

    matrix = {
        (start.key, place_nodes[0].key): _make_leg(600, 5000),
        (start.key, place_nodes[1].key): _make_leg(600, 5000),
        (place_nodes[0].key, place_nodes[1].key): _make_leg(600, 5000),
        (place_nodes[1].key, place_nodes[0].key): _make_leg(600, 5000),
    }

    # Gallery closed on Thursday (weekday 3)
    opening_map = {
        p1.id: PlaceOpeningHours(
            open_time=time(10, 0),
            close_time=time(18, 0),
            closed_days=(3,),  # Thursday
        ),
    }

    solver = VrptwSolverService()
    solution = solver.solve(
        start_node=start,
        place_nodes=place_nodes,
        places=places,
        saved_rows=saved_rows,
        matrix=matrix,
        trip_days=2,
        start_date=start_date,
        opening_hours_map=opening_map,
    )

    gallery_stop = next(s for s in solution.optimized_places if s.name == "Thursday-Closed Gallery")
    # Day 1 is Thursday, Day 2 is Friday. Gallery must be visited on Day 2!
    assert gallery_stop.day_number == 2


# ---------------------------------------------------------------------------
# 2. Visit Durations & Service Times Tests
# ---------------------------------------------------------------------------


def test_vrptw_visit_durations_affect_timetables() -> None:
    """Visit duration determines departure time = arrival + duration."""
    start = RouteNode(
        key="start",
        location_type="arrival",
        name="Hotel",
        latitude=23.17,
        longitude=75.78,
    )
    p1 = Place(
        id=uuid4(),
        city_id=uuid4(),
        name="Heritage Fort",
        category="heritage",  # 120 min duration
        latitude=23.18,
        longitude=75.78,
    )
    places = [p1]
    place_nodes = [_make_node(p1.name, p1.latitude, p1.longitude, p1.id)]
    saved_rows = [UserSavedPlace(trip_id=uuid4(), place_id=p1.id)]

    matrix = {
        (start.key, place_nodes[0].key): _make_leg(600, 5000),
    }

    solver = VrptwSolverService()
    solution = solver.solve(
        start_node=start,
        place_nodes=place_nodes,
        places=places,
        saved_rows=saved_rows,
        matrix=matrix,
        trip_days=1,
    )

    assert len(solution.optimized_places) == 1
    stop = solution.optimized_places[0]
    assert stop.visit_duration_minutes == 120
    assert stop.planned_arrival_time is not None
    assert stop.planned_departure_time is not None

    arr_m = stop.planned_arrival_time.hour * 60 + stop.planned_arrival_time.minute
    dep_m = stop.planned_departure_time.hour * 60 + stop.planned_departure_time.minute
    assert dep_m - arr_m == 120


# ---------------------------------------------------------------------------
# 3. Lunch Break Scheduling Tests
# ---------------------------------------------------------------------------


def test_vrptw_schedules_midday_lunch_break() -> None:
    """Active touring days include a midday break card between 12:30 and 14:00."""
    start = RouteNode(
        key="start",
        location_type="arrival",
        name="Hotel",
        latitude=23.17,
        longitude=75.78,
    )
    p1 = Place(
        id=uuid4(),
        city_id=uuid4(),
        name="Morning Museum",
        category="museum",  # 120 min
        latitude=23.18,
        longitude=75.78,
    )
    p2 = Place(
        id=uuid4(),
        city_id=uuid4(),
        name="Afternoon Garden",
        category="park",  # 60 min
        latitude=23.19,
        longitude=75.78,
    )
    places = [p1, p2]
    place_nodes = [_make_node(p.name, p.latitude, p.longitude, p.id) for p in places]
    saved_rows = [
        UserSavedPlace(trip_id=uuid4(), place_id=p1.id),
        UserSavedPlace(trip_id=uuid4(), place_id=p2.id),
    ]

    matrix = {
        (start.key, place_nodes[0].key): _make_leg(600, 5000),
        (start.key, place_nodes[1].key): _make_leg(600, 5000),
        (place_nodes[0].key, place_nodes[1].key): _make_leg(600, 5000),
        (place_nodes[1].key, place_nodes[0].key): _make_leg(600, 5000),
    }

    solver = VrptwSolverService()
    solution = solver.solve(
        start_node=start,
        place_nodes=place_nodes,
        places=places,
        saved_rows=saved_rows,
        matrix=matrix,
        trip_days=1,
    )

    assert len(solution.breaks) >= 1
    lunch = solution.breaks[0]
    assert lunch.day_number == 1
    assert lunch.duration_minutes == 60
    assert time(12, 30) <= lunch.start_time <= time(14, 0)
    assert lunch.label == "Midday Break / Lunch"


# ---------------------------------------------------------------------------
# 4. Locked Places & Order Tests
# ---------------------------------------------------------------------------


def test_vrptw_enforces_locked_places_order() -> None:
    """A locked place with custom_order=1 is visited first regardless of distance."""
    start = RouteNode(
        key="start",
        location_type="arrival",
        name="Hotel",
        latitude=23.17,
        longitude=75.78,
    )
    p_far_locked = Place(
        id=uuid4(),
        city_id=uuid4(),
        name="Far Locked Temple",
        category="religious",
        latitude=23.30,
        longitude=75.78,
    )
    p_near = Place(
        id=uuid4(),
        city_id=uuid4(),
        name="Close Market",
        category="market",
        latitude=23.18,
        longitude=75.78,
    )
    places = [p_far_locked, p_near]
    place_nodes = [_make_node(p.name, p.latitude, p.longitude, p.id) for p in places]
    saved_rows = [
        UserSavedPlace(trip_id=uuid4(), place_id=p_far_locked.id, is_locked=True, custom_order=1),
        UserSavedPlace(trip_id=uuid4(), place_id=p_near.id, is_locked=False),
    ]

    matrix = {
        (start.key, place_nodes[0].key): _make_leg(1800, 15000),  # Far
        (start.key, place_nodes[1].key): _make_leg(300, 1000),    # Near
        (place_nodes[0].key, place_nodes[1].key): _make_leg(1800, 15000),
        (place_nodes[1].key, place_nodes[0].key): _make_leg(1800, 15000),
    }

    solver = VrptwSolverService()
    solution = solver.solve(
        start_node=start,
        place_nodes=place_nodes,
        places=places,
        saved_rows=saved_rows,
        matrix=matrix,
        trip_days=1,
    )

    assert [p.name for p in solution.optimized_places] == ["Far Locked Temple", "Close Market"]


# ---------------------------------------------------------------------------
# 5. Priorities and Must-Visit Rules Tests
# ---------------------------------------------------------------------------


def test_vrptw_preserves_must_visit_and_drops_low_priority_under_budget() -> None:
    """When daily time budget is exceeded, must-visit is kept and lowest priority is dropped."""
    start = RouteNode(
        key="start",
        location_type="arrival",
        name="Hotel",
        latitude=23.17,
        longitude=75.78,
    )
    p_must = Place(
        id=uuid4(),
        city_id=uuid4(),
        name="Must Visit Landmark",
        category="heritage",  # 120 min
        latitude=23.18,
        longitude=75.78,
    )
    p_high = Place(
        id=uuid4(),
        city_id=uuid4(),
        name="High Priority Museum",
        category="museum",  # 120 min
        latitude=23.19,
        longitude=75.78,
    )
    p_low = Place(
        id=uuid4(),
        city_id=uuid4(),
        name="Low Priority Shop",
        category="shopping",  # 60 min
        latitude=23.20,
        longitude=75.78,
    )
    places = [p_must, p_high, p_low]
    place_nodes = [_make_node(p.name, p.latitude, p.longitude, p.id) for p in places]
    saved_rows = [
        UserSavedPlace(trip_id=uuid4(), place_id=p_must.id, must_visit=True, priority=10),
        UserSavedPlace(trip_id=uuid4(), place_id=p_high.id, must_visit=False, priority=8),
        UserSavedPlace(trip_id=uuid4(), place_id=p_low.id, must_visit=False, priority=1),
    ]

    # Travel times are long so that 3 places cannot fit within 1 day (600 min budget)
    # Travel: 120 min each leg.
    # Total for 3 places: 120 (travel) + 120 (must) + 120 (travel) + 120 (high) + 120 (travel) + 60 (low) = 660 > 600 min!
    # But 2 places can fit: 120 + 120 + 120 + 120 = 480 min <= 600 min.
    matrix = {}
    nodes = [start, *place_nodes]
    for n1 in nodes:
        for n2 in nodes:
            if n1 != n2:
                matrix[(n1.key, n2.key)] = _make_leg(120 * 60, 10000)

    solver = VrptwSolverService()
    solution = solver.solve(
        start_node=start,
        place_nodes=place_nodes,
        places=places,
        saved_rows=saved_rows,
        matrix=matrix,
        trip_days=1,
    )

    visited_names = [p.name for p in solution.optimized_places]
    assert "Must Visit Landmark" in visited_names
    assert "High Priority Museum" in visited_names
    assert "Low Priority Shop" not in visited_names
    assert p_low.id in solution.unvisited_place_ids


# ---------------------------------------------------------------------------
# 6. Full Endpoint & Route Geometry Integration Test
# ---------------------------------------------------------------------------


def test_optimize_route_endpoint_attaches_geometry(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """POST /trips/{trip_id}/optimize-route generates timetable and attaches road route geometry."""
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)

    def override_session():
        with Session(engine) as session:
            yield session

    fake_geometry = FakeGeometryProvider()
    app.dependency_overrides[get_session] = override_session
    app.dependency_overrides[get_route_geometry_provider] = lambda: fake_geometry

    client = TestClient(app)

    try:
        # Create city, places, and trip
        city_res = client.post(
            "/cities",
            json={
                "name": "Jaipur",
                "state": "Rajasthan",
                "country": "India",
                "latitude": 26.9124,
                "longitude": 75.7873,
            },
        )
        assert city_res.status_code == 201
        city_id = city_res.json()["id"]

        p1_res = client.post(
            "/places",
            json={
                "city_id": city_id,
                "name": "Hawa Mahal",
                "category": "heritage",
                "latitude": 26.9239,
                "longitude": 75.8267,
            },
        )
        p2_res = client.post(
            "/places",
            json={
                "city_id": city_id,
                "name": "City Palace",
                "category": "heritage",
                "latitude": 26.9258,
                "longitude": 75.8237,
            },
        )
        assert p1_res.status_code == 201
        assert p2_res.status_code == 201

        with Session(engine) as session:
            trip = Trip(
                user_id=uuid4(),
                city_id=UUID(city_id),
                trip_name="Jaipur Highlights",
                days=1,
                start_location_type="hotel",
                start_location_name="Jaipur Hotel",
                start_latitude=26.9150,
                start_longitude=75.8000,
            )
            session.add(trip)
            session.flush()

            session.add(UserSavedPlace(trip_id=trip.id, place_id=UUID(p1_res.json()["id"])))
            session.add(UserSavedPlace(trip_id=trip.id, place_id=UUID(p2_res.json()["id"])))
            session.commit()
            trip_id = trip.id

        response = client.post(f"/trips/{trip_id}/optimize-route")
        assert response.status_code == 200
        data = response.json()

        assert data["trip_id"] == str(trip_id)
        assert len(data["optimized_places"]) == 2
        assert len(data["breaks"]) >= 1
        assert data["route_geometry"] is not None
        assert "days" in data["route_geometry"]
        assert len(data["route_geometry"]["days"]) == 1
        assert len(data["route_geometry"]["days"][0]["coordinates"]) > 0

    finally:
        client.close()
        app.dependency_overrides.clear()
        SQLModel.metadata.drop_all(engine)
