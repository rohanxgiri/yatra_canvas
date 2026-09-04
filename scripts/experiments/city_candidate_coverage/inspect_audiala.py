import json

with open("scripts/experiments/poi_importance/data/audiala_india.json", "r", encoding="utf-8") as f:
    aud = json.load(f)

for c in ["Jaipur", "Ahmedabad", "New Delhi", "Varanasi"]:
    places = [r for r in aud if r["city_en"] == c]
    print(f"\n=== {c} (Total: {len(places)}) ===")
    top = sorted(places, key=lambda x: x.get("sitelinks") or 0, reverse=True)[:10]
    for p in top:
        name = p["name_en"]
        qid = p["wikidata_id"]
        sl = p.get("sitelinks")
        pr = p.get("wikidata_pagerank")
        lat = p["latitude"]
        lon = p["longitude"]
        print(f"  {name:<32} | QID: {qid:<10} | sl: {sl:2d} | PR: {pr} | ({lat:.4f}, {lon:.4f})")
