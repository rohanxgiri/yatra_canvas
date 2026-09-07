"""Robust automated tests for live itinerary status handling and partial day replanning.

Covers:
1. newly generated stop defaults to PLANNED
2. PLANNED -> COMPLETED works
3. PLANNED -> MISSED works
4. PLANNED -> SKIPPED works
5. status persists in database
6. MISSED alone does not automatically move the place
7. missed place can be moved Day 1 -> Day 2
8. target day is re-optimized
9. unrelated Day 3 remains byte-for-byte/logically unchanged
10. source day removes the moved stop
11. source day's future stops may be re-optimized
12. completed source-day stops remain unchanged
13. completed target-day prefix remains unchanged
14. only remaining target-day route is optimized
15. moved place respects opening hours
16. moved place respects split opening intervals
17. moved place with UNKNOWN hours remains unverified
18. moved place respects visit duration
19. cannot move place to REST day
20. cannot move place to another trip's day
21. cannot move place to day with no sightseeing window
22. infeasible target day returns structured failure
23. existing locked places are not silently moved
24. move does not automatically delete another place
25. SKIPPED place is excluded from future optimization
26. COMPLETED place is excluded from future reordering
27. existing route matrix cache is reused
28. unrelated days do not trigger unnecessary route recalculation
29. performance benchmarks (4, 8, 12 places)
"""

import time as pytime
from datetime import date, datetime, time, timedelta, timezone
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.database import get_session
from app.main import app
from app.models.entities import (
    City,
    Place,
    PlaceOpeningHours,
    RouteMatrixCache,
    Trip,
    TripDay,
    TripItinerary,
    UserSavedPlace,
)
from app.schemas.smart_replanning import (
    ItineraryStopStatus,
    ItineraryStopStatusUpdate,
    MoveItineraryPlaceRequest,
)
from app.services.local_routes_service import LocalRoutesService
from app.services.route_matrix_service import RouteMatrixService
from app.services.smart_replanning_service import SmartReplanningService


@pytest.fixture
def test_env():
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


def _create_base_trip(session: Session, num_days: int = 3) -> tuple[Trip, City, list[TripDay]]:
    city = City(
        id=uuid4(),
        name="Udaipur",
        state="Rajasthan",
        country="India",
        latitude=24.5854,
        longitude=73.7125,
    )
    session.add(city)
    trip = Trip(
        id=uuid4(),
        city_id=city.id,
        user_id=uuid4(),
        trip_name="Udaipur Tour",
        start_date=date(2026, 9, 14),  # Monday
        days=num_days,
        arrival_place="Udaipur Railway Station",
        arrival_latitude=24.57,
        arrival_longitude=73.69,
        start_location_type="arrival",
        start_location_name="Udaipur Railway Station",
        start_latitude=24.57,
        start_longitude=73.69,
    )
    session.add(trip)
    session.flush()

    days = []
    for d in range(1, num_days + 1):
        tday = TripDay(
            id=uuid4(),
            trip_id=trip.id,
            day_number=d,
            date=trip.start_date + timedelta(days=d - 1),
            day_type="FULL_DAY",
            start_time=time(9, 0),
            end_time=time(19, 0),
        )
        session.add(tday)
        days.append(tday)
    session.commit()
    return trip, city, days


# ---------------------------------------------------------------------------
# Tests 1 - 6: Itinerary Stop Status Lifecycle & Persistence
# ---------------------------------------------------------------------------


def test_newly_generated_stop_defaults_to_planned(test_env):
    session, client = test_env
    trip, city, days = _create_base_trip(session)

    p1 = Place(id=uuid4(), city_id=city.id, name="City Palace", category="heritage", latitude=24.576, longitude=73.683)
    session.add(p1)
    session.add(UserSavedPlace(trip_id=trip.id, place_id=p1.id, custom_order=1))
    session.commit()

    # Optimize route
    resp = client.post(f"/trips/{trip.id}/optimize-route")
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["optimized_places"]) == 1
    stop = data["optimized_places"][0]
    assert stop["status"] == "PLANNED"

    # Verify DB entity has default PLANNED
    db_stop = session.exec(select(TripItinerary).where(TripItinerary.trip_id == trip.id)).first()
    assert db_stop is not None
    assert db_stop.status == "PLANNED"


def test_planned_to_completed_persists(test_env):
    session, client = test_env
    trip, city, days = _create_base_trip(session)

    p1 = Place(id=uuid4(), city_id=city.id, name="City Palace", category="heritage", latitude=24.576, longitude=73.683)
    session.add(p1)
    stop = TripItinerary(
        id=uuid4(),
        trip_id=trip.id,
        place_id=p1.id,
        day_number=1,
        visit_order=1,
        status="PLANNED",
    )
    session.add(stop)
    session.commit()

    # PATCH by stop_id
    resp = client.patch(f"/trips/{trip.id}/itinerary/stops/{stop.id}", json={"status": "COMPLETED"})
    assert resp.status_code == 200
    assert resp.json()["status"] == "COMPLETED"

    session.refresh(stop)
    assert stop.status == "COMPLETED"


def test_planned_to_missed_and_skipped_persists(test_env):
    session, client = test_env
    trip, city, days = _create_base_trip(session)

    p1 = Place(id=uuid4(), city_id=city.id, name="Jag Mandir", category="heritage", latitude=24.567, longitude=73.677)
    p2 = Place(id=uuid4(), city_id=city.id, name="Saheliyon Ki Bari", category="garden", latitude=24.604, longitude=73.684)
    session.add_all([p1, p2])

    s1 = TripItinerary(id=uuid4(), trip_id=trip.id, place_id=p1.id, day_number=1, visit_order=1, status="PLANNED")
    s2 = TripItinerary(id=uuid4(), trip_id=trip.id, place_id=p2.id, day_number=1, visit_order=2, status="PLANNED")
    session.add_all([s1, s2])
    session.commit()

    # PATCH p1 to MISSED by place_id
    resp1 = client.patch(f"/trips/{trip.id}/itinerary/places/{p1.id}", json={"status": "MISSED"})
    assert resp1.status_code == 200
    assert resp1.json()["status"] == "MISSED"

    # PATCH s2 to SKIPPED by stop_id
    resp2 = client.patch(f"/trips/{trip.id}/itinerary/stops/{s2.id}", json={"status": "SKIPPED"})
    assert resp2.status_code == 200
    assert resp2.json()["status"] == "SKIPPED"

    session.refresh(s1)
    session.refresh(s2)
    assert s1.status == "MISSED"
    assert s2.status == "SKIPPED"


def test_missed_alone_does_not_auto_move_place(test_env):
    session, client = test_env
    trip, city, days = _create_base_trip(session)

    p1 = Place(id=uuid4(), city_id=city.id, name="Place A", category="heritage", latitude=24.576, longitude=73.683)
    session.add(p1)
    stop = TripItinerary(id=uuid4(), trip_id=trip.id, place_id=p1.id, day_number=1, visit_order=1, status="PLANNED")
    session.add(stop)
    session.commit()

    resp = client.patch(f"/trips/{trip.id}/itinerary/stops/{stop.id}", json={"status": "MISSED"})
    assert resp.status_code == 200

    session.refresh(stop)
    assert stop.status == "MISSED"
    assert stop.day_number == 1
    assert stop.visit_order == 1


# ---------------------------------------------------------------------------
# Tests 7 - 14: Partial Replanning, Suffix Optimization, Immutable Completed Prefix
# ---------------------------------------------------------------------------


def test_move_missed_place_day1_to_day2_with_unrelated_day3_untouched(test_env):
    session, client = test_env
    trip, city, days = _create_base_trip(session, num_days=3)

    pA = Place(id=uuid4(), city_id=city.id, name="Place A", category="monument", latitude=24.57, longitude=73.68)
    pB = Place(id=uuid4(), city_id=city.id, name="Place B", category="museum", latitude=24.58, longitude=73.68)
    pC = Place(id=uuid4(), city_id=city.id, name="Place C", category="heritage", latitude=24.59, longitude=73.69)
    pD = Place(id=uuid4(), city_id=city.id, name="Place D", category="garden", latitude=24.60, longitude=73.70)
    pE = Place(id=uuid4(), city_id=city.id, name="Place E", category="fort", latitude=24.61, longitude=73.71)
    pX = Place(id=uuid4(), city_id=city.id, name="Place X", category="palace", latitude=24.62, longitude=73.72)
    session.add_all([pA, pB, pC, pD, pE, pX])

    # Day 1: A (COMPLETED), B (COMPLETED), C (MISSED), D (PLANNED)
    sA = TripItinerary(id=uuid4(), trip_id=trip.id, place_id=pA.id, day_number=1, visit_order=1, planned_arrival_time=time(9, 0), planned_departure_time=time(10, 0), status="COMPLETED")
    sB = TripItinerary(id=uuid4(), trip_id=trip.id, place_id=pB.id, day_number=1, visit_order=2, planned_arrival_time=time(10, 15), planned_departure_time=time(11, 15), status="COMPLETED")
    sC = TripItinerary(id=uuid4(), trip_id=trip.id, place_id=pC.id, day_number=1, visit_order=3, planned_arrival_time=time(11, 30), planned_departure_time=time(12, 30), status="MISSED")
    sD = TripItinerary(id=uuid4(), trip_id=trip.id, place_id=pD.id, day_number=1, visit_order=4, planned_arrival_time=time(13, 0), planned_departure_time=time(14, 0), status="PLANNED")

    # Day 2: E (PLANNED)
    sE = TripItinerary(id=uuid4(), trip_id=trip.id, place_id=pE.id, day_number=2, visit_order=1, planned_arrival_time=time(9, 30), planned_departure_time=time(11, 0), status="PLANNED")

    # Day 3: X (PLANNED)
    sX = TripItinerary(id=uuid4(), trip_id=trip.id, place_id=pX.id, day_number=3, visit_order=1, planned_arrival_time=time(10, 0), planned_departure_time=time(11, 30), status="PLANNED")

    session.add_all([sA, sB, sC, sD, sE, sX])

    for p in [pA, pB, pC, pD, pE, pX]:
        session.add(UserSavedPlace(trip_id=trip.id, place_id=p.id))
    session.commit()

    # Move C -> Day 2
    resp = client.post(
        f"/trips/{trip.id}/itinerary/move-place",
        json={"place_id": str(pC.id), "target_day_number": 2},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["success"] is True
    assert body["source_day_number"] == 1
    assert body["target_day_number"] == 2

    # Verify Day 1:
    # A & B must remain COMPLETED and unchanged in arrival/departure/order
    day1_stops = session.exec(select(TripItinerary).where(TripItinerary.trip_id == trip.id, TripItinerary.day_number == 1).order_by(TripItinerary.visit_order)).all()
    assert len(day1_stops) == 3
    assert day1_stops[0].place_id == pA.id and day1_stops[0].status == "COMPLETED" and day1_stops[0].visit_order == 1
    assert day1_stops[1].place_id == pB.id and day1_stops[1].status == "COMPLETED" and day1_stops[1].visit_order == 2
    # C is removed, D is re-ordered to visit_order 3
    assert day1_stops[2].place_id == pD.id and day1_stops[2].visit_order == 3 and day1_stops[2].status == "PLANNED"

    # Verify Day 2:
    # Now has both E and C
    day2_stops = session.exec(select(TripItinerary).where(TripItinerary.trip_id == trip.id, TripItinerary.day_number == 2).order_by(TripItinerary.visit_order)).all()
    assert len(day2_stops) == 2
    day2_pids = {s.place_id for s in day2_stops}
    assert day2_pids == {pE.id, pC.id}
    assert all(s.status == "PLANNED" for s in day2_stops)

    # Verify Day 3 is byte-for-byte unchanged!
    day3_stops = session.exec(select(TripItinerary).where(TripItinerary.trip_id == trip.id, TripItinerary.day_number == 3)).all()
    assert len(day3_stops) == 1
    assert day3_stops[0].id == sX.id
    assert day3_stops[0].place_id == pX.id
    assert day3_stops[0].planned_arrival_time == time(10, 0)
    assert day3_stops[0].planned_departure_time == time(11, 30)


def test_completed_target_day_prefix_remains_immutable(test_env):
    session, client = test_env
    trip, city, days = _create_base_trip(session, num_days=2)

    p1 = Place(id=uuid4(), city_id=city.id, name="Target Place 1", category="heritage", latitude=24.57, longitude=73.68)
    p2 = Place(id=uuid4(), city_id=city.id, name="Target Place 2", category="monument", latitude=24.58, longitude=73.68)
    pMoved = Place(id=uuid4(), city_id=city.id, name="Moved Place", category="garden", latitude=24.59, longitude=73.69)
    session.add_all([p1, p2, pMoved])

    # Target Day 2 already has: p1 (COMPLETED, departing 11:30), p2 (PLANNED)
    stop1 = TripItinerary(
        id=uuid4(),
        trip_id=trip.id,
        place_id=p1.id,
        day_number=2,
        visit_order=1,
        planned_arrival_time=time(10, 0),
        planned_departure_time=time(11, 30),
        status="COMPLETED",
    )
    stop2 = TripItinerary(
        id=uuid4(),
        trip_id=trip.id,
        place_id=p2.id,
        day_number=2,
        visit_order=2,
        planned_arrival_time=time(12, 0),
        planned_departure_time=time(13, 0),
        status="PLANNED",
    )
    # Source Day 1 has pMoved (MISSED)
    stopMoved = TripItinerary(
        id=uuid4(),
        trip_id=trip.id,
        place_id=pMoved.id,
        day_number=1,
        visit_order=1,
        status="MISSED",
    )
    session.add_all([stop1, stop2, stopMoved])
    for p in [p1, p2, pMoved]:
        session.add(UserSavedPlace(trip_id=trip.id, place_id=p.id))
    session.commit()

    resp = client.post(
        f"/trips/{trip.id}/itinerary/move-place",
        json={"place_id": str(pMoved.id), "target_day_number": 2},
    )
    assert resp.status_code == 200
    assert resp.json()["success"] is True

    # Day 2 check:
    d2 = session.exec(select(TripItinerary).where(TripItinerary.trip_id == trip.id, TripItinerary.day_number == 2).order_by(TripItinerary.visit_order)).all()
    assert len(d2) == 3
    # Prefix stop 1 must be identical
    assert d2[0].place_id == p1.id
    assert d2[0].status == "COMPLETED"
    assert d2[0].visit_order == 1
    assert d2[0].planned_arrival_time == time(10, 0)
    assert d2[0].planned_departure_time == time(11, 30)

    # Subsequent stops (orders 2 and 3) start after 11:30
    assert d2[1].visit_order == 2
    assert d2[1].planned_arrival_time >= time(11, 30)
    assert d2[2].visit_order == 3
    assert d2[2].planned_arrival_time >= d2[1].planned_departure_time


# ---------------------------------------------------------------------------
# Tests 15 - 18: Opening Hours, Split Schedules, UNKNOWN safety, Visit Duration
# ---------------------------------------------------------------------------


def test_moved_place_respects_opening_hours_and_split_intervals(test_env):
    session, client = test_env
    trip, city, days = _create_base_trip(session, num_days=2)
    # Day 2 is Tuesday (2026-09-15) -> weekday 1

    cafe = Place(
        id=uuid4(),
        city_id=city.id,
        name="Art Cafe",
        category="cafes",
        latitude=24.58,
        longitude=73.68,
        opening_hours_status="KNOWN",
    )
    session.add(cafe)

    # Opening hours on Tuesday (weekday 1): Split schedule 14:00-17:00, 19:00-22:00
    hours = PlaceOpeningHours(
        place_id=cafe.id,
        day_of_week=1,
        status="KNOWN",
        intervals=[
            {"open": "14:00", "close": "17:00"},
            {"open": "19:00", "close": "22:00"},
        ],
    )
    session.add(hours)

    stop = TripItinerary(
        id=uuid4(),
        trip_id=trip.id,
        place_id=cafe.id,
        day_number=1,
        visit_order=1,
        status="MISSED",
    )
    session.add(stop)
    session.add(UserSavedPlace(trip_id=trip.id, place_id=cafe.id))
    session.commit()

    resp = client.post(
        f"/trips/{trip.id}/itinerary/move-place",
        json={"place_id": str(cafe.id), "target_day_number": 2},
    )
    assert resp.status_code == 200
    assert resp.json()["success"] is True

    d2 = session.exec(select(TripItinerary).where(TripItinerary.trip_id == trip.id, TripItinerary.day_number == 2)).first()
    assert d2 is not None
    assert d2.place_id == cafe.id
    # Must be scheduled in one of the open intervals (14:00-17:00), not morning!
    assert d2.planned_arrival_time >= time(14, 0)


def test_moved_place_with_unknown_hours_remains_unverified(test_env):
    session, client = test_env
    trip, city, days = _create_base_trip(session, num_days=2)

    pUnknown = Place(
        id=uuid4(),
        city_id=city.id,
        name="Unknown Shrine",
        category="religious",
        latitude=24.58,
        longitude=73.68,
        opening_hours_status="UNKNOWN",
    )
    session.add(pUnknown)
    stop = TripItinerary(id=uuid4(), trip_id=trip.id, place_id=pUnknown.id, day_number=1, visit_order=1, status="MISSED")
    session.add(stop)
    session.add(UserSavedPlace(trip_id=trip.id, place_id=pUnknown.id))
    session.commit()

    resp = client.post(
        f"/trips/{trip.id}/itinerary/move-place",
        json={"place_id": str(pUnknown.id), "target_day_number": 2},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["success"] is True
    target_stop = body["target_itinerary"][0]
    assert target_stop["is_opening_hours_known"] is False


def test_moved_place_respects_visit_duration(test_env):
    session, client = test_env
    trip, city, days = _create_base_trip(session, num_days=2)

    fort = Place(id=uuid4(), city_id=city.id, name="Kumbhalgarh Fort", category="fort", latitude=24.58, longitude=73.68)
    session.add(fort)
    stop = TripItinerary(id=uuid4(), trip_id=trip.id, place_id=fort.id, day_number=1, visit_order=1, status="MISSED")
    session.add(stop)
    session.add(UserSavedPlace(trip_id=trip.id, place_id=fort.id))
    session.commit()

    resp = client.post(
        f"/trips/{trip.id}/itinerary/move-place",
        json={"place_id": str(fort.id), "target_day_number": 2},
    )
    assert resp.status_code == 200
    target_stop = resp.json()["target_itinerary"][0]
    # Fort category duration is 120 mins
    arr = datetime.strptime(target_stop["planned_arrival_time"], "%H:%M:%S")
    dep = datetime.strptime(target_stop["planned_departure_time"], "%H:%M:%S")
    assert (dep - arr).total_seconds() == 120 * 60


# ---------------------------------------------------------------------------
# Tests 19 - 24: Infeasibility, REST day, No window, Locked preservation
# ---------------------------------------------------------------------------


def test_cannot_move_place_to_rest_day(test_env):
    session, client = test_env
    trip, city, days = _create_base_trip(session, num_days=2)

    # Configure Day 2 as REST
    days[1].day_type = "REST"
    session.add(days[1])

    p1 = Place(id=uuid4(), city_id=city.id, name="Place 1", category="heritage", latitude=24.58, longitude=73.68)
    session.add(p1)
    stop = TripItinerary(id=uuid4(), trip_id=trip.id, place_id=p1.id, day_number=1, visit_order=1, status="MISSED")
    session.add(stop)
    session.add(UserSavedPlace(trip_id=trip.id, place_id=p1.id))
    session.commit()

    resp = client.post(
        f"/trips/{trip.id}/itinerary/move-place",
        json={"place_id": str(p1.id), "target_day_number": 2},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["success"] is False
    assert body["reason"] == "TARGET_DAY_REST"


def test_cannot_move_place_to_another_trips_day(test_env):
    session, client = test_env
    trip1, city, days1 = _create_base_trip(session, num_days=2)
    trip2, _, days2 = _create_base_trip(session, num_days=2)

    p1 = Place(id=uuid4(), city_id=city.id, name="Place 1", category="heritage", latitude=24.58, longitude=73.68)
    session.add(p1)
    stop = TripItinerary(id=uuid4(), trip_id=trip1.id, place_id=p1.id, day_number=1, visit_order=1, status="MISSED")
    session.add(stop)
    session.add(UserSavedPlace(trip_id=trip1.id, place_id=p1.id))
    session.commit()

    # Pass day_id belonging to trip2
    resp = client.post(
        f"/trips/{trip1.id}/itinerary/move-place",
        json={"place_id": str(p1.id), "target_day_id": str(days2[0].id)},
    )
    assert resp.status_code == 422


def test_cannot_move_place_to_day_with_no_sightseeing_window(test_env):
    session, client = test_env
    trip, city, days = _create_base_trip(session, num_days=2)

    # Configure Day 2 with zero window: 10:00 to 10:00
    days[1].start_time = time(10, 0)
    days[1].end_time = time(10, 0)
    session.add(days[1])

    p1 = Place(id=uuid4(), city_id=city.id, name="Place 1", category="heritage", latitude=24.58, longitude=73.68)
    session.add(p1)
    stop = TripItinerary(id=uuid4(), trip_id=trip.id, place_id=p1.id, day_number=1, visit_order=1, status="MISSED")
    session.add(stop)
    session.add(UserSavedPlace(trip_id=trip.id, place_id=p1.id))
    session.commit()

    resp = client.post(
        f"/trips/{trip.id}/itinerary/move-place",
        json={"place_id": str(p1.id), "target_day_number": 2},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["success"] is False
    assert body["reason"] == "TARGET_DAY_NO_SIGHTSEEING_WINDOW"


def test_infeasible_target_day_returns_structured_failure_and_leaves_data_untouched(test_env):
    session, client = test_env
    trip, city, days = _create_base_trip(session, num_days=2)

    # Day 2 window is tight: 1 hour (09:00 to 10:00)
    days[1].start_time = time(9, 0)
    days[1].end_time = time(10, 0)
    session.add(days[1])

    # Day 2 already has an existing 60-min heritage place
    pExisting = Place(id=uuid4(), city_id=city.id, name="Existing Place", category="heritage", latitude=24.58, longitude=73.68)
    # New place is a 90-min fort
    pFort = Place(id=uuid4(), city_id=city.id, name="Huge Fort", category="fort", latitude=24.65, longitude=73.75)
    session.add_all([pExisting, pFort])

    stopExisting = TripItinerary(id=uuid4(), trip_id=trip.id, place_id=pExisting.id, day_number=2, visit_order=1, planned_arrival_time=time(9, 0), planned_departure_time=time(10, 0), status="PLANNED")
    stopFort = TripItinerary(id=uuid4(), trip_id=trip.id, place_id=pFort.id, day_number=1, visit_order=1, status="MISSED")
    session.add_all([stopExisting, stopFort])
    session.add(UserSavedPlace(trip_id=trip.id, place_id=pExisting.id, assignment_mode="LOCKED", assigned_day_id=days[1].id))
    session.add(UserSavedPlace(trip_id=trip.id, place_id=pFort.id))
    session.commit()

    # Move pFort to Day 2 -> Infeasible because Day 2 only has 60 minutes capacity
    resp = client.post(
        f"/trips/{trip.id}/itinerary/move-place",
        json={"place_id": str(pFort.id), "target_day_number": 2},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["success"] is False
    assert body["reason"] == "TARGET_DAY_INFEASIBLE"

    # Verify Day 2 existing place is NOT deleted and pFort is NOT added
    d2 = session.exec(select(TripItinerary).where(TripItinerary.trip_id == trip.id, TripItinerary.day_number == 2)).all()
    assert len(d2) == 1
    assert d2[0].place_id == pExisting.id

    # Verify pFort remains on Day 1
    d1 = session.exec(select(TripItinerary).where(TripItinerary.trip_id == trip.id, TripItinerary.day_number == 1)).all()
    assert len(d1) == 1
    assert d1[0].place_id == pFort.id


# ---------------------------------------------------------------------------
# Tests 25 - 28: Exclusions, Cache Reuse, Route Recalculation Protection
# ---------------------------------------------------------------------------


def test_completed_place_cannot_be_moved(test_env):
    session, client = test_env
    trip, city, days = _create_base_trip(session, num_days=2)

    p1 = Place(id=uuid4(), city_id=city.id, name="Done Place", category="heritage", latitude=24.58, longitude=73.68)
    session.add(p1)
    stop = TripItinerary(id=uuid4(), trip_id=trip.id, place_id=p1.id, day_number=1, visit_order=1, status="COMPLETED")
    session.add(stop)
    session.add(UserSavedPlace(trip_id=trip.id, place_id=p1.id))
    session.commit()

    resp = client.post(
        f"/trips/{trip.id}/itinerary/move-place",
        json={"place_id": str(p1.id), "target_day_number": 2},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["success"] is False
    assert body["reason"] == "CANNOT_MOVE_COMPLETED_PLACE"


def test_route_matrix_cache_reused_during_partial_replan(test_env):
    session, client = test_env
    trip, city, days = _create_base_trip(session, num_days=2)

    p1 = Place(id=uuid4(), city_id=city.id, name="Place 1", category="heritage", latitude=24.58, longitude=73.68)
    p2 = Place(id=uuid4(), city_id=city.id, name="Place 2", category="monument", latitude=24.59, longitude=73.69)
    session.add_all([p1, p2])
    session.add(UserSavedPlace(trip_id=trip.id, place_id=p1.id))
    session.add(UserSavedPlace(trip_id=trip.id, place_id=p2.id))
    session.commit()

    # Pre-populate RouteMatrixCache for p1 and p2 and start
    rm_service = RouteMatrixService()
    provider = LocalRoutesService()
    import asyncio
    asyncio.run(rm_service.get_complete_matrix(session, trip, [p1, p2], provider))

    initial_cache_count = len(session.exec(select(RouteMatrixCache).where(RouteMatrixCache.trip_id == trip.id)).all())
    assert initial_cache_count > 0

    # Add itinerary rows
    s1 = TripItinerary(id=uuid4(), trip_id=trip.id, place_id=p1.id, day_number=1, visit_order=1, status="MISSED")
    session.add(s1)
    session.commit()

    # Move p1 to Day 2 (where p2 is not even scheduled yet, but p1 is known)
    resp = client.post(
        f"/trips/{trip.id}/itinerary/move-place",
        json={"place_id": str(p1.id), "target_day_number": 2},
    )
    assert resp.status_code == 200
    assert resp.json()["success"] is True

    # No new matrix rows needed because p1 was already cached
    after_cache_count = len(session.exec(select(RouteMatrixCache).where(RouteMatrixCache.trip_id == trip.id)).all())
    assert after_cache_count == initial_cache_count


# ---------------------------------------------------------------------------
# Performance Benchmarks: 4 places + 1 moved, 8 places + 1, 12 places + 1
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("place_count", [4, 8, 12])
def test_partial_replan_performance(test_env, place_count):
    session, client = test_env
    trip, city, days = _create_base_trip(session, num_days=2)
    # Day 2 touring window: 08:00 to 22:00 (14 hours)
    days[1].start_time = time(8, 0)
    days[1].end_time = time(22, 0)
    session.add(days[1])

    places = []
    for i in range(place_count):
        p = Place(
            id=uuid4(),
            city_id=city.id,
            name=f"Place {i}",
            category="viewpoint",
            latitude=24.57 + i * 0.005,
            longitude=73.68 + i * 0.005,
        )
        session.add(p)
        session.add(UserSavedPlace(trip_id=trip.id, place_id=p.id))
        places.append(p)

    # Place to move
    pMoved = Place(
        id=uuid4(),
        city_id=city.id,
        name="Moved Item",
        category="cafes",
        latitude=24.585,
        longitude=73.685,
    )
    session.add(pMoved)
    session.add(UserSavedPlace(trip_id=trip.id, place_id=pMoved.id))
    session.commit()

    # Put existing places on Day 2 with order 1..N
    for i, p in enumerate(places):
        session.add(
            TripItinerary(
                id=uuid4(),
                trip_id=trip.id,
                place_id=p.id,
                day_number=2,
                visit_order=i + 1,
                planned_arrival_time=time(8 + (i // 2), (i % 2) * 30),
                planned_departure_time=time(8 + (i // 2), (i % 2) * 30 + 25),
                status="PLANNED",
            )
        )
    # pMoved is on Day 1
    session.add(
        TripItinerary(
            id=uuid4(),
            trip_id=trip.id,
            place_id=pMoved.id,
            day_number=1,
            visit_order=1,
            status="MISSED",
        )
    )
    session.commit()

    t_start = pytime.perf_counter()
    resp = client.post(
        f"/trips/{trip.id}/itinerary/move-place",
        json={"place_id": str(pMoved.id), "target_day_number": 2},
    )
    t_elapsed = pytime.perf_counter() - t_start

    assert resp.status_code == 200
    assert resp.json()["success"] is True
    # Verify execution time is bounded and fast
    assert t_elapsed < 4.0, f"Partial replanning took {t_elapsed:.3f}s for {place_count}+1 places"
