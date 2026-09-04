"""End-to-end route smoke tests using an isolated in-memory database."""

from collections.abc import Generator
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine

from app.database import get_session
from app.main import app
from app.routers.cities import get_geoapify_service
from app.routers.places import (
    get_audiala_places_provider,
    get_geoapify_places_provider,
    get_openstreetmap_places_service,
)
from app.schemas import (
    CitySuggestion,
    CityDetails,
    DiscoveryCategory,
)
from app.services.audiala_places_provider import AudialaPlacesProvider
from app.services.geoapify_places_provider import GeoapifyPlacesProvider
from app.services.geoapify_service import (
    GeoapifyConfigurationError,
    GeoapifyService,
    LocationAutocompleteResult,
)
from app.services.openstreetmap_places_service import OpenStreetMapNearbyPlace


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
    app.dependency_overrides[get_audiala_places_provider] = (
        lambda: AudialaPlacesProvider(None)
    )
    app.dependency_overrides[get_geoapify_places_provider] = (
        lambda: GeoapifyPlacesProvider(None)
    )
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
        "provider_place_id": "example_provider_place_id",
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


def test_resolve_city_without_provider_place_id_creates_once(
    client: TestClient,
) -> None:
    payload = {
        "name": "Udaipur",
        "state": "Rajasthan",
        "country": "India",
        "latitude": 24.578721,
        "longitude": 73.6862571,
        "provider_place_id": None,
    }
    first = client.post(
        "/cities/resolve",
        json=payload,
    )
    second = client.post("/cities/resolve", json=payload)

    assert first.status_code == 200
    assert second.status_code == 200
    assert second.json() == first.json()
    assert client.get("/cities/search", params={"query": "udaipur"}).json() == [
        first.json()
    ]


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


class FakeGeoapifyService:
    async def autocomplete(self, query: str, location_type: str, country_code: str) -> list[LocationAutocompleteResult]:
        assert query == "gandhi"
        return [
            LocationAutocompleteResult(
                provider="geoapify",
                provider_place_id="geoapify-gandhinagar",
                name="Gandhinagar",
                formatted_address="Gandhinagar, Gujarat, India",
                latitude=23.2156,
                longitude=72.6369,
                city="Gandhinagar",
                state="Gujarat",
                country_code="in",
                result_type="city",
            )
        ]

    async def get_place_details(self, provider_place_id: str) -> LocationAutocompleteResult | None:
        if provider_place_id == "missing-place":
            return None
        assert provider_place_id == "geoapify-gandhinagar"
        return LocationAutocompleteResult(
            provider="geoapify",
            provider_place_id="geoapify-gandhinagar",
            name="Gandhinagar",
            formatted_address="Gandhinagar, Gujarat, India",
            latitude=23.2156,
            longitude=72.6369,
            city="Gandhinagar",
            state="Gujarat",
            country_code="in",
            result_type="city",
        )


class FakeOpenStreetMapPlacesService:
    def __init__(self) -> None:
        self.call_counts = {
            "religious": 0,
            "food": 0,
            "heritage": 0,
        }

    async def search_nearby_places(
        self,
        *,
        latitude: float,
        longitude: float,
        category: DiscoveryCategory,
        limit: int = 40,
    ) -> list[OpenStreetMapNearbyPlace]:
        assert latitude == 23.1765
        assert longitude == 75.7885
        assert limit == 40

        if category is DiscoveryCategory.RELIGIOUS:
            category_name = "religious"
            places = [
                OpenStreetMapNearbyPlace(
                    external_place_id="node/1001",
                    source_url="https://www.openstreetmap.org/node/1001",
                    name="Mahakaleshwar Temple",
                    latitude=23.1828,
                    longitude=75.7682,
                    tags={"amenity": "place_of_worship"},
                )
            ]
        elif category is DiscoveryCategory.FOOD:
            category_name = "food"
            places = [
                OpenStreetMapNearbyPlace(
                    external_place_id="node/1002",
                    source_url="https://www.openstreetmap.org/node/1002",
                    name="Ujjain Food Street",
                    latitude=23.179,
                    longitude=75.781,
                    tags={"amenity": "restaurant"},
                )
            ]
        else:
            assert category is DiscoveryCategory.HERITAGE
            category_name = "heritage"
            places = [
                OpenStreetMapNearbyPlace(
                    external_place_id="node/1001",
                    source_url="https://www.openstreetmap.org/node/1001",
                    name="Mahakaleshwar Temple",
                    latitude=23.1828,
                    longitude=75.7682,
                    tags={"historic": "temple"},
                )
            ]

        self.call_counts[category_name] += 1
        return places


def test_geoapify_city_autocomplete_and_place_details(client: TestClient) -> None:
    app.dependency_overrides[get_geoapify_service] = FakeGeoapifyService

    autocomplete = client.get("/cities/autocomplete", params={"query": "gandhi"})
    assert autocomplete.status_code == 200
    assert autocomplete.json() == [
        {
            "provider_place_id": "geoapify-gandhinagar",
            "name": "Gandhinagar",
            "description": "Gandhinagar, Gujarat, India",
        }
    ]

    details = client.get("/cities/place-details/geoapify-gandhinagar")
    assert details.status_code == 200
    assert details.json() == {
        "name": "Gandhinagar",
        "state": "Gujarat",
        "country": "India",
        "latitude": 23.2156,
        "longitude": 72.6369,
        "google_place_id": None,
        "provider_place_id": "geoapify-gandhinagar",
    }

    missing = client.get("/cities/place-details/missing-place")
    assert missing.status_code == 404
    assert missing.json() == {"detail": "Provider place could not be found."}


def test_missing_geoapify_key_returns_safe_api_response(client: TestClient) -> None:
    app.dependency_overrides[get_geoapify_service] = lambda: GeoapifyService(
        None
    )

    response = client.get("/cities/autocomplete", params={"query": "Ujjain"})

    assert response.status_code == 503
    assert response.json() == {
        "detail": "Location autocomplete is not configured on the backend."
    }
    assert "GEOAPIFY_API_KEY" not in response.text


@pytest.mark.parametrize("query", [None, "", "a", "   "])
def test_geoapify_city_autocomplete_validates_query(
    client: TestClient, query: str | None
) -> None:
    params = {} if query is None else {"query": query}
    assert client.get("/cities/autocomplete", params=params).status_code == 422


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
            "provider_place_id": None,
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
    assert (
        client.post("/places", json={**payload, "city_id": missing_city}).status_code
        == 404
    )
    assert client.get(f"/cities/{missing_city}/places").status_code == 404


def test_discover_places_persists_and_uses_fresh_cache(
    client: TestClient,
) -> None:
    fake_osm = FakeOpenStreetMapPlacesService()
    app.dependency_overrides[get_openstreetmap_places_service] = lambda: fake_osm
    city = client.post(
        "/cities",
        json={
            "name": "Ujjain",
            "state": "Madhya Pradesh",
            "country": "India",
            "latitude": 23.1765,
            "longitude": 75.7885,
            "google_place_id": None,
            "provider_place_id": "google-ujjain",
        },
    ).json()

    path = f"/cities/{city['id']}/discover-places"
    first = client.get(path, params={"category": "religious"})
    assert first.status_code == 200
    assert len(first.json()) == 1
    assert first.json()[0] == {
        "id": first.json()[0]["id"],
        "city_id": city["id"],
        "name": "Mahakaleshwar Temple",
        "category": "religious",
        "latitude": 23.1828,
        "longitude": 75.7682,
        "rating": None,
        "review_count": 0,
        "is_popular": False,
        "is_heritage": False,
        "is_local_speciality": False,
        "wikidata_id": None,
        "importance_score": None,
        "last_fetched_at": first.json()[0]["last_fetched_at"],
        "created_at": first.json()[0]["created_at"],
    }

    second = client.get(path, params={"category": "religious"})
    assert second.status_code == 200
    assert second.json() == first.json()
    assert fake_osm.call_counts["religious"] == 1

    heritage = client.get(path, params={"category": "heritage"})
    assert heritage.status_code == 200
    assert heritage.json()[0]["id"] == first.json()[0]["id"]
    assert heritage.json()[0]["is_heritage"] is True
    assert fake_osm.call_counts["heritage"] == 1

    stored = client.get(f"/cities/{city['id']}/places")
    assert stored.status_code == 200
    assert len(stored.json()) == 1


def test_discover_places_validates_city_and_category(client: TestClient) -> None:
    missing_city = uuid4()
    missing = client.get(
        f"/cities/{missing_city}/discover-places",
        params={"category": "religious"},
    )
    assert missing.status_code == 404

    city = client.post(
        "/cities",
        json={
            "name": "Ujjain",
            "state": "Madhya Pradesh",
            "country": "India",
            "latitude": 23.1765,
            "longitude": 75.7885,
            "google_place_id": "google-ujjain-validation",
        },
    ).json()
    invalid = client.get(
        f"/cities/{city['id']}/discover-places",
        params={"category": "shopping"},
    )
    assert invalid.status_code == 422


def test_recommendations_reuse_each_category_cache_deduplicate_and_rank(
    client: TestClient,
) -> None:
    fake_osm = FakeOpenStreetMapPlacesService()
    app.dependency_overrides[get_openstreetmap_places_service] = lambda: fake_osm
    city = client.post(
        "/cities",
        json={
            "name": "Ujjain",
            "state": "Madhya Pradesh",
            "country": "India",
            "latitude": 23.1765,
            "longitude": 75.7885,
            "google_place_id": "google-ujjain-recommendations",
        },
    ).json()
    recommendation_path = f"/cities/{city['id']}/recommendations"

    payload = {
        "categories": ["religious", "food", "heritage"],
        "limit": 30,
    }
    first = client.post(recommendation_path, json=payload)
    assert first.status_code == 200
    assert [item["name"] for item in first.json()] == [
        "Mahakaleshwar Temple",
        "Ujjain Food Street",
    ]
    assert first.json()[0]["matched_categories"] == [
        "religious",
        "heritage",
    ]
    assert (
        first.json()[0]["recommendation_score"]
        > first.json()[1]["recommendation_score"]
    )
    assert fake_osm.call_counts == {
        "religious": 1,
        "food": 1,
        "heritage": 1,
    }

    second = client.post(recommendation_path, json=payload)
    assert second.status_code == 200
    assert second.json() == first.json()
    assert fake_osm.call_counts == {
        "religious": 1,
        "food": 1,
        "heritage": 1,
    }


@pytest.mark.parametrize(
    "payload",
    [
        {"categories": [], "limit": 30},
        {"categories": ["shopping"], "limit": 30},
        {"categories": ["religious"], "limit": 0},
        {"categories": ["religious"], "limit": 101},
    ],
)
def test_recommendations_validate_request(
    client: TestClient,
    payload: dict[str, object],
) -> None:
    city = client.post(
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
    response = client.post(
        f"/cities/{city['id']}/recommendations",
        json=payload,
    )
    assert response.status_code == 422


def test_recommendations_require_existing_city(client: TestClient) -> None:
    response = client.post(
        f"/cities/{uuid4()}/recommendations",
        json={"categories": ["religious"], "limit": 30},
    )
    assert response.status_code == 404
    assert response.json() == {"detail": "City not found."}


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
