"""Core trip flow hardening tests:
- Multi-day day-sequence integrity
- Destination-scoped manual place search
- Canonical place resolution and duplicate prevention
- Route optimization with manually added places
"""

from collections.abc import Generator
from datetime import datetime, timezone
from unittest.mock import AsyncMock, patch
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.engine import Engine
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.database import get_session
from app.main import app
from app.models import City, Place, Trip, UserSavedPlace
from app.routers.route_optimization import get_route_provider
from app.services.google_routes_service import RouteCoordinate, RouteMatrixLeg
from app.services.local_routes_service import LocalRoutesService


class MockRoutesService(LocalRoutesService):
    async def compute_matrix(
        self,
        origins: list[RouteCoordinate],
        destinations: list[RouteCoordinate],
    ) -> dict[tuple[int, int], RouteMatrixLeg]:
        result: dict[tuple[int, int], RouteMatrixLeg] = {}
        for i, origin in enumerate(origins):
            for j, dest in enumerate(destinations):
                dist = int(abs(origin.latitude - dest.latitude) * 111000 + abs(origin.longitude - dest.longitude) * 111000)
                dur = max(60, dist // 10)
                result[(i, j)] = RouteMatrixLeg(
                    distance_meters=dist,
                    static_duration_seconds=dur,
                    traffic_duration_seconds=dur,
                )
        return result


@pytest.fixture
def test_env() -> Generator[tuple[TestClient, Session, City, Trip], None, None]:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)

    with Session(engine) as session:
        city = City(
            id=uuid4(),
            name="Kochi",
            state="Kerala",
            country="India",
            latitude=9.9312,
            longitude=76.2673,
        )
        session.add(city)

        trip = Trip(
            id=uuid4(),
            user_id=uuid4(),
            city_id=city.id,
            trip_name="Kochi Trip",
            days=3,
            start_date=datetime(2026, 9, 10, tzinfo=timezone.utc),
            end_date=datetime(2026, 9, 12, tzinfo=timezone.utc),
            start_location_type="hotel",
            start_location_name="Grand Hyatt Kochi",
            start_latitude=9.9816,
            start_longitude=76.2758,
        )
        session.add(trip)
        session.commit()
        session.refresh(city)
        session.refresh(trip)

    def override_session() -> Generator[Session, None, None]:
        with Session(engine) as s:
            yield s

    app.dependency_overrides[get_session] = override_session
    app.dependency_overrides[get_route_provider] = lambda: MockRoutesService()
    client = TestClient(app)

    with Session(engine) as session:
        yield client, session, city, trip

    client.close()
    app.dependency_overrides.clear()
    SQLModel.metadata.drop_all(engine)


def test_route_optimization_preserves_total_days_and_handles_sparse_schedule(
    test_env: tuple[TestClient, Session, City, Trip],
) -> None:
    client, session, city, trip = test_env

    # Create 3 places in Kochi
    p1 = Place(
        id=uuid4(),
        city_id=city.id,
        name="Mattancherry Palace",
        category="heritage",
        latitude=9.9583,
        longitude=76.2592,
    )
    p2 = Place(
        id=uuid4(),
        city_id=city.id,
        name="Santa Cruz Cathedral",
        category="religious",
        latitude=9.9647,
        longitude=76.2415,
    )
    p3 = Place(
        id=uuid4(),
        city_id=city.id,
        name="Fort Kochi Beach",
        category="nature",
        latitude=9.9667,
        longitude=76.2425,
    )
    session.add_all([p1, p2, p3])
    session.commit()

    # Save to trip
    for idx, p in enumerate([p1, p2, p3]):
        saved = UserSavedPlace(
            trip_id=trip.id,
            place_id=p.id,
            custom_order=idx + 1,
            priority=1,
            is_locked=False,
            must_visit=False,
        )
        session.add(saved)
    session.commit()

    # Test 3-day trip
    response = client.post(f"/trips/{trip.id}/optimize-route")
    assert response.status_code == 200, response.text
    data = response.json()

    assert data["total_days"] == 3
    assert "optimized_places" in data
    # Check that day numbers are valid and <= total_days
    for place_item in data["optimized_places"]:
        assert 1 <= place_item["day_number"] <= 3


def test_multi_day_lengths_1_2_3_5_7_days(
    test_env: tuple[TestClient, Session, City, Trip],
) -> None:
    client, session, city, trip = test_env

    # Add 7 places so each day count from 1 to 7 satisfies the minimum places constraint
    places = [
        Place(
            id=uuid4(),
            city_id=city.id,
            name=f"Place {i}",
            category="tourism",
            latitude=9.93 + i * 0.005,
            longitude=76.25 + i * 0.005,
        )
        for i in range(7)
    ]
    session.add_all(places)
    session.commit()

    for idx, p in enumerate(places):
        session.add(
            UserSavedPlace(
                trip_id=trip.id,
                place_id=p.id,
                custom_order=idx + 1,
            )
        )
    session.commit()

    for days in [1, 2, 3, 5, 7]:
        trip.days = days
        session.add(trip)
        session.commit()

        resp = client.post(f"/trips/{trip.id}/optimize-route")
        assert resp.status_code == 200
        result = resp.json()
        assert result["total_days"] == days
        for p in result["optimized_places"]:
            assert 1 <= p["day_number"] <= days


def test_manual_place_search_destination_scoped(
    test_env: tuple[TestClient, Session, City, Trip],
) -> None:
    client, session, city, trip = test_env

    # Insert a place in local DB
    local_museum = Place(
        id=uuid4(),
        city_id=city.id,
        name="Indo-Portuguese Museum",
        category="heritage",
        latitude=9.9634,
        longitude=76.2429,
    )
    session.add(local_museum)
    session.commit()

    # Search without Geoapify API key / fallback
    resp = client.get(f"/cities/{city.id}/places/search?query=Portuguese")
    assert resp.status_code == 200
    results = resp.json()
    assert len(results) >= 1
    match = next((r for r in results if "Indo-Portuguese" in r["name"]), None)
    assert match is not None
    assert match["place_id"] == str(local_museum.id)
    assert match["category"] == "heritage"
    assert match["distance_meters"] is not None


def test_manual_place_search_deduplicates_against_local_db(
    test_env: tuple[TestClient, Session, City, Trip],
) -> None:
    client, session, city, trip = test_env

    local_place = Place(
        id=uuid4(),
        city_id=city.id,
        name="Hill Palace Museum",
        category="heritage",
        latitude=9.9535,
        longitude=76.3639,
    )
    session.add(local_place)
    session.commit()

    # Mock Geoapify autocomplete returning the same place plus an external place
    from app.schemas.location import LocationAutocompleteResult

    mock_geo_results = [
        LocationAutocompleteResult(
            provider="geoapify",
            provider_place_id="geoapify_hill_palace",
            name="Hill Palace Museum",
            formatted_address="Hill Palace Rd, Tripunithura, Kochi",
            latitude=9.9535,
            longitude=76.3639,
            city="Kochi",
            state="Kerala",
            country_code="in",
            result_type="amenity",
        ),
        LocationAutocompleteResult(
            provider="geoapify",
            provider_place_id="geoapify_folklore",
            name="Kerala Folklore Museum",
            formatted_address="Thevara, Kochi",
            latitude=9.9320,
            longitude=76.3050,
            city="Kochi",
            state="Kerala",
            country_code="in",
            result_type="amenity",
        ),
    ]

    with patch("app.services.geoapify_service.GeoapifyService.autocomplete", new_callable=AsyncMock) as mock_auto:
        mock_auto.return_value = mock_geo_results

        with patch("app.routers.places.get_settings") as mock_settings:
            settings_mock = mock_settings.return_value
            settings_mock.geoapify_api_key = "test_key"

            resp = client.get(f"/cities/{city.id}/places/search?query=Museum")
            assert resp.status_code == 200
            data = resp.json()

            # Hill Palace should only appear once (deduplicated against local DB)
            hill_palace_items = [d for d in data if "Hill Palace" in d["name"]]
            assert len(hill_palace_items) == 1
            assert hill_palace_items[0]["place_id"] == str(local_place.id)

            # Folklore museum should appear from external provider
            folklore_items = [d for d in data if "Folklore" in d["name"]]
            assert len(folklore_items) == 1
            assert folklore_items[0]["external_place_id"] == "geoapify_folklore"


def test_manual_place_resolve_and_add_to_route(
    test_env: tuple[TestClient, Session, City, Trip],
) -> None:
    client, session, city, trip = test_env

    # 1. Resolve an external search result
    resolve_payload = {
        "name": "Cherai Beach",
        "latitude": 10.1416,
        "longitude": 76.1783,
        "category": "nature",
        "address": "Cherai, Vypin Island, Kochi",
        "external_place_id": "geoapify_cherai_beach",
        "source": "geoapify",
    }

    resolve_resp = client.post(f"/cities/{city.id}/places/resolve", json=resolve_payload)
    assert resolve_resp.status_code == 200, resolve_resp.text
    resolved_place = resolve_resp.json()
    place_id = resolved_place["id"]
    assert resolved_place["name"] == "Cherai Beach"

    # 2. Add to saved places
    save_resp = client.post(f"/trips/{trip.id}/saved-places", json={"place_id": place_id})
    assert save_resp.status_code == 201, save_resp.text

    # Set trip.days = 2 and add a second place so 2 places satisfy 2 days
    trip.days = 2
    session.add(trip)
    session.commit()

    p2 = Place(
        id=uuid4(),
        city_id=city.id,
        name="Fort Kochi Promenade",
        category="tourism",
        latitude=9.965,
        longitude=76.243,
    )
    session.add(p2)
    session.commit()
    client.post(f"/trips/{trip.id}/saved-places", json={"place_id": str(p2.id)})

    # 3. Optimize route and verify manual place is in the itinerary
    opt_resp = client.post(f"/trips/{trip.id}/optimize-route")
    assert opt_resp.status_code == 200
    opt_data = opt_resp.json()
    place_ids_in_route = [p["place_id"] for p in opt_data["optimized_places"]]
    assert place_id in place_ids_in_route


def test_manual_place_resolve_duplicate_returns_existing(
    test_env: tuple[TestClient, Session, City, Trip],
) -> None:
    client, session, city, trip = test_env

    # Insert a place
    p = Place(
        id=uuid4(),
        city_id=city.id,
        name="Bolgatty Palace",
        category="heritage",
        latitude=9.9897,
        longitude=76.2678,
    )
    session.add(p)
    session.commit()

    # Resolving with matching name & close coords returns existing place
    resolve_payload = {
        "name": "Bolgatty Palace",
        "latitude": 9.9898,
        "longitude": 76.2679,
        "category": "heritage",
        "external_place_id": "geo_bolgatty",
    }
    resp = client.post(f"/cities/{city.id}/places/resolve", json=resolve_payload)
    assert resp.status_code == 200
    data = resp.json()
    assert data["id"] == str(p.id)
