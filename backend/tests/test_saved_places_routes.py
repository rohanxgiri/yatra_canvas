"""Route tests for persistent trip place customization."""

from collections.abc import Generator
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.engine import Engine
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine

from app.database import get_session
from app.main import app
from app.models import Trip


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


def create_city(client: TestClient) -> dict[str, object]:
    return client.post(
        "/cities",
        json={
            "name": "Ujjain",
            "state": "Madhya Pradesh",
            "country": "India",
            "latitude": 23.1765,
            "longitude": 75.7885,
            "google_place_id": f"google-ujjain-{uuid4()}",
        },
    ).json()


def create_place(
    client: TestClient,
    city_id: str,
    name: str,
) -> dict[str, object]:
    return client.post(
        "/places",
        json={
            "city_id": city_id,
            "name": name,
            "category": "religious",
            "latitude": 23.18,
            "longitude": 75.77,
            "rating": 4.7,
            "review_count": 1000,
            "is_popular": True,
            "is_heritage": False,
            "is_local_speciality": False,
            "last_fetched_at": None,
        },
    ).json()


def create_trip(engine: Engine, city_id: str) -> Trip:
    with Session(engine) as session:
        trip = Trip(
            user_id=uuid4(),
            city_id=UUID(city_id),
            trip_name="Ujjain spiritual trip",
            days=2,
        )
        session.add(trip)
        session.commit()
        session.refresh(trip)
        session.expunge(trip)
        return trip


def test_saved_place_add_list_notes_reorder_and_remove(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, engine = client_and_engine
    city = create_city(client)
    places = [
        create_place(client, str(city["id"]), name)
        for name in ["Place A", "Place B", "Place C"]
    ]
    trip = create_trip(engine, str(city["id"]))
    path = f"/trips/{trip.id}/saved-places"

    assert client.get(path).json() == []

    first = client.post(
        path,
        json={
            "place_id": places[0]["id"],
            "custom_order": 1,
            "notes": "  Arrive early  ",
        },
    )
    assert first.status_code == 201
    assert first.json()["notes"] == "Arrive early"
    assert first.json()["place"]["name"] == "Place A"

    second = client.post(
        path,
        json={"place_id": places[1]["id"], "custom_order": 1, "notes": None},
    )
    assert second.status_code == 201
    assert second.json()["custom_order"] == 1

    third = client.post(
        path,
        json={"place_id": places[2]["id"], "notes": None},
    )
    assert third.status_code == 201
    assert third.json()["custom_order"] == 3

    duplicate = client.post(
        path,
        json={"place_id": places[0]["id"], "notes": None},
    )
    assert duplicate.status_code == 409

    listed = client.get(path)
    assert listed.status_code == 200
    assert [item["place"]["name"] for item in listed.json()] == [
        "Place B",
        "Place A",
        "Place C",
    ]
    assert [item["custom_order"] for item in listed.json()] == [1, 2, 3]

    notes = client.patch(
        f"{path}/{places[0]['id']}",
        json={"notes": "Morning darshan"},
    )
    assert notes.status_code == 200
    assert notes.json()["notes"] == "Morning darshan"

    reordered = client.patch(
        f"{path}/reorder",
        json={
            "places": [
                {"place_id": places[2]["id"], "custom_order": 1},
                {"place_id": places[0]["id"], "custom_order": 2},
                {"place_id": places[1]["id"], "custom_order": 3},
            ]
        },
    )
    assert reordered.status_code == 200
    assert [item["place"]["name"] for item in reordered.json()] == [
        "Place C",
        "Place A",
        "Place B",
    ]

    removed = client.delete(f"{path}/{places[0]['id']}")
    assert removed.status_code == 204
    remaining = client.get(path).json()
    assert [item["place"]["name"] for item in remaining] == [
        "Place C",
        "Place B",
    ]
    assert [item["custom_order"] for item in remaining] == [1, 2]


def test_saved_place_validation_and_not_found_responses(
    client_and_engine: tuple[TestClient, Engine],
) -> None:
    client, engine = client_and_engine
    city = create_city(client)
    first_place = create_place(client, str(city["id"]), "Place A")
    second_place = create_place(client, str(city["id"]), "Place B")
    third_place = create_place(client, str(city["id"]), "Place C")
    trip = create_trip(engine, str(city["id"]))
    path = f"/trips/{trip.id}/saved-places"

    missing_trip = client.post(
        f"/trips/{uuid4()}/saved-places",
        json={"place_id": first_place["id"], "notes": None},
    )
    assert missing_trip.status_code == 404

    missing_place = client.post(
        path,
        json={"place_id": str(uuid4()), "notes": None},
    )
    assert missing_place.status_code == 404

    assert client.delete(f"{path}/{first_place['id']}").status_code == 404
    assert client.post(
        path,
        json={"place_id": first_place["id"], "notes": None},
    ).status_code == 201
    assert client.post(
        path,
        json={"place_id": second_place["id"], "notes": None},
    ).status_code == 201

    incomplete_reorder = client.patch(
        f"{path}/reorder",
        json={
            "places": [
                {"place_id": first_place["id"], "custom_order": 1},
            ]
        },
    )
    assert incomplete_reorder.status_code == 400

    duplicate_order = client.patch(
        f"{path}/reorder",
        json={
            "places": [
                {"place_id": first_place["id"], "custom_order": 1},
                {"place_id": second_place["id"], "custom_order": 1},
            ]
        },
    )
    assert duplicate_order.status_code == 422

    skipped_insert_order = client.post(
        path,
        json={"place_id": third_place["id"], "custom_order": 4, "notes": None},
    )
    assert skipped_insert_order.status_code == 400
