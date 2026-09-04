"""Evaluate Candidate Discovery Recall after adding Audiala Seed Layer."""

import asyncio
import json
import math
import os
import sys
import time
from pathlib import Path
from uuid import uuid4

# Add backend and script directory to sys.path
script_dir = Path(__file__).resolve().parent
backend_dir = Path(__file__).resolve().parents[3] / "backend"
sys.path.insert(0, str(script_dir))
sys.path.insert(0, str(backend_dir))

from app.core.config import Settings
from app.schemas.recommendation import DiscoveryCategory
from app.services.openstreetmap_places_service import OpenStreetMapPlacesService
from app.services.audiala_places_provider import AudialaPlacesProvider
from app.services.openstreetmap_discovery_service import OpenStreetMapDiscoveryService

from sqlmodel import Session, SQLModel
from app.models.entities import City

# Import reference sets and city centers from evaluate_recall
from evaluate_recall import CITY_CENTERS, REFERENCE_SETS, haversine_km

async def main():
    settings = Settings(
        DATABASE_URL="postgresql://localhost/yatracanvas_test",
        audiala_dataset_path="scripts/experiments/poi_importance/data/audiala_india.json",
    )

    import httpx
    api_url = os.environ.get("OVERPASS_API_URL", "https://overpass-api.de/api/interpreter")
    timeout = max(settings.overpass_timeout_seconds, 35.0)
    
    # We will use an in-memory SQLite DB for this test to avoid messing up dev db
    from sqlmodel import create_engine
    test_engine = create_engine("sqlite:///:memory:")
    SQLModel.metadata.create_all(test_engine)

    audiala_provider = AudialaPlacesProvider(settings.audiala_dataset_path)

    async with httpx.AsyncClient(timeout=timeout) as client:
        osm_provider = OpenStreetMapPlacesService(
            api_url,
            timeout_seconds=timeout,
            radius_meters=settings.overpass_radius_meters,
            category_radii={
                DiscoveryCategory.TOURISM: settings.overpass_tourism_radius_meters,
                DiscoveryCategory.HERITAGE: settings.overpass_heritage_radius_meters,
                DiscoveryCategory.RELIGIOUS: settings.overpass_religious_radius_meters,
                DiscoveryCategory.FOOD: settings.overpass_food_radius_meters,
                DiscoveryCategory.CAFES: settings.overpass_cafe_radius_meters,
                DiscoveryCategory.MARKETS: settings.overpass_markets_radius_meters,
                DiscoveryCategory.NATURE: settings.overpass_nature_radius_meters,
            },
            category_limits={
                DiscoveryCategory.TOURISM: settings.overpass_tourism_limit,
                DiscoveryCategory.HERITAGE: settings.overpass_heritage_limit,
                DiscoveryCategory.RELIGIOUS: settings.overpass_religious_limit,
                DiscoveryCategory.FOOD: settings.overpass_food_limit,
                DiscoveryCategory.CAFES: settings.overpass_cafe_limit,
                DiscoveryCategory.MARKETS: settings.overpass_markets_limit,
                DiscoveryCategory.NATURE: settings.overpass_nature_limit,
            },
            client=client,
        )

        discovery_service = OpenStreetMapDiscoveryService(
            settings=settings,
            provider=osm_provider,
            audiala_provider=audiala_provider,
        )

        categories = [
            DiscoveryCategory.TOURISM,
            DiscoveryCategory.HERITAGE,
            DiscoveryCategory.RELIGIOUS,
            DiscoveryCategory.FOOD,
            DiscoveryCategory.CAFES,
            DiscoveryCategory.MARKETS,
            DiscoveryCategory.NATURE,
        ]

        evaluation_results = {}
        total_ref_all = 0
        total_found_after_all = 0

        for city_name, ref_places in REFERENCE_SETS.items():
            lat, lon = CITY_CENTERS[city_name]
            
            with Session(test_engine) as session:
                city = City(id=uuid4(), name=city_name, country="India", latitude=lat, longitude=lon, radius_meters=10000)
                session.add(city)
                session.commit()
                
                print(f"[{city_name.upper()}] Discovering places via OSM + Audiala...")
                # We need to sleep to avoid hitting Overpass rate limits (if not cached inside OSM provider)
                # But since this is a clean DB, it WILL hit the API.
                results = await discovery_service.discover_many(
                    session=session,
                    city=city,
                    categories=categories,
                )
                await asyncio.sleep(2.0)
                
                # Flatten the results
                all_places = []
                for cat, places in results.items():
                    all_places.extend(places)
                
                print(f"[{city_name.upper()}] Discovered {len(all_places)} places.")

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
                        d_cand = haversine_km(ref_lat, ref_lon, p.latitude, p.longitude)
                        c_tokens = set(p.name.lower().replace("-", " ").replace("'", "").split())
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
