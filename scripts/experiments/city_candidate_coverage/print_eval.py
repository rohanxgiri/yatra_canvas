import sys
import json
from pathlib import Path

script_dir = Path(__file__).resolve().parent
backend_dir = Path(__file__).resolve().parents[2] / "backend"
sys.path.insert(0, str(script_dir))
sys.path.insert(0, str(backend_dir))

from evaluate_production_fix import evaluate_city, BASELINE_FILE, REFERENCE_SETS, CITY_CENTERS

baseline = json.load(open(BASELINE_FILE))
cache_dir = Path(__file__).resolve().parent / "cache_production_fix"

total_ref = 0
total_found_before = 0
total_found_after = 0

print("=" * 70)
print("PRODUCTION FIX CANDIDATE DISCOVERY RECALL RESULTS")
print("=" * 70)
print(f"{'City':<12} | {'Before':<10} | {'After':<10} | {'Change':<10} | {'Found/Total':<12}")
print("-" * 70)

city_results = {}
for city, ref in REFERENCE_SETS.items():
    cfile = cache_dir / f"{city}_production_candidates.json"
    payload = json.load(open(cfile, encoding="utf-8"))
    lat, lon = CITY_CENTERS[city]
    res = evaluate_city(city, payload, ref, lat, lon)
    b_found = baseline[city]["found_count"]
    b_rec = baseline[city]["recall_pct"]
    change = round(res["recall_pct"] - b_rec, 1)
    total_ref += len(ref)
    total_found_before += b_found
    total_found_after += res["found_count"]
    city_results[city] = res
    print(f"{city.capitalize():<12} | {b_rec:>5.1f}%    | {res['recall_pct']:>5.1f}%    | +{change:>4.1f}%    | {res['found_count']}/{len(ref)}")

print("-" * 70)
ov_b = round(total_found_before / total_ref * 100, 1)
ov_a = round(total_found_after / total_ref * 100, 1)
print(f"{'OVERALL':<12} | {ov_b:>5.1f}%    | {ov_a:>5.1f}%    | +{round(ov_a-ov_b, 1):>4.1f}%    | {total_found_after}/{total_ref}")
print("=" * 70)

# Also dump to production_fix_results.json
results_file = Path(__file__).resolve().parent / "production_fix_results.json"
with open(results_file, "w", encoding="utf-8") as f:
    json.dump({
        "overall": {
            "total_references": total_ref,
            "total_found_before": total_found_before,
            "total_found_after": total_found_after,
            "before_recall_pct": ov_b,
            "after_recall_pct": ov_a,
            "recall_change_pct": round(ov_a - ov_b, 1),
        },
        "cities": city_results,
    }, f, indent=2)
print("Saved to", results_file.name)
