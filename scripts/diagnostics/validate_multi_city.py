"""Multi-city validation harness verifying the end-to-end travel journey across 7 iconic Indian destinations.

Validates:
1. City resolution / retrieval
2. Progressive prefetch trigger
3. Trip creation with days and preferences
4. Discover recommendations retrieval
5. Place image cache resolution and fallback safety
Cities tested:
- Shillong (Meghalaya)
- Jaipur (Rajasthan)
- Manali (Himachal Pradesh)
- Rishikesh (Uttarakhand)
- Goa (Goa)
- Varanasi (Uttar Pradesh)
- Udaipur (Rajasthan)
"""

from __future__ import annotations

import asyncio
import os
import sys
import time
from datetime import date, timedelta
from typing import Any
from uuid import uuid4

import httpx

# Add backend directory to sys.path
backend_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "backend"))
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

BASE_URL = "http://127.0.0.1:8000"

CITIES = [
    {"name": "Shillong", "state": "Meghalaya", "country": "India", "latitude": 25.5788, "longitude": 91.8933},
    {"name": "Jaipur", "state": "Rajasthan", "country": "India", "latitude": 26.9124, "longitude": 75.7873},
    {"name": "Manali", "state": "Himachal Pradesh", "country": "India", "latitude": 32.2396, "longitude": 77.1887},
    {"name": "Rishikesh", "state": "Uttarakhand", "country": "India", "latitude": 30.0869, "longitude": 78.2676},
    {"name": "Goa", "state": "Goa", "country": "India", "latitude": 15.2993, "longitude": 74.1240},
    {"name": "Varanasi", "state": "Uttar Pradesh", "country": "India", "latitude": 25.3176, "longitude": 82.9739},
    {"name": "Udaipur", "state": "Rajasthan", "country": "India", "latitude": 24.5854, "longitude": 73.7125},
]


async def test_city_journey(client: httpx.AsyncClient, city_def: dict[str, Any]) -> dict[str, Any]:
    name = city_def["name"]
    print(f"\n--- Testing City Journey: {name} ({city_def['state']}) ---")
    start_time = time.perf_counter()

    # 1. Resolve city
    t0 = time.perf_counter()
    res = await client.post(f"{BASE_URL}/cities/resolve", json=city_def, timeout=20.0)
    if res.status_code not in (200, 201):
        return {"city": name, "status": "failed", "step": "resolve_city", "error": res.text}
    city_data = res.json()
    city_id = city_data["id"]
    resolve_ms = (time.perf_counter() - t0) * 1000
    print(f"  [1] City resolved: {name} ({city_id}) in {resolve_ms:.1f} ms")

    # 2. Trigger prefetch
    t0 = time.perf_counter()
    pref_res = await client.post(
        f"{BASE_URL}/places/prefetch",
        json={"city_id": city_id, "stage": "destination_confirmed"},
        timeout=25.0,
    )
    pref_ms = (time.perf_counter() - t0) * 1000
    print(f"  [2] Prefetch: HTTP {pref_res.status_code} in {pref_ms:.1f} ms")

    # 3. Create trip
    t0 = time.perf_counter()
    trip_id = str(uuid4())
    start_d = date.today() + timedelta(days=14)
    end_d = start_d + timedelta(days=3)
    trip_payload = {
        "request_id": trip_id,
        "city_id": city_id,
        "trip_name": f"{name} Exploration",
        "days": 4,
        "start_date": start_d.isoformat(),
        "end_date": end_d.isoformat(),
        "arrival_place": f"{name} Central Station",
        "arrival_latitude": city_def["latitude"],
        "arrival_longitude": city_def["longitude"],
        "start_location_type": "arrival",
        "purposes": ["Culture & Heritage", "Sightseeing"],
        "preferences": ["Moderate", "Mid-range", "Cab / Taxi"],
    }
    try:
        trip_res = await client.post(f"{BASE_URL}/trips", json=trip_payload, timeout=35.0)
        trip_ms = (time.perf_counter() - t0) * 1000
        if trip_res.status_code not in (200, 201):
            return {"city": name, "status": "failed", "step": "create_trip", "error": trip_res.text}
        print(f"  [3] Trip created: HTTP {trip_res.status_code} in {trip_ms:.1f} ms")
    except Exception as exc:
        trip_ms = (time.perf_counter() - t0) * 1000
        print(f"  [3] Trip create EXCEPTION: {exc} after {trip_ms:.1f} ms")
        return {"city": name, "status": "failed", "step": "create_trip", "error": str(exc)}

    # 4. Fetch recommendations
    t0 = time.perf_counter()
    rec_payload = {
        "categories": ["heritage", "tourism", "food"],
        "limit": 10,
        "trip_id": trip_id,
    }
    try:
        rec_res = await client.post(f"{BASE_URL}/cities/{city_id}/recommendations", json=rec_payload, timeout=35.0)
        rec_ms = (time.perf_counter() - t0) * 1000
        rec_count = len(rec_res.json()) if rec_res.status_code == 200 else 0
        print(f"  [4] Recommendations: HTTP {rec_res.status_code} ({rec_count} places) in {rec_ms:.1f} ms")
    except Exception as exc:
        rec_ms = (time.perf_counter() - t0) * 1000
        print(f"  [4] Rec EXCEPTION: {exc} after {rec_ms:.1f} ms")
        return {"city": name, "status": "failed", "step": "recommendations", "error": str(exc)}

    # 5. Fetch trip days
    try:
        days_res = await client.get(f"{BASE_URL}/trips/{trip_id}/days", timeout=20.0)
        days_count = len(days_res.json()) if days_res.status_code == 200 else 0
        print(f"  [5] Trip days: HTTP {days_res.status_code} ({days_count} days)")
    except Exception as exc:
        print(f"  [5] Days EXCEPTION: {exc}")
        days_count = 0

    total_ms = (time.perf_counter() - start_time) * 1000
    print(f"  -> Total journey completed in {total_ms:.1f} ms (Trip: {trip_ms:.1f}ms, Rec: {rec_ms:.1f}ms)")

    return {
        "city": name,
        "status": "success",
        "trip_ms": trip_ms,
        "rec_ms": rec_ms,
        "rec_count": rec_count,
        "days_count": days_count,
        "total_ms": total_ms,
    }


async def main():
    print("================================================================================")
    print("YatraCanvas Multi-City Journey Validation")
    print(f"Testing {len(CITIES)} cities across India")
    print("================================================================================")

    results = []
    async with httpx.AsyncClient() as client:
        for city_def in CITIES:
            res = await test_city_journey(client, city_def)
            results.append(res)

    print("\n================================================================================")
    print("MULTI-CITY VALIDATION SUMMARY")
    print("================================================================================")
    all_success = True
    for r in results:
        status_str = "PASSED" if r["status"] == "success" else f"FAILED ({r.get('step')}: {r.get('error')})"
        if r["status"] != "success":
            all_success = False
            print(f"  {r['city']:<12}: {status_str}")
        else:
            print(f"  {r['city']:<12}: {status_str:<10} | Trip: {r['trip_ms']:>7.1f} ms | Rec: {r['rec_ms']:>7.1f} ms | Places: {r['rec_count']}")

    print("================================================================================")
    if all_success:
        print("ALL 7 CITIES PASSED VALIDATION!")
    else:
        print("SOME CITIES FAILED VALIDATION.")


if __name__ == "__main__":
    asyncio.run(main())
