"""Evaluate Candidate Discovery Recall (OSM + Audiala) instantly using cached OSM data."""

import asyncio
import json
import math
import os
import sys
from pathlib import Path

script_dir = Path(__file__).resolve().parent
backend_dir = Path(__file__).resolve().parents[3] / "backend"
sys.path.insert(0, str(script_dir))
sys.path.insert(0, str(backend_dir))

from app.schemas.recommendation import DiscoveryCategory
from app.services.audiala_places_provider import AudialaPlacesProvider
from evaluate_recall import CITY_CENTERS, REFERENCE_SETS, haversine_km

CACHE_DIR = Path(__file__).resolve().parent / "cache_production_fix_v2"

async def main():
    dataset_path = "scripts/experiments/poi_importance/data/audiala_india.json"
    audiala_provider = AudialaPlacesProvider(dataset_path)

    categories = [
        DiscoveryCategory.TOURISM,
        DiscoveryCategory.HERITAGE,
        DiscoveryCategory.RELIGIOUS,
        DiscoveryCategory.FOOD,
        DiscoveryCategory.CAFES,
        DiscoveryCategory.MARKETS,
        DiscoveryCategory.NATURE,
    ]
    
    category_radii = {
        DiscoveryCategory.TOURISM: 15000,
        DiscoveryCategory.HERITAGE: 15000,
        DiscoveryCategory.RELIGIOUS: 10000,
        DiscoveryCategory.FOOD: 8000,
        DiscoveryCategory.CAFES: 8000,
    }
    
    category_limits = {
        DiscoveryCategory.TOURISM: 60,
        DiscoveryCategory.HERITAGE: 60,
        DiscoveryCategory.RELIGIOUS: 40,
        DiscoveryCategory.FOOD: 50,
        DiscoveryCategory.CAFES: 40,
    }

    evaluation_results = {}
    total_ref_all = 0
    total_found_after_all = 0

    for city_name, ref_places in REFERENCE_SETS.items():
        lat, lon = CITY_CENTERS[city_name]
        
        # Load OSM cached candidates
        cache_file = CACHE_DIR / f"{city_name}_production_candidates.json"
        all_places = []
        if cache_file.exists():
            with open(cache_file, "r", encoding="utf-8") as f:
                payload = json.load(f)
                for cat, items in payload["places_by_category"].items():
                    for item in items:
                        all_places.append({
                            "name": item["name"],
                            "latitude": item["latitude"],
                            "longitude": item["longitude"],
                            "source": "osm"
                        })
                        
        # Get Audiala candidates
        audiala_by_category = await audiala_provider.search_nearby_places_for_categories(
            latitude=lat,
            longitude=lon,
            categories=categories,
            category_radii=category_radii,
            category_limits=category_limits,
        )
        for cat, items in audiala_by_category.items():
            for item in items:
                all_places.append({
                    "name": item.name,
                    "latitude": item.latitude,
                    "longitude": item.longitude,
                    "source": "audiala"
                })
        
        print(f"[{city_name.upper()}] Discovered {len(all_places)} places combined.")

        # Evaluate against reference sets
        found_count = 0
        missing = []
        found = []
        for ref in ref_places:
            ref_name = ref["name"]
            ref_lat = ref["lat"]
            ref_lon = ref["lon"]
            d_center = haversine_km(lat, lon, ref_lat, ref_lon)
            is_outside = d_center > 8.0
            
            matched = False
            ref_tokens = set(ref_name.lower().replace("-", " ").replace("'", "").split())
            
            for p in all_places:
                d_cand = haversine_km(ref_lat, ref_lon, p["latitude"], p["longitude"])
                c_tokens = set(p["name"].lower().replace("-", " ").replace("'", "").split())
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
                    "cause": "OUTSIDE_SEARCH_AREA" if is_outside else "MISSING",
                })
                
        recall_pct = (found_count / len(ref_places)) * 100.0
        print(f"[{city_name.upper()}] Recall: {recall_pct:.1f}% ({found_count}/{len(ref_places)})")
        
        total_ref_all += len(ref_places)
        total_found_after_all += found_count
        
        evaluation_results[city_name] = {
            "reference_count": len(ref_places),
            "found_count": found_count,
            "recall_pct": recall_pct,
            "missing": missing,
            "found": found,
        }
        
    overall_after_recall = (total_found_after_all / total_ref_all) * 100
    print("\n" + "=" * 70)
    print(f"OVERALL RECALL: {overall_after_recall:.1f}% ({total_found_after_all}/{total_ref_all})")
    print("=" * 70)

    summary = {
        "overall": {
            "total_references": total_ref_all,
            "total_found": total_found_after_all,
            "recall_pct": overall_after_recall,
        },
        "cities": evaluation_results,
    }

    with open("scripts/experiments/city_candidate_coverage/production_audiala_results.json", "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2)


if __name__ == "__main__":
    asyncio.run(main())
