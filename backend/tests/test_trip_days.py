"""TripDay model, service, and API integration tests.

Verifies day generation, individual day configuration, safe date reduction/extension,
and itinerary protection.
"""

from collections.abc import Generator
from datetime import date, time
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.engine import Engine
from sqlalchemy.exc import IntegrityError
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.core.itinerary_constants import DEFAULT_DAY_END_TIME, DEFAULT_DAY_START_TIME
from app.database import get_session
from app.main import app
from app.models import City, Place, Trip, TripDay, TripItinerary
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
            "name": "Varanasi",
            "state": "Uttar Pradesh",
            "country": "India",
            "latitude": 25.3176,
            "longitude": 82.9739,
            "google_place_id": f"trip-city-{uuid4()}",
        },
    )
    assert response.status_code == 201
    return response.json()


def _create_trip(
    client: TestClient,
    city_id: str,
    days: int = 5,
    start_date: str = "2026-10-01",
    end_date: str | None = None,
) -> dict[str, object]:
    from datetime import date as dt_date, timedelta
    if end_date is None:
        s = dt_date.fromisoformat(start_date)
        end_date = (s + timedelta(days=days - 1)).isoformat()
    response = client.post(
        "/trips",
        json={
            "city_id": city_id,
            "trip_name": "Varanasi Heritage Trip",
            "start_date": start_date,
            "end_date": end_date,
            "days": days,
            "arrival_place": "Varanasi Junction",
            "arrival_latitude": 25.3283,
            "arrival_longitude": 82.9863,
            "start_location_type": "arrival",
            "purposes": ["Religious / Spiritual"],
            "preferences": ["Balanced"],
        },
    )
    assert response.status_code == 201
    return response.json()


def test_1_day_trip_creates_exactly_1_trip_day(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, engine = client_and_engine
    city = _create_city(client)
    trip = _create_trip(
        client,
        str(city["id"]),
        days=1,
        start_date="2026-10-01",
        end_date="2026-10-01",
    )
    trip_id = UUID(str(trip["trip_id"]))

    with Session(engine) as session:
        days = session.exec(
            select(TripDay).where(TripDay.trip_id == trip_id)
        ).all()
        assert len(days) == 1
        assert days[0].day_number == 1
        assert days[0].date == date(2026, 10, 1)
        assert days[0].day_type == "FULL_DAY"


def test_5_day_trip_creates_exactly_5_trip_days(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, engine = client_and_engine
    city = _create_city(client)
    trip = _create_trip(
        client,
        str(city["id"]),
        days=5,
        start_date="2026-10-01",
        end_date="2026-10-05",
    )
    trip_id = UUID(str(trip["trip_id"]))

    with Session(engine) as session:
        days = session.exec(
            select(TripDay)
            .where(TripDay.trip_id == trip_id)
            .order_by(TripDay.day_number)
        ).all()
        assert len(days) == 5


def test_dates_and_day_numbers_are_sequential_and_correct(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, engine = client_and_engine
    city = _create_city(client)
    trip = _create_trip(
        client,
        str(city["id"]),
        days=5,
        start_date="2026-10-01",
        end_date="2026-10-05",
    )
    trip_id = UUID(str(trip["trip_id"]))

    expected_dates = [
        date(2026, 10, 1),
        date(2026, 10, 2),
        date(2026, 10, 3),
        date(2026, 10, 4),
        date(2026, 10, 5),
    ]

    with Session(engine) as session:
        days = session.exec(
            select(TripDay)
            .where(TripDay.trip_id == trip_id)
            .order_by(TripDay.day_number)
        ).all()
        for idx, day in enumerate(days, start=1):
            assert day.day_number == idx
            assert day.date == expected_dates[idx - 1]
            assert day.day_type == DayType.FULL_DAY.value
            assert day.start_time == DEFAULT_DAY_START_TIME
            assert day.end_time == DEFAULT_DAY_END_TIME


def test_trip_days_belong_to_correct_trip(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, engine = client_and_engine
    city = _create_city(client)
    trip1 = _create_trip(
        client,
        str(city["id"]),
        days=2,
        start_date="2026-10-01",
        end_date="2026-10-02",
    )
    trip2 = _create_trip(
        client,
        str(city["id"]),
        days=3,
        start_date="2026-10-10",
        end_date="2026-10-12",
    )
    trip1_id = UUID(str(trip1["trip_id"]))
    trip2_id = UUID(str(trip2["trip_id"]))

    with Session(engine) as session:
        trip1_days = session.exec(
            select(TripDay).where(TripDay.trip_id == trip1_id)
        ).all()
        trip2_days = session.exec(
            select(TripDay).where(TripDay.trip_id == trip2_id)
        ).all()

        assert len(trip1_days) == 2
        assert len(trip2_days) == 3
        assert all(d.trip_id == trip1_id for d in trip1_days)
        assert all(d.trip_id == trip2_id for d in trip2_days)


def test_duplicate_day_records_cannot_be_created(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, engine = client_and_engine
    city = _create_city(client)
    trip = _create_trip(client, str(city["id"]), days=2)
    trip_id = UUID(str(trip["trip_id"]))

    with Session(engine) as session:
        duplicate = TripDay(
            trip_id=trip_id,
            day_number=1,
            date=date(2026, 10, 1),
            day_type="FULL_DAY",
        )
        session.add(duplicate)
        with pytest.raises(IntegrityError):
            session.commit()


def test_full_day_can_change_to_rest_and_allows_no_sightseeing_window(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, engine = client_and_engine
    city = _create_city(client)
    trip = _create_trip(client, str(city["id"]), days=3)
    trip_id = str(trip["trip_id"])

    response = client.patch(
        f"/trips/{trip_id}/days/2",
        json={"day_type": "REST"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["day_number"] == 2
    assert body["day_type"] == "REST"
    assert body["start_time"] is None
    assert body["end_time"] is None

    with Session(engine) as session:
        day = session.exec(
            select(TripDay).where(
                TripDay.trip_id == UUID(trip_id),
                TripDay.day_number == 2,
            )
        ).one()
        assert day.day_type == "REST"
        assert day.start_time is None
        assert day.end_time is None


def test_full_day_can_change_to_half_day(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, engine = client_and_engine
    city = _create_city(client)
    trip = _create_trip(client, str(city["id"]), days=3)
    trip_id = str(trip["trip_id"])

    response = client.patch(
        f"/trips/{trip_id}/days/3",
        json={"day_type": "HALF_DAY", "start_time": "09:00:00", "end_time": "14:00:00"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["day_number"] == 3
    assert body["day_type"] == "HALF_DAY"
    assert body["start_time"] == "09:00:00"
    assert body["end_time"] == "14:00:00"


def test_full_day_can_change_to_travel_and_update_times(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, engine = client_and_engine
    city = _create_city(client)
    trip = _create_trip(client, str(city["id"]), days=3)
    trip_id = str(trip["trip_id"])

    response = client.patch(
        f"/trips/{trip_id}/days/1",
        json={"day_type": "TRAVEL", "start_time": "14:00:00", "end_time": "20:00:00"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["day_number"] == 1
    assert body["day_type"] == "TRAVEL"
    assert body["start_time"] == "14:00:00"
    assert body["end_time"] == "20:00:00"


def test_time_window_validation_rejects_inverted_times(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, _ = client_and_engine
    city = _create_city(client)
    trip = _create_trip(client, str(city["id"]), days=2)
    trip_id = str(trip["trip_id"])

    response = client.patch(
        f"/trips/{trip_id}/days/1",
        json={"start_time": "18:00:00", "end_time": "09:00:00"},
    )
    assert response.status_code == 422


def test_retrieving_trip_days_returns_ordered_list(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, _ = client_and_engine
    city = _create_city(client)
    trip = _create_trip(client, str(city["id"]), days=4)
    trip_id = str(trip["trip_id"])

    response = client.get(f"/trips/{trip_id}/days")
    assert response.status_code == 200
    days = response.json()
    assert len(days) == 4
    for idx, day in enumerate(days, start=1):
        assert day["day_number"] == idx
        assert day["day_type"] == "FULL_DAY"


def test_increasing_trip_duration_updates_trip_days_correctly(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, engine = client_and_engine
    city = _create_city(client)
    trip = _create_trip(
        client,
        str(city["id"]),
        days=3,
        start_date="2026-10-01",
        end_date="2026-10-03",
    )
    trip_id = str(trip["trip_id"])

    # First configure Day 2 as REST
    patch_day = client.patch(
        f"/trips/{trip_id}/days/2",
        json={"day_type": "REST"},
    )
    assert patch_day.status_code == 200

    # Increase trip from 3 to 5 days, shifting start date to 2026-10-10
    update_response = client.patch(
        f"/trips/{trip_id}",
        json={
            "start_date": "2026-10-10",
            "end_date": "2026-10-14",
            "days": 5,
        },
    )
    assert update_response.status_code == 200

    # Verify days: 5 total, Day 2 preserves REST, dates shifted
    get_days = client.get(f"/trips/{trip_id}/days")
    assert get_days.status_code == 200
    days = get_days.json()
    assert len(days) == 5

    assert days[0]["date"] == "2026-10-10"
    assert days[0]["day_type"] == "FULL_DAY"

    assert days[1]["date"] == "2026-10-11"
    assert days[1]["day_type"] == "REST"

    assert days[2]["date"] == "2026-10-12"
    assert days[2]["day_type"] == "FULL_DAY"

    assert days[3]["date"] == "2026-10-13"
    assert days[3]["day_type"] == "FULL_DAY"

    assert days[4]["date"] == "2026-10-14"
    assert days[4]["day_type"] == "FULL_DAY"


def test_reducing_trip_duration_without_itinerary_succeeds(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, engine = client_and_engine
    city = _create_city(client)
    trip = _create_trip(
        client,
        str(city["id"]),
        days=5,
        start_date="2026-10-01",
        end_date="2026-10-05",
    )
    trip_id = str(trip["trip_id"])

    # Reduce from 5 days to 3 days
    response = client.patch(
        f"/trips/{trip_id}",
        json={
            "start_date": "2026-10-01",
            "end_date": "2026-10-03",
            "days": 3,
        },
    )
    assert response.status_code == 200

    days_resp = client.get(f"/trips/{trip_id}/days")
    assert days_resp.status_code == 200
    days = days_resp.json()
    assert len(days) == 3
    assert [d["day_number"] for d in days] == [1, 2, 3]


def test_reducing_trip_duration_with_itinerary_visits_is_safely_prevented(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, engine = client_and_engine
    city = _create_city(client)
    trip = _create_trip(
        client,
        str(city["id"]),
        days=5,
        start_date="2026-10-01",
        end_date="2026-10-05",
    )
    trip_id = UUID(str(trip["trip_id"]))

    # Create a place and a planned itinerary visit on Day 5
    with Session(engine) as session:
        place = Place(
            city_id=UUID(str(city["id"])),
            name="Kashi Vishwanath Temple",
            category="religious",
            latitude=25.3109,
            longitude=83.0107,
        )
        session.add(place)
        session.flush()

        itinerary = TripItinerary(
            trip_id=trip_id,
            place_id=place.id,
            day_number=5,
            visit_order=1,
            planned_arrival_time=time(10, 0),
            planned_departure_time=time(11, 0),
        )
        session.add(itinerary)
        session.commit()

    # Attempt to reduce trip from 5 days to 3 days
    response = client.patch(
        f"/trips/{trip_id}",
        json={
            "start_date": "2026-10-01",
            "end_date": "2026-10-03",
            "days": 3,
        },
    )

    # Must be explicitly rejected with a helpful validation error
    assert response.status_code == 422
    assert "contains scheduled place visits" in response.json()["detail"]

    # Verify no TripDay rows were deleted
    with Session(engine) as session:
        days = session.exec(
            select(TripDay).where(TripDay.trip_id == trip_id)
        ).all()
        assert len(days) == 5


def test_legacy_trip_without_trip_days_is_auto_backfilled_on_retrieval(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, engine = client_and_engine
    city = _create_city(client)
    trip = _create_trip(client, str(city["id"]), days=3)
    trip_id = UUID(str(trip["trip_id"]))

    # Simulate legacy state by deleting TripDay records directly from DB
    with Session(engine) as session:
        from sqlalchemy import delete
        session.exec(delete(TripDay).where(TripDay.trip_id == trip_id))
        session.commit()

    # Retrieval should cleanly auto-backfill default days
    response = client.get(f"/trips/{trip_id}/days")
    assert response.status_code == 200
    days = response.json()
    assert len(days) == 3
    assert [d["day_number"] for d in days] == [1, 2, 3]
    assert all(d["day_type"] == "FULL_DAY" for d in days)


def test_itinerary_planning_still_works_with_trip_days(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, engine = client_and_engine
    city = _create_city(client)
    trip = _create_trip(client, str(city["id"]), days=2)
    trip_id = UUID(str(trip["trip_id"]))

    with Session(engine) as session:
        place = Place(
            city_id=UUID(str(city["id"])),
            name="Dashashwamedh Ghat",
            category="sightseeing",
            latitude=25.3076,
            longitude=83.0104,
        )
        session.add(place)
        session.flush()

        itinerary = TripItinerary(
            trip_id=trip_id,
            place_id=place.id,
            day_number=1,
            visit_order=1,
            planned_arrival_time=time(9, 30),
            planned_departure_time=time(11, 0),
            distance_from_previous=1200.0,
            travel_time_minutes=15,
        )
        session.add(itinerary)
        session.commit()

        # Check itinerary row persists and coexists with TripDay rows
        persisted = session.exec(
            select(TripItinerary).where(TripItinerary.trip_id == trip_id)
        ).all()
        assert len(persisted) == 1
        assert persisted[0].day_number == 1
        assert persisted[0].visit_order == 1

        trip_days = session.exec(
            select(TripDay).where(TripDay.trip_id == trip_id)
        ).all()
        assert len(trip_days) == 2

