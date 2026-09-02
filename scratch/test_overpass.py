import asyncio
import httpx

async def test_overpass():
    url = "https://lz4.overpass-api.de/api/interpreter"
    bbox = "22.493200,88.277300,22.637000,88.421100" # Kolkata approx 8km radius
    filters = [
        '["tourism"~"^(attraction|museum|gallery|viewpoint|zoo|theme_park)$"]',
        '["leisure"="park"]',
        '["amenity"~"^(restaurant|fast_food|food_court)$"]',
        '["historic"]',
        '["heritage"]'
    ]
    statements = "\n".join(f'nwr({bbox})["name"]{f};' for f in filters)
    query = f"[out:json][timeout:25];\n(\n{statements}\n);\nout center 100;"
    
    headers = {"User-Agent": "YatraCanvas/0.1 (OpenStreetMap POI discovery)"}
    async with httpx.AsyncClient() as client:
        response = await client.post(url, data={"data": query}, headers=headers, timeout=30.0)
        print(f"Status: {response.status_code}")
        print(f"Time: {response.elapsed.total_seconds()}s")
        if response.status_code == 200:
            print(f"Results: {len(response.json().get('elements', []))}")
        else:
            print(f"Response: {response.text}")

asyncio.run(test_overpass())
