"""Diagnostic test harness reproducing real-world concurrency, latency, and resource starvation failures in YatraCanvas."""

from __future__ import annotations

import asyncio
import os
import sys
import time
from datetime import date, timedelta
from typing import Any
from uuid import UUID, uuid4

import httpx
from sqlmodel import Session, select
from sqlalchemy import event

# Add backend directory to sys.path
backend_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "backend"))
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

from app.database import get_engine
from app.models import City, Place, PlaceImageCache, Trip
from app.services.place_image_service import PlaceImageResolver
from app.core.config import get_settings

BASE_URL = "http://127.0.0.1:8000"


def get_test_city() -> tuple[str, str]:
    engine = get_engine()
    with Session(engine) as session:
        city = session.exec(select(City).where(City.name == "Shillong")).first()
        if not city:
            city = session.exec(select(City)).first()
        if not city:
            raise RuntimeError("No test city available in database.")
        return str(city.id), city.name


async def run_scenario_a(client: httpx.AsyncClient, city_id: str, city_name: str) -> dict[str, Any]:
    """Scenario A: Prefetch + Trip Creation Concurrency.
    
    Trigger background prefetch (stage=destination_confirmed) and IMMEDIATELY call POST /trips.
    Do NOT wait for background refresh.
    Verify if trip creation exceeds the Flutter 15-second client timeout or fails.
    """
    print("\n--- Running Scenario A: Prefetch + Trip Creation ---")
    
    # 1. Trigger background prefetch
    prefetch_payload = {
        "city_id": city_id,
        "stage": "destination_confirmed",
        "categories": ["heritage", "food", "tourism", "religious", "nature", "markets"],
    }
    print(f"Triggering background prefetch for {city_name} (Flutter prefetch timeout = 15,000 ms)...")
    t_pref_start = time.perf_counter()
    pref_ms = 0.0
    pref_status = None
    pref_timeout = False
    try:
        pref_res = await client.post(f"{BASE_URL}/places/prefetch", json=prefetch_payload, timeout=30.0)
        pref_ms = (time.perf_counter() - t_pref_start) * 1000
        pref_status = pref_res.status_code
        if pref_ms > 15000.0:
            pref_timeout = True
            print(f"  [VIOLATION] Prefetch took {pref_ms:.1f} ms (>15,000 ms Flutter timeout)!")
        else:
            print(f"Prefetch HTTP response: {pref_res.status_code} in {pref_ms:.1f} ms")
    except httpx.TimeoutException:
        pref_ms = (time.perf_counter() - t_pref_start) * 1000
        pref_timeout = True
        pref_status = "timeout"
        print(f"  [VIOLATION] Prefetch TIMED OUT after {pref_ms:.1f} ms!")
    except Exception as exc:
        pref_ms = (time.perf_counter() - t_pref_start) * 1000
        pref_status = f"error: {exc}"
        print(f"  Prefetch error: {exc}")

    # 2. IMMEDIATELY create trip while background workers are actively running
    trip_id = str(uuid4())
    start_d = date.today() + timedelta(days=10)
    end_d = start_d + timedelta(days=2)
    trip_payload = {
        "request_id": trip_id,
        "city_id": city_id,
        "trip_name": f"Scenario A {city_name} Trip",
        "days": 3,
        "start_date": start_d.isoformat(),
        "end_date": end_d.isoformat(),
        "arrival_place": f"{city_name} Center",
        "arrival_latitude": 25.57,
        "arrival_longitude": 91.88,
        "start_location_type": "arrival",
        "purposes": ["Culture & Heritage", "Food Exploration"],
        "preferences": ["Moderate", "Mid-range", "Cab / Taxi"],
    }

    print(f"Immediately dispatching POST /trips (Flutter timeout = 15,000 ms)...")
    t_trip_start = time.perf_counter()
    status = "success"
    error_msg = None
    trip_res_status = None
    try:
        trip_res = await client.post(f"{BASE_URL}/trips", json=trip_payload, timeout=35.0)
        trip_res_status = trip_res.status_code
        if trip_res.status_code not in (200, 201):
            status = "http_error"
            error_msg = f"HTTP {trip_res.status_code}: {trip_res.text}"
    except httpx.TimeoutException:
        status = "timeout"
        error_msg = "Request timed out after 35s"
    except Exception as exc:
        status = "failed"
        error_msg = f"{type(exc).__name__}: {exc}"

    trip_duration_ms = (time.perf_counter() - t_trip_start) * 1000
    violates_flutter_timeout = trip_duration_ms > 15000.0 or status != "success"
    print(f"Trip creation result: {status} (HTTP {trip_res_status}) in {trip_duration_ms:.1f} ms")
    if violates_flutter_timeout:
        print(f"  [VIOLATION] Exceeds 15,000 ms client timeout! (Actual: {trip_duration_ms:.1f} ms)")

    return {
        "scenario": "A",
        "status": status,
        "http_status": trip_res_status,
        "trip_duration_ms": trip_duration_ms,
        "prefetch_ms": pref_ms,
        "violates_flutter_timeout": violates_flutter_timeout,
        "error": error_msg,
    }


async def run_scenario_b(client: httpx.AsyncClient, city_id: str, city_name: str) -> dict[str, Any]:
    """Scenario B: Discover Under Load.
    
    Simulates Discover screen opening concurrently:
    - saved places
    - trip days
    - recommendations
    Measures recommendation latency and observes candidate queries.
    """
    print("\n--- Running Scenario B: Discover Under Load ---")
    trip_id = str(uuid4())
    start_d = date.today() + timedelta(days=10)
    end_d = start_d + timedelta(days=2)
    # Create a base trip first
    trip_payload = {
        "request_id": trip_id,
        "city_id": city_id,
        "trip_name": "Discover Load Test Trip",
        "days": 3,
        "start_date": start_d.isoformat(),
        "end_date": end_d.isoformat(),
        "arrival_place": f"{city_name} Station",
        "arrival_latitude": 25.57,
        "arrival_longitude": 91.88,
        "start_location_type": "arrival",
        "purposes": ["Culture & Heritage", "Food Exploration"],
        "preferences": ["Moderate", "Mid-range", "Cab / Taxi"],
    }
    t_create_base = time.perf_counter()
    base_res = await client.post(f"{BASE_URL}/trips", json=trip_payload, timeout=30.0)
    print(f"Base trip creation for Discover: {base_res.status_code} in {(time.perf_counter() - t_create_base)*1000:.1f} ms")

    # Concurrently execute Discover requests as Flutter does
    rec_payload = {
        "categories": ["heritage", "food", "tourism"],
        "limit": 10,
        "trip_id": trip_id,
    }

    t0 = time.perf_counter()
    days_task = asyncio.create_task(client.get(f"{BASE_URL}/trips/{trip_id}/days", timeout=25.0))
    saved_task = asyncio.create_task(client.get(f"{BASE_URL}/trips/{trip_id}/saved-places", timeout=25.0))
    rec_task = asyncio.create_task(client.post(f"{BASE_URL}/cities/{city_id}/recommendations", json=rec_payload, timeout=35.0))

    days_res, saved_res, rec_res = await asyncio.gather(days_task, saved_task, rec_task, return_exceptions=True)
    total_elapsed_ms = (time.perf_counter() - t0) * 1000

    rec_status = getattr(rec_res, "status_code", type(rec_res).__name__)
    rec_count = len(rec_res.json()) if getattr(rec_res, "status_code", None) == 200 else 0

    print(f"Concurrent Discover responses in {total_elapsed_ms:.1f} ms:")
    print(f"  Days: {getattr(days_res, 'status_code', type(days_res).__name__)}")
    print(f"  Saved Places: {getattr(saved_res, 'status_code', type(saved_res).__name__)}")
    print(f"  Recommendations: {rec_status} ({rec_count} places)")

    violates = total_elapsed_ms > 10000.0 or rec_status != 200
    if violates:
        print(f"  [VIOLATION] Recommendation response took {total_elapsed_ms:.1f} ms (>10,000 ms SLA threshold)!")

    return {
        "scenario": "B",
        "total_discover_ms": total_elapsed_ms,
        "rec_status": rec_status,
        "rec_count": rec_count,
        "violates_performance_sla": violates,
    }


async def run_scenario_c(client: httpx.AsyncClient, city_id: str, city_name: str, runs: int = 10) -> dict[str, Any]:
    """Scenario C: Full Onboarding Journey Repeated (10 consecutive journeys).
    
    No artificial waiting between steps.
    Measures trip-create time, recommendation time, pass/fail, min, median, max, p95.
    """
    print(f"\n--- Running Scenario C: Full Onboarding Journey ({runs} consecutive runs) ---")
    trip_latencies: list[float] = []
    rec_latencies: list[float] = []
    failures = 0

    for i in range(1, runs + 1):
        print(f"Journey Run {i}/{runs}...", end=" ", flush=True)
        t_journey_start = time.perf_counter()
        run_failed = False
        trip_id = str(uuid4())

        try:
            # 1. Destination Confirmed prefetch (fire-and-forget in Flutter)
            try:
                await client.post(
                    f"{BASE_URL}/places/prefetch",
                    json={"city_id": city_id, "stage": "destination_confirmed"},
                    timeout=15.0,
                )
            except Exception:
                pass

            # 2. Interests Confirmed prefetch (fire-and-forget in Flutter)
            try:
                await client.post(
                    f"{BASE_URL}/places/prefetch",
                    json={
                        "city_id": city_id,
                        "stage": "interests_confirmed",
                        "categories": ["heritage", "food", "tourism"],
                    },
                    timeout=15.0,
                )
            except Exception:
                pass

            # 3. Create Trip (Flutter timeout 15s)
            t_trip_start = time.perf_counter()
            start_d = date.today() + timedelta(days=15)
            end_d = start_d + timedelta(days=2)
            trip_res = await client.post(
                f"{BASE_URL}/trips",
                json={
                    "request_id": trip_id,
                    "city_id": city_id,
                    "trip_name": f"Journey {i}",
                    "days": 3,
                    "start_date": start_d.isoformat(),
                    "end_date": end_d.isoformat(),
                    "arrival_place": f"{city_name} Center",
                    "arrival_latitude": 25.57,
                    "arrival_longitude": 91.88,
                    "start_location_type": "arrival",
                    "purposes": ["Culture & Heritage"],
                    "preferences": ["Moderate", "Mid-range", "Cab / Taxi"],
                },
                timeout=35.0,
            )
            trip_time = (time.perf_counter() - t_trip_start) * 1000
            trip_latencies.append(trip_time)

            if trip_res.status_code not in (200, 201) or trip_time > 15000.0:
                run_failed = True
                print(f"[TRIP FAIL/TIMEOUT: {trip_res.status_code} in {trip_time:.0f}ms]", end=" ")

            # 4. Discover Recommendations
            t_rec_start = time.perf_counter()
            rec_res = await client.post(
                f"{BASE_URL}/cities/{city_id}/recommendations",
                json={
                    "categories": ["heritage", "food"],
                    "limit": 10,
                    "trip_id": trip_id,
                },
                timeout=35.0,
            )
            rec_time = (time.perf_counter() - t_rec_start) * 1000
            rec_latencies.append(rec_time)

            if rec_res.status_code != 200 or rec_time > 20000.0:
                run_failed = True
                print(f"[REC FAIL/SLOW: {rec_res.status_code} in {rec_time:.0f}ms]", end=" ")

        except Exception as exc:
            run_failed = True
            failures += 1
            print(f"[EXCEPTION: {exc}]", end=" ")

        total_ms = (time.perf_counter() - t_journey_start) * 1000
        if not run_failed:
            print(f"OK (trip={trip_latencies[-1]:.0f}ms, rec={rec_latencies[-1]:.0f}ms, total={total_ms:.0f}ms)")
        else:
            failures += 1
            print(f"FAILED (total={total_ms:.0f}ms)")

    trip_latencies.sort()
    rec_latencies.sort()

    def stats(vals: list[float]) -> dict[str, float]:
        if not vals:
            return {"min": 0, "median": 0, "max": 0, "p95": 0}
        n = len(vals)
        return {
            "min": round(vals[0], 1),
            "median": round(vals[n // 2], 1),
            "max": round(vals[-1], 1),
            "p95": round(vals[int(n * 0.95)], 1) if n >= 10 else round(vals[-1], 1),
        }

    trip_stats = stats(trip_latencies)
    rec_stats = stats(rec_latencies)
    print(f"\nJourney Statistics over {runs} runs:")
    print(f"  Trip Create: min={trip_stats['min']}ms, median={trip_stats['median']}ms, max={trip_stats['max']}ms, p95={trip_stats['p95']}ms")
    print(f"  Recommendations: min={rec_stats['min']}ms, median={rec_stats['median']}ms, max={rec_stats['max']}ms, p95={rec_stats['p95']}ms")
    print(f"  Total Journeys Failed: {failures}/{runs}")

    return {
        "scenario": "C",
        "runs": runs,
        "failures": failures,
        "trip_stats": trip_stats,
        "rec_stats": rec_stats,
    }


async def run_scenario_d() -> dict[str, Any]:
    """Scenario D: Image Resolution Batch (20 realistic persisted places).
    
    Tests whether Semaphore(1) lock contention causes places to exhaust their 10.0s budget
    and get marked as 'provider_error' in PlaceImageCache.
    """
    print("\n--- Running Scenario D: Image Resolution Batch (20 Places) ---")
    engine = get_engine()

    with Session(engine) as session:
        places = session.exec(select(Place).limit(20)).all()
        place_ids = [p.id for p in places]

    print(f"Resolving images for {len(place_ids)} real persisted places with force=True...")
    resolver = PlaceImageResolver()
    t0 = time.perf_counter()

    with Session(engine) as session:
        results = await resolver.resolve_many(session, place_ids, force=True)

    duration_ms = (time.perf_counter() - t0) * 1000

    with Session(engine) as session:
        cached_rows = session.exec(
            select(PlaceImageCache).where(PlaceImageCache.place_id.in_(place_ids))
        ).all()
        statuses = [r.status for r in cached_rows]
        reasons = [r.failure_reason for r in cached_rows if r.failure_reason]

    resolved_count = statuses.count("resolved")
    not_found_count = statuses.count("not_found")
    failed_count = statuses.count("failed")
    provider_error_count = reasons.count("provider_error")

    print(f"Batch resolution completed in {duration_ms:.1f} ms")
    print(f"Results: resolved={resolved_count}, not_found={not_found_count}, failed={failed_count}")
    print(f"Failure reasons: provider_error={provider_error_count}")

    violates = provider_error_count > 0 or failed_count > 5
    if violates:
        print(f"  [VIOLATION] High provider_error count ({provider_error_count}) caused by lock starvation!")

    return {
        "scenario": "D",
        "place_count": len(place_ids),
        "duration_ms": duration_ms,
        "resolved": resolved_count,
        "not_found": not_found_count,
        "failed": failed_count,
        "provider_error": provider_error_count,
        "violates_reliability": violates,
    }


async def main():
    print("================================================================================")
    print("YatraCanvas Diagnostic Harness: Reproducing Real-World Failures")
    print("================================================================================")

    city_id, city_name = get_test_city()
    print(f"Using test city: {city_name} ({city_id})")

    async with httpx.AsyncClient() as client:
        res_a = await run_scenario_a(client, city_id, city_name)
        res_b = await run_scenario_b(client, city_id, city_name)
        res_c = await run_scenario_c(client, city_id, city_name, runs=10)
        res_d = await run_scenario_d()

    print("\n================================================================================")
    print("SUMMARY OF DIAGNOSTIC REPRODUCTION RESULTS")
    print("================================================================================")
    print(f"Scenario A (Trip create during prefetch): duration={res_a['trip_duration_ms']:.1f}ms, violates_timeout={res_a['violates_flutter_timeout']}")
    print(f"Scenario B (Discover recommendation latency): total={res_b['total_discover_ms']:.1f}ms, rec_status={res_b['rec_status']}, violates_sla={res_b['violates_performance_sla']}")
    print(f"Scenario C (10 Onboarding Journeys): failures={res_c['failures']}/10, trip_median={res_c['trip_stats']['median']}ms, trip_max={res_c['trip_stats']['max']}ms, rec_median={res_c['rec_stats']['median']}ms")
    print(f"Scenario D (Image 20-batch resolution): resolved={res_d['resolved']}, failed={res_d['failed']}, provider_errors={res_d['provider_error']}, violates={res_d['violates_reliability']}")


if __name__ == "__main__":
    asyncio.run(main())
