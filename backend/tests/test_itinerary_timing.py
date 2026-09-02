"""Comprehensive test suite for time-aware itinerary scheduling and opening-hours awareness."""

from datetime import date, time
from uuid import uuid4

from fastapi.testclient import TestClient
import pytest
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.core.itinerary_constants import (
    DEFAULT_DAY_START_TIME,
    estimate_visit_duration,
)
from app.database import get_session
from app.main import app


@pytest.fixture
def session_and_client():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)

    with Session(engine) as session:
        def override_get_session():
            yield session

        app.dependency_overrides[get_session] = override_get_session
        with TestClient(app) as client:
            yield session, client

    app.dependency_overrides.clear()

from app.models.entities import City, Place, Trip, TripItinerary, UserSavedPlace
from app.services.google_routes_service import RouteMatrixLeg
from app.services.itinerary_timing_service import (
    ItineraryTimingService,
    PlaceOpeningHours,
)
from app.services.route_matrix_service import RouteNode


def _make_node(key: str, lat: float, lon: float) -> RouteNode:
    return RouteNode(
        key=key,
        location_type="place",
        name=key,
        latitude=lat,
        longitude=lon,
        place_id=uuid4(),
    )


def _make_leg(duration_seconds: int, distance_meters: int) -> RouteMatrixLeg:
    return RouteMatrixLeg(
        distance_meters=distance_meters,
        static_duration_seconds=duration_seconds,
    )


def test_category_visit_duration_estimates():
    """Verify deterministic category heuristics map to expected tourist visit durations."""
    assert estimate_visit_duration("fort") == 120
    assert estimate_visit_duration("palace") == 120
    assert estimate_visit_duration("museum") == 90
    assert estimate_visit_duration("park") == 60
    assert estimate_visit_duration("temple") == 45
    assert estimate_visit_duration("religious") == 45
    assert estimate_visit_duration("monument") == 45
    assert estimate_visit_duration("cafe") == 45
    assert estimate_visit_duration("unknown_category") == 75


def test_one_day_itinerary_timing_and_travel_insertion():
    """Verify that a 1-day itinerary computes sequential times with travel gaps."""
    service = ItineraryTimingService()
    start_node = _make_node("start", 26.91, 75.78)

    p1_id = uuid4()
    p2_id = uuid4()
    place1 = Place(id=p1_id, city_id=uuid4(), name="Hawa Mahal", category="monument", latitude=26.92, longitude=75.82)
    place2 = Place(id=p2_id, city_id=uuid4(), name="City Palace", category="palace", latitude=26.92, longitude=75.83)
    places = [place1, place2]

    node1 = RouteNode("p1", "place", place1.name, place1.latitude, place1.longitude, p1_id)
    node2 = RouteNode("p2", "place", place2.name, place2.latitude, place2.longitude, p2_id)
    place_nodes = [node1, node2]

    saved_rows = [
        UserSavedPlace(trip_id=uuid4(), place_id=p1_id, priority=0, must_visit=True),
        UserSavedPlace(trip_id=uuid4(), place_id=p2_id, priority=0, must_visit=True),
    ]

    # Travel: start -> p1 is 15 min, p1 -> p2 is 10 min
    matrix = {
        (start_node.key, node1.key): _make_leg(15 * 60, 5000),
        (node1.key, node2.key): _make_leg(10 * 60, 3000),
    }

    result = service.schedule_itinerary(
        start_node=start_node,
        place_nodes=place_nodes,
        places=places,
        saved_rows=saved_rows,
        ordered_indices=[0, 1],
        matrix=matrix,
        trip_days=1,
        start_date=date(2026, 9, 10),
    )

    assert len(result.optimized_places) == 2
    # Place 1 (monument: 45 min): start at 09:00, arrival 09:15, departs 10:00
    stop1 = result.optimized_places[0]
    assert stop1.day_number == 1
    assert stop1.visit_order == 1
    assert stop1.travel_time_minutes == 15
    assert stop1.planned_arrival_time == time(9, 15)
    assert stop1.planned_departure_time == time(10, 0)
    assert stop1.visit_duration_minutes == 45

    # Place 2 (palace: 120 min): departs p1 at 10:00, 10 min travel -> arrival 10:10, departs 12:10
    stop2 = result.optimized_places[1]
    assert stop2.day_number == 1
    assert stop2.visit_order == 2
    assert stop2.travel_time_minutes == 10
    assert stop2.planned_arrival_time == time(10, 10)
    assert stop2.planned_departure_time == time(12, 10)
    assert stop2.visit_duration_minutes == 120


def test_lunch_break_insertion():
    """Verify that a midday lunch break is scheduled when touring crosses 12:30-14:00."""
    service = ItineraryTimingService()
    start_node = _make_node("start", 26.91, 75.78)

    p1_id, p2_id, p3_id = uuid4(), uuid4(), uuid4()
    place1 = Place(id=p1_id, city_id=uuid4(), name="Amer Fort", category="fort", latitude=26.98, longitude=75.85)  # 120 min
    place2 = Place(id=p2_id, city_id=uuid4(), name="Jaigarh Fort", category="fort", latitude=26.98, longitude=75.84) # 120 min
    place3 = Place(id=p3_id, city_id=uuid4(), name="Albert Hall", category="museum", latitude=26.91, longitude=75.81) # 90 min
    places = [place1, place2, place3]

    node1 = RouteNode("p1", "place", place1.name, place1.latitude, place1.longitude, p1_id)
    node2 = RouteNode("p2", "place", place2.name, place2.latitude, place2.longitude, p2_id)
    node3 = RouteNode("p3", "place", place3.name, place3.latitude, place3.longitude, p3_id)
    place_nodes = [node1, node2, node3]

    saved_rows = [
        UserSavedPlace(trip_id=uuid4(), place_id=p1_id),
        UserSavedPlace(trip_id=uuid4(), place_id=p2_id),
        UserSavedPlace(trip_id=uuid4(), place_id=p3_id),
    ]

    matrix = {
        (start_node.key, node1.key): _make_leg(30 * 60, 10000),  # arrival 09:30, depart 11:30
        (node1.key, node2.key): _make_leg(15 * 60, 4000),        # arrival 11:45, depart 13:45 -> crosses midday!
        (node2.key, node3.key): _make_leg(20 * 60, 8000),
    }

    result = service.schedule_itinerary(
        start_node=start_node,
        place_nodes=place_nodes,
        places=places,
        saved_rows=saved_rows,
        ordered_indices=[0, 1, 2],
        matrix=matrix,
        trip_days=1,
    )

    # A lunch break should have been inserted after stop 2 (at 13:45 to 14:45)
    assert len(result.breaks) == 1
    break_item = result.breaks[0]
    assert break_item.day_number == 1
    assert break_item.duration_minutes == 60
    assert break_item.start_time == time(13, 45)
    assert break_item.end_time == time(14, 45)

    # Stop 3 should start after the lunch break + travel time (14:45 + 20m = 15:05)
    stop3 = result.optimized_places[2]
    assert stop3.planned_arrival_time == time(15, 5)


def test_opening_hours_delayed_start():
    """Verify that when a place opens later (e.g. 10:00 AM), arrival is delayed to opening time."""
    service = ItineraryTimingService()
    start_node = _make_node("start", 26.91, 75.78)

    p1_id = uuid4()
    place1 = Place(id=p1_id, city_id=uuid4(), name="Museum", category="museum", latitude=26.92, longitude=75.82)
    node1 = RouteNode("p1", "place", place1.name, place1.latitude, place1.longitude, p1_id)

    matrix = {
        (start_node.key, node1.key): _make_leg(15 * 60, 5000),  # would arrive at 09:15
    }
    # Known opening hours: 10:00 AM to 05:00 PM
    opening_hours_map = {
        p1_id: PlaceOpeningHours(open_time=time(10, 0), close_time=time(17, 0)),
    }

    result = service.schedule_itinerary(
        start_node=start_node,
        place_nodes=[node1],
        places=[place1],
        saved_rows=[UserSavedPlace(trip_id=uuid4(), place_id=p1_id)],
        ordered_indices=[0],
        matrix=matrix,
        trip_days=1,
        opening_hours_map=opening_hours_map,
    )

    stop = result.optimized_places[0]
    # Arrival should be delayed to 10:00 AM
    assert stop.planned_arrival_time == time(10, 0)
    assert stop.planned_departure_time == time(11, 30)
    assert stop.is_opening_hours_known is True
    assert len(result.conflicts) == 0


def test_opening_hours_closing_conflict():
    """Verify that when a place closes too early, a conflict is emitted without dropping the place."""
    service = ItineraryTimingService()
    start_node = _make_node("start", 26.91, 75.78)

    p1_id = uuid4()
    place1 = Place(id=p1_id, city_id=uuid4(), name="Quick Museum", category="museum", latitude=26.92, longitude=75.82)
    node1 = RouteNode("p1", "place", place1.name, place1.latitude, place1.longitude, p1_id)

    matrix = {
        (start_node.key, node1.key): _make_leg(15 * 60, 5000),  # arrives 09:15, 90 min visit -> departs 10:45
    }
    # Closes at 10:00 AM (too early for 90 min visit)
    opening_hours_map = {
        p1_id: PlaceOpeningHours(open_time=time(9, 0), close_time=time(10, 0)),
    }

    result = service.schedule_itinerary(
        start_node=start_node,
        place_nodes=[node1],
        places=[place1],
        saved_rows=[UserSavedPlace(trip_id=uuid4(), place_id=p1_id)],
        ordered_indices=[0],
        matrix=matrix,
        trip_days=1,
        opening_hours_map=opening_hours_map,
    )

    assert len(result.optimized_places) == 1
    assert len(result.conflicts) == 1
    assert "closes at 10:00 AM" in result.conflicts[0]


def test_multi_day_timing_and_overflow():
    """Verify multi-day schedule partitioning when stops exceed day budget."""
    service = ItineraryTimingService()
    start_node = _make_node("start", 26.91, 75.78)

    places = []
    nodes = []
    saved = []
    matrix = {}

    # 4 major forts/palaces (120 min each + 30 min travel each)
    for i in range(4):
        pid = uuid4()
        p = Place(id=pid, city_id=uuid4(), name=f"Fort {i+1}", category="fort", latitude=26.9 + i*0.01, longitude=75.8)
        places.append(p)
        n = RouteNode(f"p{i}", "place", p.name, p.latitude, p.longitude, pid)
        nodes.append(n)
        saved.append(UserSavedPlace(trip_id=uuid4(), place_id=pid))
        matrix[(start_node.key, n.key)] = _make_leg(30 * 60, 8000)
        for j in range(4):
            if i != j:
                matrix[(f"p{i}", f"p{j}")] = _make_leg(30 * 60, 8000)

    result = service.schedule_itinerary(
        start_node=start_node,
        place_nodes=nodes,
        places=places,
        saved_rows=saved,
        ordered_indices=[0, 1, 2, 3],
        matrix=matrix,
        trip_days=2,
    )

    day1_stops = [p for p in result.optimized_places if p.day_number == 1]
    day2_stops = [p for p in result.optimized_places if p.day_number == 2]

    # Forts (120 min) + lunch (60 min) + travel (30 min) will partition across 2 days
    assert len(day1_stops) >= 1
    assert len(day2_stops) >= 1
    assert len(day1_stops) + len(day2_stops) == 4


def test_must_visit_preservation_raises_on_infeasible_trip():
    """Verify that must_visit places are never silently dropped; raises ValueError on impossible trip."""
    service = ItineraryTimingService()
    start_node = _make_node("start", 26.91, 75.78)

    # 5 massive attractions with 300 min travel time on a 1-day trip
    places = []
    nodes = []
    saved = []
    matrix = {}

    for i in range(5):
        pid = uuid4()
        p = Place(id=pid, city_id=uuid4(), name=f"Huge Site {i}", category="fort", latitude=26.9 + i*0.01, longitude=75.8)
        places.append(p)
        n = RouteNode(f"p{i}", "place", p.name, p.latitude, p.longitude, pid)
        nodes.append(n)
        saved.append(UserSavedPlace(trip_id=uuid4(), place_id=pid, must_visit=True))
        matrix[(start_node.key, n.key)] = _make_leg(300 * 60, 50000)
        for j in range(5):
            if i != j:
                matrix[(f"p{i}", f"p{j}")] = _make_leg(300 * 60, 50000)

    with pytest.raises(ValueError, match="Cannot fit all must-visit places within the trip duration."):
        service.schedule_itinerary(
            start_node=start_node,
            place_nodes=nodes,
            places=places,
            saved_rows=saved,
            ordered_indices=[0, 1, 2, 3, 4],
            matrix=matrix,
            trip_days=1,
        )


def test_deterministic_scheduling_output():
    """Verify that repeated scheduling calls produce identical output."""
    service = ItineraryTimingService()
    start_node = _make_node("start", 26.91, 75.78)

    p1_id, p2_id = uuid4(), uuid4()
    p1 = Place(id=p1_id, city_id=uuid4(), name="Amer", category="fort", latitude=26.98, longitude=75.85)
    p2 = Place(id=p2_id, city_id=uuid4(), name="Hawa", category="monument", latitude=26.92, longitude=75.82)
    n1 = RouteNode("p1", "place", p1.name, p1.latitude, p1.longitude, p1_id)
    n2 = RouteNode("p2", "place", p2.name, p2.latitude, p2.longitude, p2_id)

    matrix = {
        (start_node.key, n1.key): _make_leg(20 * 60, 6000),
        (n1.key, n2.key): _make_leg(15 * 60, 4000),
    }
    saved = [UserSavedPlace(trip_id=uuid4(), place_id=p1_id), UserSavedPlace(trip_id=uuid4(), place_id=p2_id)]

    run1 = service.schedule_itinerary(start_node, [n1, n2], [p1, p2], saved, [0, 1], matrix, trip_days=1)
    run2 = service.schedule_itinerary(start_node, [n1, n2], [p1, p2], saved, [0, 1], matrix, trip_days=1)

    assert len(run1.optimized_places) == len(run2.optimized_places)
    for s1, s2 in zip(run1.optimized_places, run2.optimized_places):
        assert s1.planned_arrival_time == s2.planned_arrival_time
        assert s1.planned_departure_time == s2.planned_departure_time
        assert s1.visit_duration_minutes == s2.visit_duration_minutes


def test_locked_places_order_preserved():
    """Verify that locked places preserve custom_order position in the schedule."""
    from app.services.route_optimization_service import RouteOptimizationService

    start_node = _make_node("start", 26.91, 75.78)
    p1_id, p2_id, p3_id = uuid4(), uuid4(), uuid4()

    place_nodes = [
        RouteNode("p1", "place", "Place 1", 26.91, 75.79, p1_id),
        RouteNode("p2", "place", "Place 2", 26.92, 75.80, p2_id),
        RouteNode("p3", "place", "Place 3", 26.93, 75.81, p3_id),
    ]
    # Place 3 is locked to position 1
    saved_rows = [
        UserSavedPlace(trip_id=uuid4(), place_id=p1_id, custom_order=None, is_locked=False),
        UserSavedPlace(trip_id=uuid4(), place_id=p2_id, custom_order=None, is_locked=False),
        UserSavedPlace(trip_id=uuid4(), place_id=p3_id, custom_order=1, is_locked=True),
    ]
    matrix = {
        (start_node.key, "p1"): _make_leg(10 * 60, 3000),
        (start_node.key, "p2"): _make_leg(10 * 60, 3000),
        (start_node.key, "p3"): _make_leg(10 * 60, 3000),
        ("p1", "p2"): _make_leg(10 * 60, 3000),
        ("p2", "p1"): _make_leg(10 * 60, 3000),
        ("p1", "p3"): _make_leg(10 * 60, 3000),
        ("p3", "p1"): _make_leg(10 * 60, 3000),
        ("p2", "p3"): _make_leg(10 * 60, 3000),
        ("p3", "p2"): _make_leg(10 * 60, 3000),
    }

    order = RouteOptimizationService._constraint_aware_order(start_node, place_nodes, matrix, saved_rows)
    # The first element must be index 2 (Place 3, which is locked to slot 1)
    assert order[0] == 2


def test_transactional_regeneration_updates_itinerary(session_and_client):
    """Verify that re-optimizing a trip regenerates times transactionally without duplicate rows."""
    session, client = session_and_client
    city = City(id=uuid4(), name="Jaipur", country="India", latitude=26.9124, longitude=75.7873)
    session.add(city)
    trip = Trip(
        id=uuid4(),
        city_id=city.id,
        user_id=uuid4(),
        trip_name="Jaipur Trip",
        start_date=date(2026, 9, 15),
        days=1,
        arrival_place="Jaipur Station",
        arrival_latitude=26.9124,
        arrival_longitude=75.7873,
        start_location_type="arrival",
        start_location_name="Jaipur Station",
        start_latitude=26.9124,
        start_longitude=75.7873,
    )
    session.add(trip)

    p1 = Place(id=uuid4(), city_id=city.id, name="Hawa Mahal", category="monument", latitude=26.9239, longitude=75.8267)
    p2 = Place(id=uuid4(), city_id=city.id, name="City Palace", category="palace", latitude=26.9258, longitude=75.8237)
    session.add(p1)
    session.add(p2)
    session.add(UserSavedPlace(trip_id=trip.id, place_id=p1.id, priority=0))
    session.add(UserSavedPlace(trip_id=trip.id, place_id=p2.id, priority=0))
    session.commit()

    resp = client.post(f"/trips/{trip.id}/optimize-route")
    assert resp.status_code == 200
    data = resp.json()

    assert len(data["optimized_places"]) == 2
    for p in data["optimized_places"]:
        assert p["planned_arrival_time"] is not None
        assert p["planned_departure_time"] is not None
        assert p["visit_duration_minutes"] > 0

    # Verify rows in database
    rows = session.exec(select(TripItinerary).where(TripItinerary.trip_id == trip.id)).all()
    assert len(rows) == 2
    for r in rows:
        assert r.planned_arrival_time is not None
        assert r.planned_departure_time is not None

    # Re-optimize (simulate regeneration)
    resp2 = client.post(f"/trips/{trip.id}/optimize-route")
    assert resp2.status_code == 200
    rows_after = session.exec(select(TripItinerary).where(TripItinerary.trip_id == trip.id)).all()
    # Verified no duplicate rows created
    assert len(rows_after) == 2

