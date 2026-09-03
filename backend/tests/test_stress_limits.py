"""Stress tests for generating larger itineraries and heavy load."""

import asyncio
from collections.abc import Generator
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import event
from sqlalchemy.engine import Engine
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine

from app.database import get_session
from app.main import app
from app.models import Place, PlaceSource, PlaceCategory
from app.routers.route_optimization import get_route_provider
from app.services.local_routes_service import LocalRoutesService

# We need to simulate heavy operations on SQLite
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
    
    # Use LocalRoutesService instead of FakeGoogle to simulate real matrix calculation
    app.dependency_overrides[get_route_provider] = lambda: LocalRoutesService()

    client = TestClient(app)
    yield client, engine
    client.close()
    app.dependency_overrides.clear()
    SQLModel.metadata.drop_all(engine)

def _create_city(client: TestClient) -> dict[str, object]:
    response = client.post(
        "/cities",
        json={
            "name": "Stress City",
            "state": "State",
            "country": "India",
            "latitude": 23.1765,
            "longitude": 75.7885,
            "google_place_id": f"stress-city-{uuid4()}",
        },
    )
    return response.json()

def test_heavy_trip_planning_flow(client_and_engine: tuple[TestClient, Engine]) -> None:
    client, engine = client_and_engine
    
    city = _create_city(client)
    city_id = city["id"]
    
    place_uuid_str_list = [str(uuid4()) for _ in range(30)]
    
    # Create 30 places to simulate a city with many places
    with Session(engine) as session:
        for i, place_id_str in enumerate(place_uuid_str_list):
            place = Place(
                id=UUID(place_id_str),
                city_id=UUID(city_id),
                name=f"Stress Place {i}",
                latitude=23.1765 + (i * 0.001),
                longitude=75.7885 + (i * 0.001),
                category="heritage",
                rating=4.5,
                review_count=100,
                is_popular=True,
            )
            session.add(place)
        session.commit()
        
    # 1. Create a trip with multiple interests (5+)
    response = client.post(
        "/trips",
        json={
            "city_id": city_id,
            "start_date": "2026-09-10",
            "end_date": "2026-09-14",
            "days": 5,
            "arrival_place": "Ujjain Railway Station",
            "arrival_latitude": 23.1793,
            "arrival_longitude": 75.7849,
            "start_location_type": "hotel",
            "start_location_name": "Test Hotel",
            "start_latitude": 23.1765,
            "start_longitude": 75.7885,
            "start_location_provider": "geoapify",
            "start_location_provider_place_id": "geoapify-test-hotel",
            "purposes": ["heritage", "food", "nature", "shopping", "adventure", "religious"],
            "preferences": ["heritage", "food", "nature", "shopping", "adventure", "religious"],
        },
    )
    assert response.status_code == 201, f"Failed to create trip: {response.json()}"
    trip_id = response.json()["trip_id"]
    
    # 2. Add 20 places rapidly (testing state/API)
    place_ids = place_uuid_str_list[:20]
    for idx, pid in enumerate(place_ids):
        res = client.post(f"/trips/{trip_id}/saved-places", json={"place_id": pid})
        assert res.status_code == 201
        
    # 3. Repeated reordering of 20 places
    for _ in range(3):
        # Reverse the order
        place_ids.reverse()
        reorder_payload = {
            "places": [
                {"place_id": pid, "custom_order": idx + 1}
                for idx, pid in enumerate(place_ids)
            ]
        }
        res = client.patch(f"/trips/{trip_id}/saved-places/reorder", json=reorder_payload)
        assert res.status_code == 200
        assert [p["place_id"] for p in res.json()] == place_ids

    # 4. Repeated removal and addition
    for _ in range(5):
        pid = place_ids.pop()
        res = client.delete(f"/trips/{trip_id}/saved-places/{pid}")
        assert res.status_code == 204
        
        res = client.post(f"/trips/{trip_id}/saved-places", json={"place_id": pid})
        assert res.status_code == 201
        place_ids.append(pid)
        
    # 5. Route optimization with a large itinerary (20 places over 5 days)
    res = client.post(f"/trips/{trip_id}/optimize-route")
    assert res.status_code == 200
    
    # 6. Smart Replanning API on large trip
    res = client.post(
        f"/trips/{trip_id}/replan-preview",
        json={"reason": "test"}
    )
    assert res.status_code == 200
    
    # Apply
    res = client.post(f"/trips/{trip_id}/replan-apply")
    assert res.status_code == 200
