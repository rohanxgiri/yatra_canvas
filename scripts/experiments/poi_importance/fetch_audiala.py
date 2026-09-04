"""Fetch and extract Audiala open-data for India."""

import csv
import json
import os
import httpx

AUDIALA_CSV_URL = "https://raw.githubusercontent.com/audiala/open-data/main/data/audiala-places.csv"
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "data")
OUTPUT_FILE = os.path.join(OUTPUT_DIR, "audiala_india.json")


def fetch_audiala_india():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    if os.path.exists(OUTPUT_FILE):
        print(f"Audiala India file already exists at {OUTPUT_FILE}")
        with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
            print(f"Loaded {len(data)} cached India records.")
            return data

    print(f"Downloading Audiala dataset from {AUDIALA_CSV_URL}...")
    india_rows = []
    total_rows = 0

    with httpx.stream("GET", AUDIALA_CSV_URL, follow_redirects=True, timeout=120.0) as resp:
        resp.raise_for_status()
        line_iter = resp.iter_lines()
        header_line = next(line_iter)
        
        # We parse line by line with csv.reader
        header = next(csv.reader([header_line]))
        col_indices = {col: i for i, col in enumerate(header)}
        
        c_iso2_idx = col_indices.get("country_iso2")
        qid_idx = col_indices.get("wikidata_id")
        name_en_idx = col_indices.get("name_en")
        lat_idx = col_indices.get("latitude")
        lon_idx = col_indices.get("longitude")
        city_idx = col_indices.get("city_en")
        cat_idx = col_indices.get("category")
        tier_idx = col_indices.get("article_tier")
        pr_idx = col_indices.get("wikidata_pagerank")
        sitelinks_idx = col_indices.get("sitelinks")
        url_idx = col_indices.get("url_en")

        for line in line_iter:
            if not line:
                continue
            total_rows += 1
            row = next(csv.reader([line]))
            if c_iso2_idx is not None and len(row) > c_iso2_idx:
                if row[c_iso2_idx] == "IN":
                    india_rows.append({
                        "wikidata_id": row[qid_idx] if qid_idx < len(row) else None,
                        "name_en": row[name_en_idx] if name_en_idx < len(row) else None,
                        "latitude": float(row[lat_idx]) if lat_idx < len(row) and row[lat_idx] else None,
                        "longitude": float(row[lon_idx]) if lon_idx < len(row) and row[lon_idx] else None,
                        "city_en": row[city_idx] if city_idx < len(row) else None,
                        "category": row[cat_idx] if cat_idx < len(row) else None,
                        "article_tier": row[tier_idx] if tier_idx < len(row) else None,
                        "wikidata_pagerank": float(row[pr_idx]) if pr_idx < len(row) and row[pr_idx] else None,
                        "sitelinks": int(row[sitelinks_idx]) if sitelinks_idx < len(row) and row[sitelinks_idx] else None,
                        "url_en": row[url_idx] if url_idx < len(row) else None,
                    })

    print(f"Scanned {total_rows} total Audiala rows. Found {len(india_rows)} in India.")
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(india_rows, f, indent=2, ensure_ascii=False)
    print(f"Saved to {OUTPUT_FILE}")
    return india_rows


if __name__ == "__main__":
    fetch_audiala_india()
