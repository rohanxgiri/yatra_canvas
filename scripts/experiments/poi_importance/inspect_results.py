"""Inspect and format experimental ranking results across all 5 cities."""

import json
import os

CITIES = ["jaipur", "ahmedabad", "surat", "delhi", "varanasi"]
RESULTS_DIR = os.path.join(os.path.dirname(__file__), "results")


def inspect_city(city_key: str):
    path = os.path.join(RESULTS_DIR, f"{city_key}.json")
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    city_name = data["city_name"]
    print(f"\n=======================================================")
    print(f"CITY: {city_name.upper()} (Total Candidates: {data['candidates_count']})")
    print(f"=======================================================")
    print("Metadata coverage:")
    for k, v in data["metadata_stats"]["percentages"].items():
        print(f"  {k:15}: {v}")
    print(f"Audiala matched: {data['audiala_matched_count']} ({data['audiala_matched_count']/data['candidates_count']*100:.1f}%)")

    print("\n--- TOP 10 CURRENT YATRACANVAS (Variant A) ---")
    for i, p in enumerate(data["top_20_variant_a"][:10], 1):
        name = p["name"]
        cat = p["category"]
        sc = p["score_a"]
        print(f"  {i:2d}. {name:<35} | {cat:<10} | Score: {sc:4.1f}")

    print("\n--- TOP 10 BEST OPEN DATA (Variant C: Wikidata + Wikipedia) ---")
    for i, p in enumerate(data["top_20_variant_c"][:10], 1):
        name = p["name"]
        cat = p["category"]
        sc = p["score_c"]
        sl = p["sitelinks"]
        pv = p["pageviews_90d"]
        qid = p.get("wikidata_id") or "None"
        aud = "YES" if p["audiala_match"] else "NO"
        print(f"  {i:2d}. {name:<35} | {cat:<10} | Score: {sc:4.1f} | QID: {qid:<10} | Sitelinks: {sl:2d} | 90d Views: {pv:7,d} | Aud: {aud}")

    print("\n--- TOP 10 FULL COMPOSITE (Variant D: Wikidata + Wikipedia + Audiala) ---")
    for i, p in enumerate(data["top_20_variant_d"][:10], 1):
        name = p["name"]
        cat = p["category"]
        sc = p["score_d"]
        sl = p["sitelinks"]
        pv = p["pageviews_90d"]
        pr = f"{p['audiala_pagerank']:.2f}" if p.get("audiala_pagerank") is not None else "None"
        aud = "YES" if p["audiala_match"] else "NO"
        print(f"  {i:2d}. {name:<35} | {cat:<10} | Score: {sc:4.1f} | Sitelinks: {sl:2d} | 90d Views: {pv:7,d} | Aud PR: {pr:<5} | Aud: {aud}")


if __name__ == "__main__":
    for c in CITIES:
        inspect_city(c)
