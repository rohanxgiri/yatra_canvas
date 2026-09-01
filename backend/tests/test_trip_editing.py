"""Trip reading, editing, and downstream invalidation tests."""

from collections.abc import Generator
from datetime import datetime, timezone
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import event
from sqlalchemy.engine import Engine
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.database import get_session
from app.main import app
from app.models import (
    Place,
    RouteMatrixCache,
    Trip,
    TripItinerary,
    TripPreference,
    UserSavedPlace,
)
from app.schemas import TripUpdate
from app.services.trip_service import TripService


@pytest.fixture
def client_and_engine() -> Generator[tuple[TestClient, Engine], None, None]:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)

    def override_session() -> Generator[Session, None, None]:
        with Session(engine) as session:
            yield session

    app.dependency_overrides[get_session] = override_session
    client = TestClient(app)
    yield client, engine
    client.close()
    app.dependency_overrides.clear()
    SQLModel.metadata.drop_all(engine)


def _create_city(
    client: TestClient, name: str = "Ujjain", state: str = "Madhya Pradesh"
) -> dict[str, object]:
    response = client.post(
        "/cities",
        json={
            "name": name,
            "state": state,
            "country": "India",
            "latitude": 23.1765,
            "longitude": 75.7885,
            "google_place_id": f"trip-city-{uuid4()}",
        },
    )
    assert response.status_code == 201
    return response.json()


def _create_trip(client: TestClient, city_id: str) -> dict[str, object]:
    response = client.post(
        "/trips",
        json={
            "city_id": city_id,
            "trip_name": "Ujjain Spiritual Trip",
            "start_date": "2026-09-10",
            "end_date": "2026-09-12",
            "days": 3,
            "arrival_place": "Ujjain Railway Station",
            "arrival_latitude": 23.1793,
            "arrival_longitude": 75.7849,
            "start_location_type": "hotel",
            "start_location_name": "Hotel Imperial",
            "start_latitude": 23.1801,
            "start_longitude": 75.7812,
            "start_location_provider": "geoapify",
            "start_location_provider_place_id": "geoapify-hotel-imperial",
            "purposes": ["Religious / Spiritual", "Culture & Heritage"],
            "preferences": ["Balanced", "Chill", "Walking", "Auto / Cab"],
        },
    )
    assert response.status_code == 201
    return response.json()


def test_get_existing_trip_returns_complete_representation(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, _ = client_and_engine
    city = _create_city(client)
    created = _create_trip(client, str(city["id"]))
    trip_id = created["trip_id"]

    response = client.get(f"/trips/{trip_id}")

    assert response.status_code == 200
    body = response.json()
    assert body["trip_id"] == trip_id
    assert body["city_id"] == city["id"]
    assert body["city"] is not None
    assert body["city"]["name"] == "Ujjain"
    assert body["city"]["country"] == "India"
    assert body["trip_name"] == "Ujjain Spiritual Trip"
    assert body["days"] == 3
    assert body["start_date"] == "2026-09-10"
    assert body["end_date"] == "2026-09-12"
    assert body["arrival_place"] == "Ujjain Railway Station"
    assert body["arrival_latitude"] == 23.1793
    assert body["arrival_longitude"] == 75.7849
    assert body["start_location_type"] == "hotel"
    assert body["start_location_name"] == "Hotel Imperial"
    assert body["start_latitude"] == 23.1801
    assert body["start_longitude"] == 75.7812
    assert body["start_location_provider"] == "geoapify"
    assert body["start_location_provider_place_id"] == "geoapify-hotel-imperial"
    assert body["preferences"] == [
        "Religious / Spiritual",
        "Culture & Heritage",
        "Balanced",
        "Chill",
        "Walking",
        "Auto / Cab",
    ]
    assert "user_id" not in body


def test_get_unknown_trip_returns_404(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, _ = client_and_engine
    unknown_id = str(uuid4())

    response = client.get(f"/trips/{unknown_id}")

    assert response.status_code == 404
    assert response.json() == {"detail": "Trip not found."}


def test_patch_single_field(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, engine = client_and_engine
    city = _create_city(client)
    created = _create_trip(client, str(city["id"]))
    trip_id = created["trip_id"]

    response = client.patch(
        f"/trips/{trip_id}",
        json={"trip_name": "Updated Weekend Getaway"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["trip_name"] == "Updated Weekend Getaway"
    assert body["days"] == 3
    assert body["start_date"] == "2026-09-10"

    with Session(engine) as session:
        trip = session.get(Trip, UUID(trip_id))
        assert trip is not None
        assert trip.trip_name == "Updated Weekend Getaway"


def test_patch_multiple_fields_and_dates(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, engine = client_and_engine
    city = _create_city(client)
    created = _create_trip(client, str(city["id"]))
    trip_id = created["trip_id"]

    response = client.patch(
        f"/trips/{trip_id}",
        json={
            "trip_name": "Extended Retreat",
            "start_date": "2026-09-15",
            "end_date": "2026-09-19",
            "days": 5,
            "arrival_place": "Indore Airport",
            "arrival_latitude": 22.7217,
            "arrival_longitude": 75.8011,
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["trip_name"] == "Extended Retreat"
    assert body["start_date"] == "2026-09-15"
    assert body["end_date"] == "2026-09-19"
    assert body["days"] == 5
    assert body["arrival_place"] == "Indore Airport"
    assert body["arrival_latitude"] == 22.7217
    assert body["arrival_longitude"] == 75.8011

    with Session(engine) as session:
        trip = session.get(Trip, UUID(trip_id))
        assert trip is not None
        assert trip.days == 5
        assert trip.arrival_place == "Indore Airport"


def test_patch_preferences_reconciles_and_avoids_duplicates(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, engine = client_and_engine
    city = _create_city(client)
    created = _create_trip(client, str(city["id"]))
    trip_id = created["trip_id"]

    response = client.patch(
        f"/trips/{trip_id}",
        json={
            "purposes": ["Food Exploration", "Photography"],
            "preferences": ["Packed", "Boujee", "Own Vehicle", "food exploration"],
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["preferences"] == [
        "Food Exploration",
        "Photography",
        "Packed",
        "Boujee",
        "Own Vehicle",
    ]

    with Session(engine) as session:
        preferences = session.exec(
            select(TripPreference).where(TripPreference.trip_id == UUID(trip_id))
        ).all()
        pref_set = {p.preference for p in preferences}
        assert pref_set == {
            "Food Exploration",
            "Photography",
            "Packed",
            "Boujee",
            "Own Vehicle",
        }
        # Verify old preferences are removed
        assert "Religious / Spiritual" not in pref_set
        assert "Chill" not in pref_set


@pytest.mark.parametrize(
    "changes",
    [
        {"days": 0},
        {"start_date": "2026-09-20", "end_date": "2026-09-18"},
        {"start_date": "2026-09-10", "end_date": "2026-09-12", "days": 10},
    ],
)
def test_patch_trip_rejects_invalid_dates(
    client_and_engine: tuple[TestClient, Engine],
    changes: dict[str, object],
) -> None:
    client, _ = client_and_engine
    city = _create_city(client)
    created = _create_trip(client, str(city["id"]))
    trip_id = created["trip_id"]

    response = client.patch(f"/trips/{trip_id}", json=changes)

    assert response.status_code == 422


@pytest.mark.parametrize(
    "changes",
    [
        {"arrival_latitude": 95.0},
        {"arrival_latitude": 23.1, "arrival_longitude": None},
        {"start_latitude": None, "start_longitude": 75.7},
        {"start_location_provider": "geoapify", "start_location_provider_place_id": None},
    ],
)
def test_patch_trip_rejects_invalid_coordinates(
    client_and_engine: tuple[TestClient, Engine],
    changes: dict[str, object],
) -> None:
    client, _ = client_and_engine
    city = _create_city(client)
    created = _create_trip(client, str(city["id"]))
    trip_id = created["trip_id"]

    response = client.patch(f"/trips/{trip_id}", json=changes)

    assert response.status_code == 422


def test_patch_unknown_trip_returns_404(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, _ = client_and_engine
    unknown_id = str(uuid4())

    response = client.patch(
        f"/trips/{unknown_id}",
        json={"trip_name": "Ghost Trip"},
    )

    assert response.status_code == 404
    assert response.json() == {"detail": "Trip not found."}


def test_patch_unknown_city_returns_404(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, _ = client_and_engine
    city = _create_city(client)
    created = _create_trip(client, str(city["id"]))
    trip_id = created["trip_id"]
    unknown_city_id = str(uuid4())

    response = client.patch(
        f"/trips/{trip_id}",
        json={"city_id": unknown_city_id},
    )

    assert response.status_code == 404
    assert response.json() == {"detail": "City not found."}


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("id", str(uuid4())),
        ("trip_id", str(uuid4())),
        ("user_id", str(uuid4())),
        ("created_at", "2026-09-01T00:00:00Z"),
    ],
)
def test_patch_trip_rejects_server_owned_fields(
    client_and_engine: tuple[TestClient, Engine],
    field: str,
    value: str,
) -> None:
    client, _ = client_and_engine
    city = _create_city(client)
    created = _create_trip(client, str(city["id"]))
    trip_id = created["trip_id"]

    response = client.patch(
        f"/trips/{trip_id}",
        json={field: value},
    )

    assert response.status_code == 422


def test_patch_trip_rolls_back_on_preference_failure(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, engine = client_and_engine
    city = _create_city(client)
    created = _create_trip(client, str(city["id"]))
    trip_id = UUID(created["trip_id"])
    update_request = TripUpdate(
        trip_name="Should Not Persist",
        preferences=["New Preference"],
    )

    def fail_preference_insert(*_: object) -> None:
        raise RuntimeError("controlled preference update failure")

    event.listen(TripPreference, "before_insert", fail_preference_insert)
    try:
        with Session(engine) as session:
            with pytest.raises(RuntimeError, match="controlled preference update failure"):
                TripService().update(session, trip_id, update_request)
    finally:
        event.remove(TripPreference, "before_insert", fail_preference_insert)

    with Session(engine) as session:
        trip = session.get(Trip, trip_id)
        assert trip is not None
        assert trip.trip_name == "Ujjain Spiritual Trip"
        preferences = session.exec(
            select(TripPreference).where(TripPreference.trip_id == trip_id)
        ).all()
        assert {p.preference for p in preferences} == {
            "Religious / Spiritual",
            "Culture & Heritage",
            "Balanced",
            "Chill",
            "Walking",
            "Auto / Cab",
        }


def test_existing_saved_places_are_preserved_and_cache_invalidated_on_city_or_start_change(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, engine = client_and_engine
    city1 = _create_city(client, name="Ujjain")
    city2 = _create_city(client, name="Jaipur", state="Rajasthan")
    created = _create_trip(client, str(city1["id"]))
    trip_id = UUID(created["trip_id"])

    with Session(engine) as session:
        place = Place(
            city_id=UUID(city1["id"]),
            name="Mahakaleshwar Temple",
            category="religious",
            latitude=23.1827,
            longitude=75.7682,
        )
        session.add(place)
        session.flush()

        saved_place = UserSavedPlace(
            trip_id=trip_id,
            place_id=place.id,
            custom_order=1,
            priority=5,
            notes="Must visit morning aarti",
        )
        session.add(saved_place)

        now = datetime.now(timezone.utc)
        route_cache = RouteMatrixCache(
            trip_id=trip_id,
            from_location_type="start",
            from_latitude=23.1801,
            from_longitude=75.7812,
            to_location_type="place",
            to_place_id=place.id,
            from_key="start:23.1801:75.7812",
            to_key=f"place:{place.id}",
            travel_mode="driving",
            distance_meters=1500,
            static_duration_seconds=300,
            calculated_at=now,
            expires_at=now,
        )
        session.add(route_cache)

        itinerary = TripItinerary(
            trip_id=trip_id,
            place_id=place.id,
            day_number=1,
            visit_order=1,
            distance_from_previous=1.5,
            travel_time_minutes=5,
        )
        session.add(itinerary)
        session.commit()

    # Verify downstream rows exist before update
    with Session(engine) as session:
        assert session.exec(select(UserSavedPlace).where(UserSavedPlace.trip_id == trip_id)).all() != []
        assert session.exec(select(RouteMatrixCache).where(RouteMatrixCache.trip_id == trip_id)).all() != []
        assert session.exec(select(TripItinerary).where(TripItinerary.trip_id == trip_id)).all() != []

    # Update destination city
    response = client.patch(
        f"/trips/{trip_id}",
        json={"city_id": city2["id"]},
    )
    assert response.status_code == 200

    # UserSavedPlace must be strictly preserved, while route cache and itinerary are safely invalidated
    with Session(engine) as session:
        saved_rows = session.exec(select(UserSavedPlace).where(UserSavedPlace.trip_id == trip_id)).all()
        assert len(saved_rows) == 1
        assert saved_rows[0].notes == "Must visit morning aarti"

        cache_rows = session.exec(select(RouteMatrixCache).where(RouteMatrixCache.trip_id == trip_id)).all()
        assert cache_rows == []

        itinerary_rows = session.exec(select(TripItinerary).where(TripItinerary.trip_id == trip_id)).all()
        assert itinerary_rows == []
