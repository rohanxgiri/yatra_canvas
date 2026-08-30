"""End-to-end route smoke tests using an isolated in-memory database."""

from collections.abc import Generator
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine

from app.database import get_session
from app.main import app


@pytest.fixture
def client() -> Generator[TestClient, None, None]:
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
    test_client = TestClient(app)
    yield test_client
    test_client.close()
    app.dependency_overrides.clear()
    SQLModel.metadata.drop_all(engine)


def test_status_route(client: TestClient) -> None:
    response = client.get("/")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "service": "YatraCanvas API"}


@pytest.mark.parametrize(
    "path", ["/openapi.json", "/docs", "/docs/oauth2-redirect", "/redoc"]
)
def test_generated_documentation_routes(client: TestClient, path: str) -> None:
    assert client.get(path).status_code == 200


def test_city_routes(client: TestClient) -> None:
    payload = {
        "name": "Jaipur",
        "state": "Rajasthan",
        "country": "India",
        "latitude": 26.9124,
        "longitude": 75.7873,
        "google_place_id": None,
    }

    created = client.post("/cities", json=payload)
    assert created.status_code == 201
    city = created.json()

    listed = client.get("/cities", params={"offset": 0, "limit": 100})
    assert listed.status_code == 200
    assert [item["id"] for item in listed.json()] == [city["id"]]

    fetched = client.get(f"/cities/{city['id']}")
    assert fetched.status_code == 200
    assert fetched.json() == city

    missing = client.get(f"/cities/{uuid4()}")
    assert missing.status_code == 404
    assert missing.json() == {"detail": "City not found."}


def test_resolve_city_creates_once_and_returns_existing(client: TestClient) -> None:
    payload = {
        "name": "Gandhinagar",
        "state": "Gujarat",
        "country": "India",
        "latitude": 23.2156,
        "longitude": 72.6369,
        "google_place_id": "example_google_place_id",
    }

    first = client.post("/cities/resolve", json=payload)
    assert first.status_code == 200

    second = client.post(
        "/cities/resolve",
        json={**payload, "name": "This value must not replace the stored city"},
    )
    assert second.status_code == 200
    assert second.json() == first.json()

    listed = client.get("/cities")
    assert listed.status_code == 200
    assert len(listed.json()) == 1


@pytest.mark.parametrize("google_place_id", [None, "", "   "])
def test_resolve_city_requires_google_place_id(
    client: TestClient, google_place_id: str | None
) -> None:
    response = client.post(
        "/cities/resolve",
        json={
            "name": "Gandhinagar",
            "state": "Gujarat",
            "country": "India",
            "latitude": 23.2156,
            "longitude": 72.6369,
            "google_place_id": google_place_id,
        },
    )

    assert response.status_code == 422


def test_search_cities_matches_name_and_state_case_insensitively(
    client: TestClient,
) -> None:
    cities = [
        {
            "name": "Gandhinagar",
            "state": "Gujarat",
            "country": "India",
            "latitude": 23.2156,
            "longitude": 72.6369,
            "google_place_id": "gandhinagar-gujarat",
        },
        {
            "name": "Ahmedabad",
            "state": "Gujarat",
            "country": "India",
            "latitude": 23.0225,
            "longitude": 72.5714,
            "google_place_id": "ahmedabad-gujarat",
        },
        {
            "name": "Mumbai",
            "state": "Maharashtra",
            "country": "India",
            "latitude": 19.076,
            "longitude": 72.8777,
            "google_place_id": "mumbai-maharashtra",
        },
    ]
    for city in cities:
        assert client.post("/cities/resolve", json=city).status_code == 200

    name_match = client.get("/cities/search", params={"query": "GANDHI"})
    assert name_match.status_code == 200
    assert [city["name"] for city in name_match.json()] == ["Gandhinagar"]

    state_match = client.get("/cities/search", params={"query": "guja"})
    assert state_match.status_code == 200
    assert [city["name"] for city in state_match.json()] == [
        "Ahmedabad",
        "Gandhinagar",
    ]

    no_match = client.get("/cities/search", params={"query": "Chennai"})
    assert no_match.status_code == 200
    assert no_match.json() == []


@pytest.mark.parametrize("query", [None, "", "   "])
def test_search_cities_requires_non_blank_query(
    client: TestClient, query: str | None
) -> None:
    params = {} if query is None else {"query": query}
    assert client.get("/cities/search", params=params).status_code == 422


def test_place_routes(client: TestClient) -> None:
    city = client.post(
        "/cities",
        json={
            "name": "Ujjain",
            "state": "Madhya Pradesh",
            "country": "India",
            "latitude": 23.1765,
            "longitude": 75.7885,
            "google_place_id": None,
        },
    ).json()
    payload = {
        "city_id": city["id"],
        "name": "Mahakaleshwar Temple",
        "category": "heritage",
        "latitude": 23.1828,
        "longitude": 75.7682,
        "rating": 4.8,
        "review_count": 15000,
        "is_popular": True,
        "is_heritage": True,
        "is_local_speciality": False,
        "last_fetched_at": None,
    }

    created = client.post("/places", json=payload)
    assert created.status_code == 201
    place = created.json()

    listed = client.get(
        f"/cities/{city['id']}/places", params={"offset": 0, "limit": 100}
    )
    assert listed.status_code == 200
    assert listed.json() == [place]

    missing_city = str(uuid4())
    assert client.post(
        "/places", json={**payload, "city_id": missing_city}
    ).status_code == 404
    assert client.get(f"/cities/{missing_city}/places").status_code == 404


@pytest.mark.parametrize(
    ("path", "params"),
    [
        ("/cities", {"offset": -1}),
        ("/cities", {"limit": 0}),
        ("/cities", {"limit": 501}),
        (f"/cities/{uuid4()}/places", {"offset": -1}),
    ],
)
def test_list_route_query_validation(
    client: TestClient, path: str, params: dict[str, int]
) -> None:
    assert client.get(path, params=params).status_code == 422
