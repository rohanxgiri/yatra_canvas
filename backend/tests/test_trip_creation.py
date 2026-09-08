"""Trip creation API and transactional persistence tests."""

from collections.abc import Generator
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import event
from sqlalchemy.engine import Engine
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.database import get_session
from app.main import app
from app.models import Trip, TripPreference
from app.schemas import TripCreate
from app.services.trip_service import DEVELOPMENT_USER_ID, TripService


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
            "name": "Ujjain",
            "state": "Madhya Pradesh",
            "country": "India",
            "latitude": 23.1765,
            "longitude": 75.7885,
            "google_place_id": f"trip-city-{uuid4()}",
        },
    )
    assert response.status_code == 201
    return response.json()


def _payload(city_id: str) -> dict[str, object]:
    return {
        "city_id": city_id,
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
    }


def test_create_trip_returns_id_and_persists_trip_and_preferences(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, engine = client_and_engine
    city = _create_city(client)

    response = client.post("/trips", json=_payload(str(city["id"])))

    assert response.status_code == 201
    body = response.json()
    trip_id = UUID(body["trip_id"])
    assert body["city_id"] == city["id"]
    assert body["trip_name"] == "Ujjain trip"
    assert body["days"] == 3
    assert body["start_date"] == "2026-09-10"
    assert body["start_location_type"] == "hotel"
    assert body["start_location_provider_place_id"] == ("geoapify-hotel-imperial")
    assert body["preferences"] == [
        "Religious / Spiritual",
        "Culture & Heritage",
        "Balanced",
        "Chill",
        "Walking",
        "Auto / Cab",
    ]
    assert "user_id" not in body

    with Session(engine) as session:
        trip = session.get(Trip, trip_id)
        assert trip is not None
        assert trip.user_id == DEVELOPMENT_USER_ID
        assert trip.arrival_place == "Ujjain Railway Station"
        assert trip.start_location_name == "Hotel Imperial"
        preferences = session.exec(
            select(TripPreference).where(TripPreference.trip_id == trip_id)
        ).all()
        purpose_prefs = {"Religious / Spiritual", "Culture & Heritage"}
        assert all(
            row.weight == 2.0 if row.preference in purpose_prefs else row.weight == 1.0
            for row in preferences
        )


def test_create_trip_reuses_request_id_without_duplicate_rows(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, engine = client_and_engine
    city = _create_city(client)
    request_id = str(uuid4())
    payload = {**_payload(str(city["id"])), "request_id": request_id}

    first = client.post("/trips", json=payload)
    retry = client.post("/trips", json=payload)

    assert first.status_code == 201
    assert retry.status_code == 201
    assert first.json()["trip_id"] == request_id
    assert retry.json()["trip_id"] == request_id
    with Session(engine) as session:
        assert len(session.exec(select(Trip)).all()) == 1


def test_create_trip_rejects_reused_request_id_with_different_data(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, _ = client_and_engine
    city = _create_city(client)
    request_id = str(uuid4())
    payload = {**_payload(str(city["id"])), "request_id": request_id}
    assert client.post("/trips", json=payload).status_code == 201

    conflict = client.post(
        "/trips",
        json={**payload, "arrival_place": "Different station"},
    )

    assert conflict.status_code == 422
    assert "already used" in conflict.json()["detail"]


def test_create_trip_accepts_arrival_label_without_coordinates(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, engine = client_and_engine
    city = _create_city(client)
    payload = {
        **_payload(str(city["id"])),
        "arrival_latitude": None,
        "arrival_longitude": None,
        "start_location_type": "arrival",
        "start_location_name": None,
        "start_latitude": None,
        "start_longitude": None,
        "start_location_provider": None,
        "start_location_provider_place_id": None,
    }

    response = client.post("/trips", json=payload)

    assert response.status_code == 201
    body = response.json()
    assert body["start_location_name"] == "Ujjain Railway Station"
    assert body["start_latitude"] is None
    assert body["start_longitude"] is None
    with Session(engine) as session:
        trip = session.get(Trip, UUID(body["trip_id"]))
        assert trip is not None
        assert trip.start_location_type == "arrival"
        assert trip.start_location_name == "Ujjain Railway Station"


def test_create_trip_rejects_unknown_city(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, _ = client_and_engine

    response = client.post("/trips", json=_payload(str(uuid4())))

    assert response.status_code == 404
    assert response.json() == {"detail": "City not found."}


@pytest.mark.parametrize(
    "changes",
    [
        {"days": 0},
        {"start_date": "2026-09-12", "end_date": "2026-09-10"},
        {"days": 2},
    ],
)
def test_create_trip_rejects_invalid_dates_and_days(
    client_and_engine: tuple[TestClient, Engine],
    changes: dict[str, object],
) -> None:
    client, _ = client_and_engine
    city = _create_city(client)

    response = client.post(
        "/trips",
        json={**_payload(str(city["id"])), **changes},
    )

    assert response.status_code == 422


@pytest.mark.parametrize(
    "changes",
    [
        {"arrival_longitude": None},
        {"start_latitude": 91},
        {
            "start_location_type": "custom",
            "start_latitude": None,
            "start_longitude": None,
        },
        {"start_location_provider_place_id": None},
    ],
)
def test_create_trip_rejects_invalid_coordinates_and_location_pairs(
    client_and_engine: tuple[TestClient, Engine],
    changes: dict[str, object],
) -> None:
    client, _ = client_and_engine
    city = _create_city(client)

    response = client.post(
        "/trips",
        json={**_payload(str(city["id"])), **changes},
    )

    assert response.status_code == 422


def test_create_trip_rolls_back_when_preference_insert_fails(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, engine = client_and_engine
    city = _create_city(client)
    request = TripCreate.model_validate(_payload(str(city["id"])))

    def fail_preference_insert(*_: object) -> None:
        raise RuntimeError("controlled preference failure")

    event.listen(TripPreference, "before_insert", fail_preference_insert)
    try:
        with Session(engine) as session:
            with pytest.raises(RuntimeError, match="controlled preference failure"):
                TripService().create(session, request)
    finally:
        event.remove(TripPreference, "before_insert", fail_preference_insert)

    with Session(engine) as session:
        assert session.exec(select(Trip)).all() == []
        assert session.exec(select(TripPreference)).all() == []


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("id", str(uuid4())),
        ("trip_id", str(uuid4())),
        ("user_id", str(uuid4())),
        ("created_at", "2026-09-01T00:00:00Z"),
    ],
)
def test_create_trip_rejects_server_owned_fields(
    client_and_engine: tuple[TestClient, Engine],
    field: str,
    value: str,
) -> None:
    client, engine = client_and_engine
    city = _create_city(client)

    response = client.post(
        "/trips",
        json={**_payload(str(city["id"])), field: value},
    )

    assert response.status_code == 422
    with Session(engine) as session:
        assert session.exec(select(Trip)).all() == []
