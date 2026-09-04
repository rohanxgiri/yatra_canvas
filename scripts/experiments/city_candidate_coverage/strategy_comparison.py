"""Evaluate candidate discovery strategies across all 5 test cities."""

import json
import math
import os

REFERENCE_SETS_FILE = "scripts/experiments/city_candidate_coverage/recall_baseline.json"
AUDIALA_FILE = "scripts/experiments/poi_importance/data/audiala_india.json"

with open(REFERENCE_SETS_FILE, "r", encoding="utf-8") as f:
    baseline_data = json.load(f)

with open(AUDIALA_FILE, "r", encoding="utf-8") as f:
    audiala_data = json.load(f)

def run_strategy_comparison():
    out = {}

    for city, base in baseline_data.items():
        all_refs = base["found"] + base["missing"]
        total_refs = len(all_refs)
        osm_found = base["found_count"]

        # Strategy 1: Current YatraCanvas (8km, 100 limit)
        recall_current = (osm_found / total_refs) * 100

        # Strategy 2: Larger Radius (15km) without solving limit
        # Still capped at 100, but places within 15km eligible
        # Any place >15km is strictly OUTSIDE
        within_15km = [r for r in all_refs if r.get("distance_km", 0) <= 15.0]

        # Strategy 3: Multi-Category Separated Discovery (Per-Category Quotas)
        # Instead of 1 query capped at 100, 5 independent category queries (Tourism 60, Heritage 60, Religious 60, etc.)
        # Estimates recall if within 12km and not truncated by global limit
        within_12km = [r for r in all_refs if r.get("distance_km", 0) <= 12.0]
        # In Delhi, Tourism + Heritage would easily catch Red Fort, Humayun, India Gate, Qutub Minar (10.2km)
        # All of these exist in OSM within 12km!
        estimated_quota_found = len(within_12km)
        recall_quota = (estimated_quota_found / total_refs) * 100

        # Strategy 4: OSM + Audiala Multi-source
        city_alias = "new delhi" if city == "delhi" else city
        aud_places = [r for r in audiala_data if r.get("city_en", "").lower() == city_alias]
        
        aud_found = 0
        combined_found = 0
        for r in all_refs:
            name = r["name"].lower()
            is_osm = r in base["found"]
            is_aud = any(
                name in (a.get("name_en") or "").lower()
                or any(w in (a.get("name_en") or "").lower() for w in name.split() if len(w) > 4)
                for a in aud_places
            )
            if is_aud:
                aud_found += 1
            if is_osm or is_aud:
                combined_found += 1

        recall_audiala_only = (aud_found / total_refs) * 100
        recall_combined = (combined_found / total_refs) * 100

        # Strategy 5: Tiered Hybrid (OSM Dedicated Tourism/Heritage 15km + Audiala Seed Layer)
        # Places captured by Audiala + places within 15km in OSM
        within_15km_count = len(within_15km)
        # In 15km + Audiala, only extreme outliers (e.g. Akshardham Gandhinagar 25km or Suvali Beach 19km) require explicit regional reach
        hybrid_found = min(total_refs, len(set([r["name"] for r in within_15km] + [r["name"] for r in all_refs if any(r["name"].lower() in (a.get("name_en") or "").lower() for a in aud_places)])))
        recall_hybrid = (hybrid_found / total_refs) * 100

        out[city] = {
            "total_references": total_refs,
            "recall_current_8km_osm": round(recall_current, 1),
            "recall_separated_category_quotas_12km": round(recall_quota, 1),
            "recall_audiala_standalone": round(recall_audiala_only, 1),
            "recall_osm_plus_audiala": round(recall_combined, 1),
            "recall_tiered_hybrid_15km": round(recall_hybrid, 1),
        }

    return out

if __name__ == "__main__":
    res = run_strategy_comparison()
    print(json.dumps(res, indent=2))
    with open("scripts/experiments/city_candidate_coverage/strategy_comparison.json", "w", encoding="utf-8") as f:
        json.dump(res, f, indent=2)
