"""Tests for place-to-TripDay assignment foundation.

Verifies:
1. selected place defaults to AUTO
2. AUTO place has no assigned_day_id
3. place can be locked to Day 1
4. place can be locked to another valid active day
5. LOCKED requires assigned_day_id
6. place cannot be locked to another trip's day
7. place cannot be locked to REST day
8. place can switch LOCKED -> AUTO
9. switching to AUTO clears assigned_day_id
10. changing a day with locked places to REST is safely rejected
11. trip-duration reduction removing a locked day is safely rejected
12. deleting/removing a selected place does not corrupt TripDay records
13. existing trip creation still works
14. database check constraints enforce assignment consistency
"""

from collections.abc import Generator
from datetime import date
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.engine import Engine
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.database import get_session
from app.main import app
from app.models import City, Place, Trip, TripDay, UserSavedPlace
from app.schemas.saved_place import AssignmentMode
from app.schemas.trip_day import DayType


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


def _create_city(client: TestClient) -> dict[str, object]:
    response = client.post(
        "/cities",
        json={
            "name": "Jaipur",
            "state": "Rajasthan",
            "country": "India",
            "latitude": 26.9124,
            "longitude": 75.7873,
            "google_place_id": f"jaipur-{uuid4()}",
        },
    )
    assert response.status_code == 201
    return response.json()


def _create_place(client: TestClient, city_id: str, name: str) -> dict[str, object]:
    response = client.post(
        "/places",
        json={
            "city_id": city_id,
            "name": name,
            "category": "tourism",
            "latitude": 26.92,
            "longitude": 75.82,
            "rating": 4.8,
            "review_count": 5000,
            "is_popular": True,
            "is_heritage": True,
            "is_local_speciality": False,
        },
    )
    assert response.status_code == 201
    return response.json()


def _create_trip(
    client: TestClient,
    city_id: str,
    days: int = 5,
    start_date: str = "2026-10-01",
) -> dict[str, object]:
    from datetime import date as dt_date, timedelta

    s = dt_date.fromisoformat(start_date)
    end_date = (s + timedelta(days=days - 1)).isoformat()
    response = client.post(
        "/trips",
        json={
            "city_id": city_id,
            "trip_name": "Jaipur Heritage Tour",
            "start_date": start_date,
            "end_date": end_date,
            "days": days,
            "arrival_place": "Jaipur Junction",
            "arrival_latitude": 26.92,
            "arrival_longitude": 75.79,
            "start_location_type": "arrival",
            "purposes": ["Sightseeing"],
            "preferences": ["Balanced"],
        },
    )
    assert response.status_code == 201
    return response.json()


def test_selected_place_defaults_to_auto(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, _ = client_and_engine
    city = _create_city(client)
    place = _create_place(client, str(city["id"]), "Hawa Mahal")
    trip = _create_trip(client, str(city["id"]), days=3)
    trip_id = trip["trip_id"]

    res = client.post(
        f"/trips/{trip_id}/saved-places",
        json={"place_id": place["id"]},
    )
    assert res.status_code == 201
    data = res.json()
    assert data["assignment_mode"] == "AUTO"
    assert data["assigned_day_id"] is None


def test_auto_place_has_no_assigned_day_id_and_rejects_non_null(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, _ = client_and_engine
    city = _create_city(client)
    place = _create_place(client, str(city["id"]), "Amber Fort")
    trip = _create_trip(client, str(city["id"]), days=3)
    trip_id = trip["trip_id"]

    days_res = client.get(f"/trips/{trip_id}/days")
    day_1 = days_res.json()[0]

    # Explicit AUTO with assigned_day_id must be rejected
    res = client.post(
        f"/trips/{trip_id}/saved-places",
        json={
            "place_id": place["id"],
            "assignment_mode": "AUTO",
            "assigned_day_id": day_1["id"],
        },
    )
    assert res.status_code == 422


def test_place_can_be_locked_to_day_1(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, _ = client_and_engine
    city = _create_city(client)
    place = _create_place(client, str(city["id"]), "City Palace")
    trip = _create_trip(client, str(city["id"]), days=3)
    trip_id = trip["trip_id"]

    days_res = client.get(f"/trips/{trip_id}/days")
    day_1 = days_res.json()[0]

    # Create place locked to Day 1
    res = client.post(
        f"/trips/{trip_id}/saved-places",
        json={
            "place_id": place["id"],
            "assignment_mode": "LOCKED",
            "assigned_day_id": day_1["id"],
        },
    )
    assert res.status_code == 201
    data = res.json()
    assert data["assignment_mode"] == "LOCKED"
    assert data["assigned_day_id"] == day_1["id"]


def test_place_can_be_locked_to_another_valid_active_day(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, _ = client_and_engine
    city = _create_city(client)
    place = _create_place(client, str(city["id"]), "Nahargarh Fort")
    trip = _create_trip(client, str(city["id"]), days=3)
    trip_id = trip["trip_id"]

    days_res = client.get(f"/trips/{trip_id}/days")
    days = days_res.json()
    day_3 = days[2]

    # Add as AUTO first
    add_res = client.post(
        f"/trips/{trip_id}/saved-places",
        json={"place_id": place["id"]},
    )
    assert add_res.status_code == 201

    # Update to Day 3
    update_res = client.patch(
        f"/trips/{trip_id}/saved-places/{place['id']}",
        json={
            "assignment_mode": "LOCKED",
            "assigned_day_id": day_3["id"],
        },
    )
    assert update_res.status_code == 200
    data = update_res.json()
    assert data["assignment_mode"] == "LOCKED"
    assert data["assigned_day_id"] == day_3["id"]


def test_locked_requires_assigned_day_id(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, _ = client_and_engine
    city = _create_city(client)
    place = _create_place(client, str(city["id"]), "Jantar Mantar")
    trip = _create_trip(client, str(city["id"]), days=3)
    trip_id = trip["trip_id"]

    # At creation: LOCKED without assigned_day_id
    res = client.post(
        f"/trips/{trip_id}/saved-places",
        json={
            "place_id": place["id"],
            "assignment_mode": "LOCKED",
        },
    )
    assert res.status_code == 422

    # Add as AUTO
    client.post(
        f"/trips/{trip_id}/saved-places",
        json={"place_id": place["id"]},
    )

    # At update: LOCKED without assigned_day_id
    up_res = client.patch(
        f"/trips/{trip_id}/saved-places/{place['id']}",
        json={"assignment_mode": "LOCKED"},
    )
    assert up_res.status_code == 422


def test_place_cannot_be_locked_to_another_trips_day(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, _ = client_and_engine
    city = _create_city(client)
    place_a = _create_place(client, str(city["id"]), "Place A")
    trip_a = _create_trip(client, str(city["id"]), days=3)
    trip_b = _create_trip(client, str(city["id"]), days=3)

    trip_a_id = trip_a["trip_id"]
    trip_b_id = trip_b["trip_id"]

    trip_b_days = client.get(f"/trips/{trip_b_id}/days").json()
    trip_b_day_1 = trip_b_days[0]

    # Attempt to lock place in trip A to day in trip B
    res = client.post(
        f"/trips/{trip_a_id}/saved-places",
        json={
            "place_id": place_a["id"],
            "assignment_mode": "LOCKED",
            "assigned_day_id": trip_b_day_1["id"],
        },
    )
    assert res.status_code == 422
    assert "Assigned day does not belong to this trip." in res.json()["detail"]


def test_place_cannot_be_locked_to_rest_day_or_no_window_day(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, _ = client_and_engine
    city = _create_city(client)
    place = _create_place(client, str(city["id"]), "Albert Hall")
    trip = _create_trip(client, str(city["id"]), days=3)
    trip_id = trip["trip_id"]

    days = client.get(f"/trips/{trip_id}/days").json()
    day_2 = days[1]

    # Change Day 2 to REST
    rest_res = client.patch(
        f"/trips/{trip_id}/days/2",
        json={"day_type": "REST"},
    )
    assert rest_res.status_code == 200

    # Attempt to lock place to Day 2 (REST)
    res = client.post(
        f"/trips/{trip_id}/saved-places",
        json={
            "place_id": place["id"],
            "assignment_mode": "LOCKED",
            "assigned_day_id": day_2["id"],
        },
    )
    assert res.status_code == 422
    assert "Cannot lock place to Day 2 because it is a REST day." in res.json()["detail"]


def test_place_can_switch_locked_to_auto(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, _ = client_and_engine
    city = _create_city(client)
    place = _create_place(client, str(city["id"]), "Jal Mahal")
    trip = _create_trip(client, str(city["id"]), days=3)
    trip_id = trip["trip_id"]

    day_1 = client.get(f"/trips/{trip_id}/days").json()[0]

    # Create locked
    add_res = client.post(
        f"/trips/{trip_id}/saved-places",
        json={
            "place_id": place["id"],
            "assignment_mode": "LOCKED",
            "assigned_day_id": day_1["id"],
        },
    )
    assert add_res.status_code == 201
    assert add_res.json()["assignment_mode"] == "LOCKED"

    # Switch to AUTO
    switch_res = client.patch(
        f"/trips/{trip_id}/saved-places/{place['id']}",
        json={"assignment_mode": "AUTO"},
    )
    assert switch_res.status_code == 200
    data = switch_res.json()
    assert data["assignment_mode"] == "AUTO"
    assert data["assigned_day_id"] is None


def test_changing_day_with_locked_places_to_rest_is_safely_rejected(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, _ = client_and_engine
    city = _create_city(client)
    p1 = _create_place(client, str(city["id"]), "Place 1")
    p2 = _create_place(client, str(city["id"]), "Place 2")
    trip = _create_trip(client, str(city["id"]), days=3)
    trip_id = trip["trip_id"]

    day_2 = client.get(f"/trips/{trip_id}/days").json()[1]

    # Lock p1 and p2 to Day 2
    client.post(
        f"/trips/{trip_id}/saved-places",
        json={
            "place_id": p1["id"],
            "assignment_mode": "LOCKED",
            "assigned_day_id": day_2["id"],
        },
    )
    client.post(
        f"/trips/{trip_id}/saved-places",
        json={
            "place_id": p2["id"],
            "assignment_mode": "LOCKED",
            "assigned_day_id": day_2["id"],
        },
    )

    # Attempt to change Day 2 to REST
    res = client.patch(
        f"/trips/{trip_id}/days/2",
        json={"day_type": "REST"},
    )
    assert res.status_code == 422
    detail = res.json()["detail"]
    assert "Day 2 cannot be changed to REST because 2 places are locked to this day. Move or unlock those places first." in detail

    # Attempt to remove sightseeing window
    res2 = client.patch(
        f"/trips/{trip_id}/days/2",
        json={"start_time": None, "end_time": None},
    )
    assert res2.status_code == 422
    assert "Day 2 cannot have its sightseeing window removed because 2 places are locked to this day" in res2.json()["detail"]


def test_trip_duration_reduction_removing_locked_day_is_safely_rejected(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, _ = client_and_engine
    city = _create_city(client)
    place = _create_place(client, str(city["id"]), "Galta Ji")
    trip = _create_trip(client, str(city["id"]), days=5)
    trip_id = trip["trip_id"]

    day_5 = client.get(f"/trips/{trip_id}/days").json()[4]
    assert day_5["day_number"] == 5

    # Lock place to Day 5
    client.post(
        f"/trips/{trip_id}/saved-places",
        json={
            "place_id": place["id"],
            "assignment_mode": "LOCKED",
            "assigned_day_id": day_5["id"],
        },
    )

    # Attempt to reduce trip from 5 days to 3 days (eliminating Day 4 and Day 5)
    reduce_res = client.patch(
        f"/trips/{trip_id}",
        json={
            "start_date": "2026-10-01",
            "end_date": "2026-10-03",
            "days": 3,
        },
    )
    assert reduce_res.status_code == 422
    detail = reduce_res.json()["detail"]
    assert "Cannot reduce trip duration to 3 days because Day 5 has 1 place locked to it. Move or unlock those places first." in detail


def test_deleting_selected_place_does_not_corrupt_trip_day_records(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, _ = client_and_engine
    city = _create_city(client)
    place = _create_place(client, str(city["id"]), "Bapu Bazaar")
    trip = _create_trip(client, str(city["id"]), days=3)
    trip_id = trip["trip_id"]

    day_2 = client.get(f"/trips/{trip_id}/days").json()[1]

    # Lock place to Day 2
    client.post(
        f"/trips/{trip_id}/saved-places",
        json={
            "place_id": place["id"],
            "assignment_mode": "LOCKED",
            "assigned_day_id": day_2["id"],
        },
    )

    # Delete place
    del_res = client.delete(f"/trips/{trip_id}/saved-places/{place['id']}")
    assert del_res.status_code == 204

    # Verify all 3 days still exist intact
    days = client.get(f"/trips/{trip_id}/days").json()
    assert len(days) == 3
    assert [d["day_number"] for d in days] == [1, 2, 3]

    # Now Day 2 CAN be safely changed to REST
    rest_res = client.patch(
        f"/trips/{trip_id}/days/2",
        json={"day_type": "REST"},
    )
    assert rest_res.status_code == 200
    assert rest_res.json()["day_type"] == "REST"


def test_database_check_constraints_enforce_assignment_consistency(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    from sqlalchemy.exc import IntegrityError
    _, engine = client_and_engine

    with Session(engine) as session:
        city = City(
            name="Jodhpur",
            state="Rajasthan",
            country="India",
            latitude=26.2389,
            longitude=73.0243,
            google_place_id=f"jodhpur-{uuid4()}",
        )
        session.add(city)
        session.commit()

        trip = Trip(
            user_id=uuid4(),
            city_id=city.id,
            trip_name="Jodhpur Tour",
            days=2,
            start_date=date(2026, 10, 1),
        )
        session.add(trip)
        session.commit()

        day_1 = TripDay(
            trip_id=trip.id,
            day_number=1,
            date=date(2026, 10, 1),
            day_type="FULL_DAY",
        )
        session.add(day_1)
        place = Place(
            city_id=city.id,
            name="Mehrangarh Fort",
            category="tourism",
            latitude=26.29,
            longitude=73.01,
        )
        session.add(place)
        session.commit()

        # 1. Invalid mode: e.g. "INVALID"
        bad_mode = UserSavedPlace(
            trip_id=trip.id,
            place_id=place.id,
            assignment_mode="INVALID",
        )
        session.add(bad_mode)
        with pytest.raises(IntegrityError):
            session.commit()
        session.rollback()

        # 2. Inconsistent: AUTO with assigned_day_id not null
        bad_auto = UserSavedPlace(
            trip_id=trip.id,
            place_id=place.id,
            assignment_mode="AUTO",
            assigned_day_id=day_1.id,
        )
        session.add(bad_auto)
        with pytest.raises(IntegrityError):
            session.commit()
        session.rollback()

        # 3. Inconsistent: LOCKED with assigned_day_id null
        bad_locked = UserSavedPlace(
            trip_id=trip.id,
            place_id=place.id,
            assignment_mode="LOCKED",
            assigned_day_id=None,
        )
        session.add(bad_locked)
        with pytest.raises(IntegrityError):
            session.commit()
        session.rollback()


def test_is_locked_ordering_lock_coexists_with_assignment_mode(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, _ = client_and_engine
    city = _create_city(client)
    place = _create_place(client, str(city["id"]), "Albert Hall Museum")
    trip = _create_trip(client, str(city["id"]), days=3)
    trip_id = trip["trip_id"]

    day_1 = client.get(f"/trips/{trip_id}/days").json()[0]

    # Create place with is_locked=True (sequence/solver lock) AND assignment_mode=LOCKED to day 1
    res = client.post(
        f"/trips/{trip_id}/saved-places",
        json={
            "place_id": place["id"],
            "is_locked": True,
            "assignment_mode": "LOCKED",
            "assigned_day_id": day_1["id"],
        },
    )
    assert res.status_code == 201
    data = res.json()
    assert data["is_locked"] is True
    assert data["assignment_mode"] == "LOCKED"
    assert data["assigned_day_id"] == day_1["id"]
