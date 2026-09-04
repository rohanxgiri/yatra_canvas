"""Evaluate Candidate Discovery Recall after the Production Fix across 5 Cities.

Uses the actual production OpenStreetMapPlacesService with category-specific
search radii and independent quotas.
"""

import asyncio
import json
import math
import os
import sys
import time
from pathlib import Path

# Add backend and script directory to sys.path
script_dir = Path(__file__).resolve().parent
backend_dir = Path(__file__).resolve().parents[3] / "backend"
sys.path.insert(0, str(script_dir))
sys.path.insert(0, str(backend_dir))

from app.core.config import Settings
from app.schemas.recommendation import DiscoveryCategory
from app.services.openstreetmap_places_service import (
    OpenStreetMapPlacesError,
    OpenStreetMapPlacesService,
)
from app.services.place_deduplication_service import (
    deduplicate_places,
    haversine_distance_meters,
)
from app.services.place_suitability_service import is_traveller_suitable
from app.models.entities import Place, PlaceSource

# Import reference sets and city centers from evaluate_recall
from evaluate_recall import CITY_CENTERS, REFERENCE_SETS, haversine_km

CACHE_DIR = Path(__file__).resolve().parent / "cache_production_fix_v2"
CACHE_DIR.mkdir(parents=True, exist_ok=True)
BASELINE_FILE = Path(__file__).resolve().parent / "recall_baseline.json"
RESULTS_FILE = Path(__file__).resolve().parent / "production_fix_results.json"


async def fetch_city_candidates(
    service: OpenStreetMapPlacesService,
    city: str,
    lat: float,
    lon: float,
    categories: list[DiscoveryCategory],
) -> dict:
    cache_file = CACHE_DIR / f"{city}_production_candidates.json"
    if cache_file.exists():
        print(f"[{city.upper()}] Loading from disk cache: {cache_file.name}")
        with open(cache_file, "r", encoding="utf-8") as f:
            return json.load(f)

    print(f"[{city.upper()}] Querying Overpass with production category quotas and radii...")
    start_time = time.monotonic()

    # Query with polite sequential requests
    places_by_category = {}
    query_count = 0
    query_errors = 0

    for cat in categories:
        limit = service.get_limit_for_category(cat)
        radius = service.get_radius_for_category(cat)
        print(f"  -> Querying category '{cat.value}' (radius={radius}m, limit={limit})...")
        t0 = time.monotonic()
        try:
            places = await service.search_nearby_places(
                latitude=lat,
                longitude=lon,
                category=cat,
                limit=limit,
                radius_meters=radius,
            )
            places_by_category[cat.value] = [
                {
                    "external_place_id": p.external_place_id,
                    "source_url": p.source_url,
                    "name": p.name,
                    "latitude": p.latitude,
                    "longitude": p.longitude,
                    "tags": p.tags,
                }
                for p in places
            ]
            query_count += 1
            dur = time.monotonic() - t0
            print(f"     Found {len(places)} items in {dur:.2f}s")
        except OpenStreetMapPlacesError as exc:
            query_errors += 1
            print(f"     Failed: {exc}")
            places_by_category[cat.value] = []
        
        # Polite delay to avoid Overpass rate-limiting
        await asyncio.sleep(2.0)

    total_latency = time.monotonic() - start_time
    payload = {
        "city": city,
        "latitude": lat,
        "longitude": lon,
        "query_count": query_count,
        "query_errors": query_errors,
        "total_latency_seconds": round(total_latency, 2),
        "places_by_category": places_by_category,
    }

    with open(cache_file, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)

    return payload


def evaluate_city(city: str, payload: dict, ref_places: list[dict], c_lat: float, c_lon: float) -> dict:
    places_by_category = payload["places_by_category"]

    # Gather all raw candidates
    all_raw = []
    seen_ids = set()
    raw_category_counts = {}

    for cat, items in places_by_category.items():
        raw_category_counts[cat] = len(items)
        for item in items:
            all_raw.append(item)

    total_raw_candidates = len(all_raw)

    # Convert to Place entities for deduplication pipeline
    dummy_places = []
    dummy_sources = []
    from uuid import uuid4

    ext_to_place_id = {}
    for idx, item in enumerate(all_raw):
        ext_id = item["external_place_id"]
        if ext_id in ext_to_place_id:
            pid = ext_to_place_id[ext_id]
        else:
            pid = uuid4()
            ext_to_place_id[ext_id] = pid

        p = Place(
            id=pid,
            city_id=uuid4(),
            name=item["name"],
            category=list(places_by_category.keys())[0],
            latitude=item["latitude"],
            longitude=item["longitude"],
        )
        dummy_places.append(p)

        s = PlaceSource(
            place_id=pid,
            source="openstreetmap",
            external_place_id=ext_id,
            source_url=item["source_url"],
            licence_identifier="ODbL-1.0",
        )
        dummy_sources.append(s)

    deduped = deduplicate_places(places=dummy_places, place_sources=dummy_sources)
    deduped_count = len(deduped)

    # Suitability filtering
    suitable_candidates = []
    suitability_filtered_count = 0
    for p in deduped:
        # Find item tags
        match_item = next((it for it in all_raw if it["name"] == p.name), None)
        tags = match_item["tags"] if match_item else {}
        is_suit, _ = is_traveller_suitable(name=p.name, category=p.category, tags=tags)
        if is_suit:
            suitable_candidates.append(p)
        else:
            suitability_filtered_count += 1

    # Match candidates against reference sets using identical logic
    cand_names = [it["name"].lower() for it in all_raw]
    cand_coords = [(it["latitude"], it["longitude"]) for it in all_raw]

    found_count = 0
    missing = []
    found = []

    for ref in ref_places:
        ref_name = ref["name"]
        ref_lat = ref["lat"]
        ref_lon = ref["lon"]
        d_center = haversine_km(c_lat, c_lon, ref_lat, ref_lon)

        matched = False
        ref_tokens = set(ref_name.lower().replace("-", " ").replace("'", "").split())

        for idx, c_name in enumerate(cand_names):
            c_c = cand_coords[idx]
            if not c_c[0] or not c_c[1]:
                continue
            d_cand = haversine_km(ref_lat, ref_lon, c_c[0], c_c[1])
            c_tokens = set(c_name.replace("-", " ").replace("'", "").split())
            overlap = len(ref_tokens & c_tokens)
            if d_cand <= 0.35 and overlap >= 1:
                matched = True
                break
            elif overlap >= 2 and d_cand <= 1.0:
                matched = True
                break

        if matched:
            found_count += 1
            found.append({
                "name": ref_name,
                "distance_km": round(d_center, 2),
                "category": ref["category"],
            })
        else:
            missing.append({
                "name": ref_name,
                "distance_km": round(d_center, 2),
                "category": ref["category"],
            })

    recall_pct = (found_count / len(ref_places)) * 100.0

    return {
        "city": city,
        "reference_count": len(ref_places),
        "found_count": found_count,
        "missing_count": len(missing),
        "recall_pct": round(recall_pct, 1),
        "raw_candidate_count": total_raw_candidates,
        "raw_category_counts": raw_category_counts,
        "deduped_candidate_count": deduped_count,
        "suitability_filtered_out": suitability_filtered_count,
        "suitable_candidate_count": len(suitable_candidates),
        "query_count": payload.get("query_count", 5),
        "query_errors": payload.get("query_errors", 0),
        "latency_seconds": payload.get("total_latency_seconds", 0),
        "found": found,
        "missing": missing,
    }


async def main():
    settings = Settings(
        DATABASE_URL="postgresql://localhost/yatracanvas_test",
    )

    category_radii = {
        DiscoveryCategory.TOURISM: settings.overpass_tourism_radius_meters,
        DiscoveryCategory.HERITAGE: settings.overpass_heritage_radius_meters,
        DiscoveryCategory.RELIGIOUS: settings.overpass_religious_radius_meters,
        DiscoveryCategory.FOOD: settings.overpass_food_radius_meters,
        DiscoveryCategory.CAFES: settings.overpass_cafe_radius_meters,
    }
    category_limits = {
        DiscoveryCategory.TOURISM: settings.overpass_tourism_limit,
        DiscoveryCategory.HERITAGE: settings.overpass_heritage_limit,
        DiscoveryCategory.RELIGIOUS: settings.overpass_religious_limit,
        DiscoveryCategory.FOOD: settings.overpass_food_limit,
        DiscoveryCategory.CAFES: settings.overpass_cafe_limit,
    }

    import httpx
    api_url = os.environ.get("OVERPASS_API_URL", "https://overpass-api.de/api/interpreter")
    timeout = max(settings.overpass_timeout_seconds, 35.0)
    async with httpx.AsyncClient(timeout=timeout) as client:
        service = OpenStreetMapPlacesService(
            api_url,
            timeout_seconds=timeout,
            radius_meters=settings.overpass_radius_meters,
            category_radii=category_radii,
            category_limits=category_limits,
            client=client,
        )

        categories = [
            DiscoveryCategory.TOURISM,
            DiscoveryCategory.HERITAGE,
            DiscoveryCategory.RELIGIOUS,
            DiscoveryCategory.FOOD,
            DiscoveryCategory.CAFES,
        ]

        # Load baseline for before vs after
        with open(BASELINE_FILE, "r", encoding="utf-8") as f:
            baseline_results = json.load(f)

        evaluation_results = {}
        total_ref_all = 0
        total_found_before_all = 0
        total_found_after_all = 0

        for city, ref_places in REFERENCE_SETS.items():
            lat, lon = CITY_CENTERS[city]
            payload = await fetch_city_candidates(service, city, lat, lon, categories)
            city_eval = evaluate_city(city, payload, ref_places, lat, lon)

            before_found = baseline_results[city]["found_count"]
            before_recall = baseline_results[city]["recall_pct"]
            city_eval["before_found_count"] = before_found
            city_eval["before_recall_pct"] = before_recall
            city_eval["recall_change_pct"] = round(city_eval["recall_pct"] - before_recall, 1)

            total_ref_all += len(ref_places)
            total_found_before_all += before_found
            total_found_after_all += city_eval["found_count"]

            evaluation_results[city] = city_eval

        overall_before_recall = round((total_found_before_all / total_ref_all) * 100, 1)
        overall_after_recall = round((total_found_after_all / total_ref_all) * 100, 1)
        overall_change = round(overall_after_recall - overall_before_recall, 1)

        summary = {
            "overall": {
                "total_references": total_ref_all,
                "total_found_before": total_found_before_all,
                "total_found_after": total_found_after_all,
                "before_recall_pct": overall_before_recall,
                "after_recall_pct": overall_after_recall,
                "recall_change_pct": overall_change,
            },
            "cities": evaluation_results,
        }

        with open(RESULTS_FILE, "w", encoding="utf-8") as f:
            json.dump(summary, f, indent=2)

        print("\n" + "=" * 70)
        print("PRODUCTION FIX CANDIDATE DISCOVERY RECALL RESULTS")
        print("=" * 70)
        print(f"{'City':<12} | {'Before':<10} | {'After':<10} | {'Change':<10} | {'Found/Total':<12}")
        print("-" * 70)
        for city, res in evaluation_results.items():
            print(
                f"{city.capitalize():<12} | "
                f"{res['before_recall_pct']:>5.1f}%    | "
                f"{res['recall_pct']:>5.1f}%    | "
                f"+{res['recall_change_pct']:>4.1f}%    | "
                f"{res['found_count']}/{res['reference_count']}"
            )
        print("-" * 70)
        print(
            f"{'OVERALL':<12} | "
            f"{overall_before_recall:>5.1f}%    | "
            f"{overall_after_recall:>5.1f}%    | "
            f"+{overall_change:>4.1f}%    | "
            f"{total_found_after_all}/{total_ref_all}"
        )
        print("=" * 70)


if __name__ == "__main__":
    asyncio.run(main())
