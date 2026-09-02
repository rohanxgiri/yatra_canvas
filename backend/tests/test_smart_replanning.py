"""Unit and API tests for Smart Trip Re-planning and Invalidation Engine."""

from datetime import date, datetime, time, timezone
from uuid import uuid4

from fastapi.testclient import TestClient
import pytest
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.database import get_session
from app.main import app
from app.models.entities import City, Place, RouteMatrixCache, Trip, TripItinerary, UserSavedPlace
from app.schemas.smart_replanning import TripReplanImpactRead, TripReplanPreviewRead
from app.services.smart_replanning_service import (
    SmartReplanningService,
    TripChangeType,
    evaluate_change_impact,
    purge_stale_matrix_cache,
)


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


def test_invalidation_rules():
    """Verify deterministic change impact evaluation rules."""
    # 1. Notes change
    impact = evaluate_change_impact(TripChangeType.UPDATE_NOTES)
    assert impact.itinerary_stale is False
    assert impact.route_matrix_stale is False
    assert impact.matrix_purge_scope == "none"
    assert impact.requires_replan_preview is False

    # 2. Add place
    impact = evaluate_change_impact(TripChangeType.ADD_PLACE)
    assert impact.itinerary_stale is True
    assert impact.route_matrix_stale is True
    assert impact.matrix_purge_scope == "none"
    assert impact.requires_replan_preview is True

    # 3. Remove place
    impact = evaluate_change_impact(TripChangeType.REMOVE_PLACE)
    assert impact.itinerary_stale is True
    assert impact.route_matrix_stale is False
    assert impact.matrix_purge_scope == "none"
    assert impact.requires_replan_preview is True

    # 4. Start location change
    impact = evaluate_change_impact(TripChangeType.UPDATE_START_LOCATION)
    assert impact.itinerary_stale is True
    assert impact.route_matrix_stale is True
    assert impact.matrix_purge_scope == "start_only"
    assert impact.requires_replan_preview is True

    # 5. Dates change
    impact = evaluate_change_impact(TripChangeType.UPDATE_DATES)
    assert impact.itinerary_stale is True
    assert impact.route_matrix_stale is False
    assert impact.weather_advisory_stale is True
    assert impact.matrix_purge_scope == "none"

    # 6. City change
    impact = evaluate_change_impact(TripChangeType.UPDATE_CITY)
    assert impact.itinerary_stale is True
    assert impact.matrix_purge_scope == "all"
    assert impact.requires_replan_preview is True


def test_selective_cache_purging(session_and_client):
    """Verify that changing start location purges ONLY start legs and preserves place-to-place legs."""
    session, client = session_and_client
    trip_id = uuid4()
    p1_id = uuid4()
    p2_id = uuid4()

    # Seed 3 cached legs: start->p1, p1->start, and p1->p2
    leg_start_to_p1 = RouteMatrixCache(
        trip_id=trip_id,
        from_location_type="start",
        to_location_type="place",
        from_key="start",
        from_latitude=26.91,
        from_longitude=75.78,
        to_key=f"place:{p1_id}",
        to_place_id=p1_id,
        distance_meters=5000,
        static_duration_seconds=600,
        calculated_at=datetime.now(timezone.utc),
    )
    leg_p1_to_start = RouteMatrixCache(
        trip_id=trip_id,
        from_location_type="place",
        to_location_type="start",
        from_key=f"place:{p1_id}",
        from_place_id=p1_id,
        to_key="start",
        to_latitude=26.91,
        to_longitude=75.78,
        distance_meters=5000,
        static_duration_seconds=600,
        calculated_at=datetime.now(timezone.utc),
    )
    leg_p1_to_p2 = RouteMatrixCache(
        trip_id=trip_id,
        from_location_type="place",
        to_location_type="place",
        from_key=f"place:{p1_id}",
        to_key=f"place:{p2_id}",
        from_place_id=p1_id,
        to_place_id=p2_id,
        distance_meters=3000,
        static_duration_seconds=400,
        calculated_at=datetime.now(timezone.utc),
    )
    session.add_all([leg_start_to_p1, leg_p1_to_start, leg_p1_to_p2])
    session.commit()

    # Purge only start
    purged = purge_stale_matrix_cache(session, trip_id, "start_only")
    assert purged == 2

    # Verify place-to-place leg is preserved
    remaining = session.exec(select(RouteMatrixCache).where(RouteMatrixCache.trip_id == trip_id)).all()
    assert len(remaining) == 1
    assert remaining[0].from_location_type == "place"
    assert remaining[0].to_location_type == "place"
    assert remaining[0].distance_meters == 3000


def test_replan_impact_detects_stale_itinerary(session_and_client):
    """Verify that adding/removing saved places is accurately detected as stale."""
    session, client = session_and_client
    city = City(id=uuid4(), name="Jaipur", country="India", latitude=26.91, longitude=75.78)
    session.add(city)
    trip = Trip(
        id=uuid4(),
        city_id=city.id,
        user_id=uuid4(),
        trip_name="Jaipur Trip",
        start_date=date(2026, 9, 15),
        days=1,
        arrival_place="Jaipur Station",
        arrival_latitude=26.91,
        arrival_longitude=75.78,
        start_location_type="arrival",
        start_location_name="Jaipur Station",
        start_latitude=26.91,
        start_longitude=75.78,
    )
    session.add(trip)

    p1 = Place(id=uuid4(), city_id=city.id, name="Hawa Mahal", category="monument", latitude=26.92, longitude=75.82)
    p2 = Place(id=uuid4(), city_id=city.id, name="City Palace", category="palace", latitude=26.92, longitude=75.83)
    session.add_all([p1, p2])

    session.add(UserSavedPlace(trip_id=trip.id, place_id=p1.id, custom_order=1))
    session.add(UserSavedPlace(trip_id=trip.id, place_id=p2.id, custom_order=2))

    # Synchronized itinerary
    session.add(TripItinerary(trip_id=trip.id, place_id=p1.id, day_number=1, visit_order=1))
    session.add(TripItinerary(trip_id=trip.id, place_id=p2.id, day_number=1, visit_order=2))
    session.commit()

    service = SmartReplanningService()
    impact = service.check_itinerary_stale(session, trip.id)
    assert impact.is_stale is False
    assert len(impact.reasons) == 0

    # User adds a third place
    p3 = Place(id=uuid4(), city_id=city.id, name="Amer Fort", category="fort", latitude=26.98, longitude=75.85)
    session.add(p3)
    session.add(UserSavedPlace(trip_id=trip.id, place_id=p3.id, custom_order=3))
    session.commit()

    impact2 = service.check_itinerary_stale(session, trip.id)
    assert impact2.is_stale is True
    assert impact2.requires_replan_preview is True
    assert any("not yet scheduled" in r for r in impact2.reasons)


def test_replan_preview_and_atomic_apply(session_and_client):
    """Verify that replan preview does not persist and apply transactionally commits changes."""
    session, client = session_and_client
    city = City(id=uuid4(), name="Jaipur", country="India", latitude=26.91, longitude=75.78)
    session.add(city)
    trip = Trip(
        id=uuid4(),
        city_id=city.id,
        user_id=uuid4(),
        trip_name="Jaipur Trip",
        start_date=date(2026, 9, 15),
        days=1,
        arrival_place="Jaipur Station",
        arrival_latitude=26.91,
        arrival_longitude=75.78,
        start_location_type="arrival",
        start_location_name="Jaipur Station",
        start_latitude=26.91,
        start_longitude=75.78,
    )
    session.add(trip)

    p1 = Place(id=uuid4(), city_id=city.id, name="Hawa Mahal", category="monument", latitude=26.92, longitude=75.82)
    p2 = Place(id=uuid4(), city_id=city.id, name="City Palace", category="palace", latitude=26.92, longitude=75.83)
    session.add_all([p1, p2])

    session.add(UserSavedPlace(trip_id=trip.id, place_id=p1.id, custom_order=1))
    session.add(UserSavedPlace(trip_id=trip.id, place_id=p2.id, custom_order=2))
    # Itinerary initially has only p1
    session.add(TripItinerary(trip_id=trip.id, place_id=p1.id, day_number=1, visit_order=1))
    session.commit()

    # 1. Preview Re-plan via API
    resp = client.post(f"/trips/{trip.id}/replan-preview")
    assert resp.status_code == 200
    preview = resp.json()

    assert preview["is_stale"] is True
    assert "City Palace" in preview["added_places"]
    assert len(preview["proposed_itinerary"]) == 2

    # PREVIEW DOES NOT PERSIST: Check database still has only 1 row
    current_rows = session.exec(select(TripItinerary).where(TripItinerary.trip_id == trip.id)).all()
    assert len(current_rows) == 1
    assert current_rows[0].place_id == p1.id

    # 2. Apply Re-plan via API
    apply_resp = client.post(f"/trips/{trip.id}/replan-apply")
    assert apply_resp.status_code == 200
    applied = apply_resp.json()

    assert len(applied["optimized_places"]) == 2

    # APPLY PERSISTS: Check database now has 2 rows with arrival/departure times
    rows_after = session.exec(select(TripItinerary).where(TripItinerary.trip_id == trip.id)).all()
    assert len(rows_after) == 2
    for r in rows_after:
        assert r.planned_arrival_time is not None
        assert r.planned_departure_time is not None


def test_notes_only_change_does_not_mark_stale(session_and_client):
    """Verify that updating notes on a saved place does not mark itinerary stale."""
    session, client = session_and_client
    city = City(id=uuid4(), name="Jaipur", country="India", latitude=26.91, longitude=75.78)
    session.add(city)
    trip = Trip(
        id=uuid4(),
        city_id=city.id,
        user_id=uuid4(),
        trip_name="Jaipur Trip",
        start_date=date(2026, 9, 15),
        days=1,
        arrival_place="Jaipur Station",
        arrival_latitude=26.91,
        arrival_longitude=75.78,
        start_location_type="arrival",
        start_location_name="Jaipur Station",
        start_latitude=26.91,
        start_longitude=75.78,
    )
    session.add(trip)
    p1 = Place(id=uuid4(), city_id=city.id, name="Hawa Mahal", category="monument", latitude=26.92, longitude=75.82)
    session.add(p1)
    saved = UserSavedPlace(trip_id=trip.id, place_id=p1.id, notes="Old note", custom_order=1)
    session.add(saved)
    session.add(TripItinerary(trip_id=trip.id, place_id=p1.id, day_number=1, visit_order=1))
    session.commit()

    # Edit note via API
    resp = client.patch(f"/trips/{trip.id}/saved-places/{p1.id}", json={"notes": "Updated note: visit early morning"})
    assert resp.status_code == 200

    service = SmartReplanningService()
    impact = service.check_itinerary_stale(session, trip.id)
    assert impact.is_stale is False
    assert impact.requires_replan_preview is False


def test_remove_place_shows_in_preview(session_and_client):
    """Verify that removing a saved place shows up under removed_places in replan preview."""
    session, client = session_and_client
    city = City(id=uuid4(), name="Jaipur", country="India", latitude=26.91, longitude=75.78)
    session.add(city)
    trip = Trip(
        id=uuid4(),
        city_id=city.id,
        user_id=uuid4(),
        trip_name="Jaipur Trip",
        start_date=date(2026, 9, 15),
        days=1,
        arrival_place="Jaipur Station",
        arrival_latitude=26.91,
        arrival_longitude=75.78,
        start_location_type="arrival",
        start_location_name="Jaipur Station",
        start_latitude=26.91,
        start_longitude=75.78,
    )
    session.add(trip)
    p1 = Place(id=uuid4(), city_id=city.id, name="Hawa Mahal", category="monument", latitude=26.92, longitude=75.82)
    p2 = Place(id=uuid4(), city_id=city.id, name="City Palace", category="palace", latitude=26.92, longitude=75.83)
    p3 = Place(id=uuid4(), city_id=city.id, name="Amer Fort", category="fort", latitude=26.98, longitude=75.85)
    session.add_all([p1, p2, p3])

    # Saved places initially has p1 and p2 (p3 was removed)
    session.add(UserSavedPlace(trip_id=trip.id, place_id=p1.id, custom_order=1))
    session.add(UserSavedPlace(trip_id=trip.id, place_id=p2.id, custom_order=2))

    # Current itinerary still has p1, p2, AND p3
    session.add(TripItinerary(trip_id=trip.id, place_id=p1.id, day_number=1, visit_order=1))
    session.add(TripItinerary(trip_id=trip.id, place_id=p2.id, day_number=1, visit_order=2))
    session.add(TripItinerary(trip_id=trip.id, place_id=p3.id, day_number=1, visit_order=3))
    session.commit()

    resp = client.post(f"/trips/{trip.id}/replan-preview")
    assert resp.status_code == 200
    preview = resp.json()

    assert preview["is_stale"] is True
    assert "Amer Fort" in preview["removed_places"]
    assert len(preview["proposed_itinerary"]) == 2


def test_replan_preview_conflict_when_must_visit_cannot_fit(session_and_client):
    """Verify that an infeasible trip returns 422 with conflict details during replan preview."""
    session, client = session_and_client
    city = City(id=uuid4(), name="Jaipur", country="India", latitude=26.91, longitude=75.78)
    session.add(city)
    trip = Trip(
        id=uuid4(),
        city_id=city.id,
        user_id=uuid4(),
        trip_name="Jaipur Trip",
        start_date=date(2026, 9, 15),
        days=1,
        arrival_place="Jaipur Station",
        arrival_latitude=26.91,
        arrival_longitude=75.78,
        start_location_type="arrival",
        start_location_name="Jaipur Station",
        start_latitude=26.91,
        start_longitude=75.78,
    )
    session.add(trip)

    # 10 massive attractions with must_visit on a 1-day trip
    for i in range(10):
        p = Place(id=uuid4(), city_id=city.id, name=f"Huge Fort {i}", category="fort", latitude=26.9 + i*0.01, longitude=75.8)
        session.add(p)
        session.add(UserSavedPlace(trip_id=trip.id, place_id=p.id, custom_order=i+1, must_visit=True))
    session.commit()

    resp = client.post(f"/trips/{trip.id}/replan-preview")
    assert resp.status_code == 422
    assert "Cannot fit all must-visit places" in resp.json()["detail"]

