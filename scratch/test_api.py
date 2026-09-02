import asyncio
import time
from uuid import uuid4
from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.main import app
from app.api.deps import get_session
from app.models import City
from app.schemas.recommendation import DiscoveryCategory

client = TestClient(app)

def test_perf():
    with next(get_session()) as session:
        city = session.exec(select(City)).first()
        if not city:
            print("No city found, please create one or add mock data.")
            return
        
        city_id = city.id
        print(f"Using city {city.name} ({city_id})")

        categories = [
            DiscoveryCategory.RELIGIOUS.value,
            DiscoveryCategory.FOOD.value,
            DiscoveryCategory.TOURISM.value,
            DiscoveryCategory.CAFES.value,
            DiscoveryCategory.HERITAGE.value
        ]

        print(f"Making request for {categories}...")
        start_time = time.time()
        response = client.post(
            f"/cities/{city_id}/recommendations",
            json={"categories": categories, "limit": 30}
        )
        end_time = time.time()
        
        print(f"Status: {response.status_code}")
        print(f"Time: {end_time - start_time}s")
        if response.status_code != 200:
            print(f"Error: {response.text}")
        else:
            print(f"Got {len(response.json())} recommendations.")

if __name__ == "__main__":
    test_perf()
