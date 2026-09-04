"""Real-data feasibility experiment for city-level POI importance ranking.

Tests:
- Jaipur, Ahmedabad, Surat, Delhi, Varanasi
- Overpass candidate discovery + existing YatraCanvas deduplication and suitability filtering
- OSM metadata coverage
- Wikidata entity batch enrichment (sitelinks, claims)
- Wikimedia 90-day pageviews enrichment
- Audiala Open Travel Data matching and PageRank
- Comparative ranking variants (Variant A, B, C, D)
- Top-20 outputs and failure case analysis
"""

from __future__ import annotations

import asyncio
import csv
import json
import math
import os
import re
import sys
import time
import urllib.parse
from dataclasses import asdict, dataclass, field
from typing import Any
from uuid import UUID, uuid4

import httpx

# Ensure backend modules are importable
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
BACKEND_DIR = os.path.join(PROJECT_ROOT, "backend")
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

from app.models.entities import Place, PlaceSource, PlaceTag
from app.schemas.recommendation import DiscoveryCategory
from app.services.openstreetmap_places_service import (
    OpenStreetMapNearbyPlace,
    OpenStreetMapPlacesService,
)
from app.services.place_deduplication_service import (
    deduplicate_places,
    haversine_distance_meters,
)
from app.services.place_suitability_service import (
    AccessConfidence,
    evaluate_access_confidence,
    is_traveller_suitable,
)

CACHE_DIR = os.path.join(os.path.dirname(__file__), "cache")
DATA_DIR = os.path.join(os.path.dirname(__file__), "data")
RESULTS_DIR = os.path.join(os.path.dirname(__file__), "results")

os.makedirs(CACHE_DIR, exist_ok=True)
os.makedirs(DATA_DIR, exist_ok=True)
os.makedirs(RESULTS_DIR, exist_ok=True)

USER_AGENT = "YatraCanvas-Experiment/0.1 (https://yatracanvas.org; info@yatracanvas.org)"

TEST_CITIES = {
    "jaipur": {"name": "Jaipur", "lat": 26.9124, "lon": 75.7873, "radius": 10000},
    "ahmedabad": {"name": "Ahmedabad", "lat": 23.0225, "lon": 72.5714, "radius": 10000},
    "surat": {"name": "Surat", "lat": 21.1702, "lon": 72.8311, "radius": 10000},
    "delhi": {"name": "Delhi", "lat": 28.6139, "lon": 77.2090, "radius": 12000},
    "varanasi": {"name": "Varanasi", "lat": 25.3176, "lon": 82.9739, "radius": 8000},
}


def load_json(filepath: str) -> Any | None:
    if os.path.exists(filepath):
        try:
            with open(filepath, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return None
    return None


def save_json(filepath: str, data: Any) -> None:
    with open(filepath, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


# =====================================================================
# STEP 1: CANDIDATE DISCOVERY (Overpass + Deduplication + Suitability)
# =====================================================================

OVERPASS_ENDPOINTS = [
    "https://lz4.overpass-api.de/api/interpreter",
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]

async def fetch_city_candidates(city_key: str, city_meta: dict[str, Any]) -> dict[str, Any]:
    cache_path = os.path.join(CACHE_DIR, f"osm_candidates_{city_key}.json")
    cached = load_json(cache_path)
    if cached is not None:
        print(f"[{city_meta['name']}] Loaded raw OSM candidates from cache ({len(cached['raw_elements'])} elements).")
        return cached

    print(f"[{city_meta['name']}] Querying Overpass API...")
    categories = [
        DiscoveryCategory.RELIGIOUS,
        DiscoveryCategory.FOOD,
        DiscoveryCategory.TOURISM,
        DiscoveryCategory.CAFES,
        DiscoveryCategory.HERITAGE,
    ]

    service_builder = OpenStreetMapPlacesService(
        api_url="https://lz4.overpass-api.de/api/interpreter",
        timeout_seconds=45.0,
        radius_meters=city_meta["radius"],
    )

    query = service_builder._build_multi_category_query(
        latitude=city_meta["lat"],
        longitude=city_meta["lon"],
        categories=categories,
        limit_per_category=60,
    )
    query_full = query.replace("out center", "out body center")

    raw_elements = None
    for endpoint in OVERPASS_ENDPOINTS:
        print(f"[{city_meta['name']}] Trying Overpass endpoint: {endpoint}")
        for attempt in range(3):
            try:
                srv = OpenStreetMapPlacesService(api_url=endpoint, timeout_seconds=45.0, radius_meters=city_meta["radius"])
                resp = await srv._request(query_full)
                if resp.status_code == 200:
                    payload = resp.json()
                    raw_elements = payload.get("elements", [])
                    break
                elif resp.status_code == 429:
                    retry_after = int(resp.headers.get("Retry-After", "5"))
                    wait_time = max(retry_after, 5 * (attempt + 1))
                    print(f"[{city_meta['name']}] 429 Rate limited on {endpoint}. Waiting {wait_time}s...")
                    await asyncio.sleep(wait_time)
                else:
                    print(f"[{city_meta['name']}] Endpoint {endpoint} returned status {resp.status_code}")
                    await asyncio.sleep(3)
            except Exception as e:
                print(f"[{city_meta['name']}] Error with {endpoint} (attempt {attempt+1}): {e}")
                await asyncio.sleep(3)
        if raw_elements is not None:
            break

    if raw_elements is None:
        raise RuntimeError(f"Failed to fetch OSM data for {city_meta['name']} across all endpoints.")

    result = {
        "city_key": city_key,
        "city_name": city_meta["name"],
        "raw_elements": raw_elements,
    }
    save_json(cache_path, result)
    print(f"[{city_meta['name']}] Retrieved {len(raw_elements)} elements from Overpass.")
    # Respectful pause between city queries
    await asyncio.sleep(4.0)
    return result



def process_candidates(city_key: str, city_meta: dict[str, Any], raw_data: dict[str, Any]) -> dict[str, Any]:
    """Applies YatraCanvas normalization, deduplication, and traveller-suitability."""
    raw_elements = raw_data["raw_elements"]
    service = OpenStreetMapPlacesService(api_url="", radius_meters=city_meta["radius"])
    
    raw_places: list[OpenStreetMapNearbyPlace] = []
    for raw in raw_elements:
        norm = service._normalize(raw)
        if norm is not None:
            raw_places.append(norm)

    # Map to YatraCanvas Place and PlaceSource instances
    candidates_by_id: dict[str, dict[str, Any]] = {}
    categories = [
        DiscoveryCategory.RELIGIOUS,
        DiscoveryCategory.FOOD,
        DiscoveryCategory.TOURISM,
        DiscoveryCategory.CAFES,
        DiscoveryCategory.HERITAGE,
    ]

    for p in raw_places:
        matched_cats = [c.value for c in categories if service._matches_filter(p, c)]
        if not matched_cats:
            # Fallback based on amenity
            if p.tags.get("amenity") in ("cafe", "restaurant", "fast_food"):
                matched_cats = ["food"]
            elif p.tags.get("tourism") or p.tags.get("historic"):
                matched_cats = ["tourism"]
            else:
                continue

        primary_cat = matched_cats[0]
        place_id = uuid4()
        candidates_by_id[p.external_place_id] = {
            "id": str(place_id),
            "external_place_id": p.external_place_id,
            "name": p.name,
            "category": primary_cat,
            "matched_categories": matched_cats,
            "latitude": p.latitude,
            "longitude": p.longitude,
            "tags": p.tags,
            "source_url": p.source_url,
        }

    # Convert to Place and PlaceSource for YatraCanvas deduplicator
    place_objs = []
    source_objs = []
    fake_city_id = uuid4()
    for item in candidates_by_id.values():
        p_obj = Place(
            id=UUID(item["id"]),
            city_id=fake_city_id,
            name=item["name"],
            category=item["category"],
            latitude=item["latitude"],
            longitude=item["longitude"],
            rating=None,
            review_count=0,
            is_popular=False,
            is_heritage=("heritage" in item["matched_categories"]),
            is_local_speciality=False,
        )
        s_obj = PlaceSource(
            id=uuid4(),
            place_id=p_obj.id,
            source="openstreetmap",
            external_place_id=item["external_place_id"],
            source_url=item["source_url"],
            last_fetched_at=time.strftime("%Y-%m-%dT%H:%M:%SZ"),
        )
        place_objs.append(p_obj)
        source_objs.append(s_obj)

    # 1. Canonical & Spatial Deduplication
    deduped = deduplicate_places(places=place_objs, place_sources=source_objs)
    duplicates_removed = len(place_objs) - len(deduped)
    deduped_id_set = {str(p.id) for p in deduped}

    # 2. Traveller Suitability Filtering
    suitable_candidates = []
    suitability_filtered_count = 0
    
    for item in candidates_by_id.values():
        if item["id"] not in deduped_id_set:
            continue
        
        tags_set = set(item["tags"].keys()) | set(item["tags"].values())
        suitable, access_conf = is_traveller_suitable(
            name=item["name"],
            category=item["category"],
            tags=tags_set,
        )
        if not suitable:
            suitability_filtered_count += 1
            continue
        
        item["access_confidence"] = access_conf.value
        suitable_candidates.append(item)

    return {
        "city_key": city_key,
        "city_name": city_meta["name"],
        "total_raw": len(raw_places),
        "duplicates_removed": duplicates_removed,
        "suitability_filtered": suitability_filtered_count,
        "final_candidates": suitable_candidates,
    }


# =====================================================================
# STEP 2: INSPECT OSM METADATA COVERAGE
# =====================================================================

def analyze_osm_metadata(candidates: list[dict[str, Any]]) -> dict[str, Any]:
    total = len(candidates)
    if total == 0:
        return {}

    counts = {
        "wikidata": 0,
        "wikipedia": 0,
        "website": 0,
        "tourism": 0,
        "historic": 0,
        "heritage": 0,
        "unesco": 0,
        "opening_hours": 0,
    }

    category_dist: dict[str, int] = {}
    for c in candidates:
        cat = c["category"]
        category_dist[cat] = category_dist.get(cat, 0) + 1
        tags = c["tags"]

        if tags.get("wikidata"):
            counts["wikidata"] += 1
        if tags.get("wikipedia"):
            counts["wikipedia"] += 1
        if tags.get("website") or tags.get("contact:website"):
            counts["website"] += 1
        if tags.get("tourism"):
            counts["tourism"] += 1
        if tags.get("historic") and tags.get("historic") != "no":
            counts["historic"] += 1
        if tags.get("heritage") and tags.get("heritage") != "no":
            counts["heritage"] += 1
        if tags.get("unesco") or "unesco" in tags.get("heritage:operator", "").lower():
            counts["unesco"] += 1
        if tags.get("opening_hours"):
            counts["opening_hours"] += 1

    percentages = {
        k: f"{v} ({v / total * 100:.1f}%)" for k, v in counts.items()
    }
    return {
        "total_candidates": total,
        "category_distribution": category_dist,
        "counts": counts,
        "percentages": percentages,
    }


# =====================================================================
# STEP 3: WIKIDATA ENRICHMENT
# =====================================================================

WIKIDATA_CACHE_FILE = os.path.join(CACHE_DIR, "wikidata_cache.json")

async def enrich_with_wikidata(all_qids: set[str]) -> dict[str, dict[str, Any]]:
    cache = load_json(WIKIDATA_CACHE_FILE) or {}
    missing_qids = [q for q in all_qids if q not in cache]
    
    if missing_qids:
        print(f"Fetching {len(missing_qids)} missing Wikidata entities in batches of 50...")
        async with httpx.AsyncClient(timeout=25.0, headers={"User-Agent": USER_AGENT}) as client:
            batch_size = 50
            for i in range(0, len(missing_qids), batch_size):
                batch = missing_qids[i:i + batch_size]
                params = {
                    "action": "wbgetentities",
                    "ids": "|".join(batch),
                    "props": "sitelinks|claims|labels|descriptions",
                    "languages": "en",
                    "format": "json",
                }
                try:
                    r = await client.get("https://www.wikidata.org/w/api.php", params=params)
                    if r.status_code == 200:
                        entities = r.json().get("entities", {})
                        for qid, ent in entities.items():
                            if "missing" in ent:
                                cache[qid] = {"missing": True}
                                continue
                            
                            sitelinks_dict = ent.get("sitelinks", {})
                            sitelinks_count = len(sitelinks_dict)
                            en_wiki_title = sitelinks_dict.get("enwiki", {}).get("title")

                            claims = ent.get("claims", {})
                            
                            # P31: instance of
                            instance_of = []
                            for c in claims.get("P31", []):
                                val = c.get("mainsnak", {}).get("datavalue", {}).get("value")
                                if isinstance(val, dict) and "id" in val:
                                    instance_of.append(val["id"])

                            # P1435: heritage designation
                            heritage_designation = []
                            for c in claims.get("P1435", []):
                                val = c.get("mainsnak", {}).get("datavalue", {}).get("value")
                                if isinstance(val, dict) and "id" in val:
                                    heritage_designation.append(val["id"])

                            # P856: official website
                            official_website = None
                            for c in claims.get("P856", []):
                                val = c.get("mainsnak", {}).get("datavalue", {}).get("value")
                                if isinstance(val, str):
                                    official_website = val
                                    break

                            # P373: Commons category
                            commons_category = None
                            for c in claims.get("P373", []):
                                val = c.get("mainsnak", {}).get("datavalue", {}).get("value")
                                if isinstance(val, str):
                                    commons_category = val
                                    break

                            cache[qid] = {
                                "qid": qid,
                                "label_en": ent.get("labels", {}).get("en", {}).get("value"),
                                "description_en": ent.get("descriptions", {}).get("en", {}).get("value"),
                                "sitelinks_count": sitelinks_count,
                                "en_wiki_title": en_wiki_title,
                                "instance_of": instance_of,
                                "heritage_designation": heritage_designation,
                                "official_website": official_website,
                                "commons_category": commons_category,
                            }
                    await asyncio.sleep(0.1)  # Respectful pace
                except Exception as exc:
                    print(f"Error fetching Wikidata batch: {exc}")
        
        save_json(WIKIDATA_CACHE_FILE, cache)

    return cache


# =====================================================================
# STEP 4: WIKIPEDIA PAGEVIEWS EXPERIMENT
# =====================================================================

PAGEVIEWS_CACHE_FILE = os.path.join(CACHE_DIR, "pageviews_cache.json")

async def enrich_with_pageviews(articles: set[str]) -> dict[str, int]:
    cache = load_json(PAGEVIEWS_CACHE_FILE) or {}
    missing = [a for a in articles if a and a not in cache]
    
    if missing:
        print(f"Fetching 90-day pageviews for {len(missing)} Wikipedia articles...")
        # 90-day window: 2026-05-01 to 2026-07-31
        start_date = "20260501"
        end_date = "20260731"
        
        async with httpx.AsyncClient(timeout=15.0, headers={"User-Agent": USER_AGENT}) as client:
            for art in missing:
                # Normalize article title for URL
                norm_art = art.replace(" ", "_")
                quoted_art = urllib.parse.quote(norm_art, safe="")
                url = f"https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/en.wikipedia.org/all-access/user/{quoted_art}/monthly/{start_date}/{end_date}"
                try:
                    r = await client.get(url)
                    if r.status_code == 200:
                        data = r.json()
                        total_views = sum(item.get("views", 0) for item in data.get("items", []))
                        cache[art] = total_views
                    elif r.status_code == 404:
                        cache[art] = 0
                    elif r.status_code == 429:
                        retry_after = int(r.headers.get("Retry-After", "2"))
                        print(f"Rate limited by Wikimedia. Sleeping {retry_after}s...")
                        await asyncio.sleep(retry_after)
                    else:
                        cache[art] = 0
                    await asyncio.sleep(0.05)  # 50ms politeness delay
                except Exception as exc:
                    print(f"Error fetching pageviews for {art}: {exc}")
                    cache[art] = 0

        save_json(PAGEVIEWS_CACHE_FILE, cache)

    return cache


# =====================================================================
# STEP 5: AUDIALA DATASET MATCHING
# =====================================================================

def load_audiala_data() -> list[dict[str, Any]]:
    audiala_file = os.path.join(DATA_DIR, "audiala_india.json")
    if not os.path.exists(audiala_file):
        raise RuntimeError("audiala_india.json not found! Run fetch_audiala.py first.")
    with open(audiala_file, "r", encoding="utf-8") as f:
        return json.load(f)


def normalize_name_for_match(name: str) -> str:
    cleaned = re.sub(r"[^a-zA-Z0-9\s]", " ", name.lower())
    tokens = [w for w in cleaned.split() if w not in {"the", "of", "and", "in", "at", "jaipur", "delhi", "surat", "ahmedabad", "varanasi"}]
    return " ".join(sorted(tokens))


def match_audiala_poi(
    candidate: dict[str, Any],
    audiala_by_qid: dict[str, dict[str, Any]],
    audiala_places: list[dict[str, Any]],
) -> dict[str, Any] | None:
    tags = candidate["tags"]
    cand_qid = tags.get("wikidata")
    
    # Priority 1: Exact Wikidata QID match
    if cand_qid and cand_qid in audiala_by_qid:
        aud = audiala_by_qid[cand_qid]
        return {
            "matched": True,
            "match_method": "exact_qid",
            "match_confidence": 1.0,
            "audiala_record": aud,
        }

    # Priority 2: Coordinate proximity (<= 150m) + token overlap
    c_lat = candidate["latitude"]
    c_lon = candidate["longitude"]
    c_norm = normalize_name_for_match(candidate["name"])
    c_tokens = set(c_norm.split())

    best_match = None
    best_dist = 999999.0

    for aud in audiala_places:
        a_lat = aud.get("latitude")
        a_lon = aud.get("longitude")
        if a_lat is None or a_lon is None:
            continue
        dist = haversine_distance_meters(c_lat, c_lon, a_lat, a_lon)
        if dist <= 250:
            a_norm = normalize_name_for_match(aud.get("name_en", ""))
            a_tokens = set(a_norm.split())
            if not c_tokens or not a_tokens:
                continue
            overlap = len(c_tokens & a_tokens) / max(len(c_tokens), len(a_tokens))
            if overlap >= 0.5:
                if dist < best_dist:
                    best_dist = dist
                    best_match = (aud, dist, overlap)

    if best_match:
        aud, dist, overlap = best_match
        method = "coord_exact_name" if dist <= 100 and overlap >= 0.7 else "coord_fuzzy_name"
        conf = 0.9 if method == "coord_exact_name" else 0.75
        return {
            "matched": True,
            "match_method": method,
            "match_confidence": conf,
            "audiala_record": aud,
        }

    return None


# =====================================================================
# STEP 6: EXPERIMENTAL RANKING VARIANTS
# =====================================================================

def score_variant_a_current(c: dict[str, Any]) -> float:
    """Current YatraCanvas logic: category match 40, rating 35 (0), bonuses."""
    score = 40.0
    if c["tags"].get("historic") or c["tags"].get("heritage"):
        score += 8.0
    if c["access_confidence"] == "UNKNOWN":
        score -= 15.0
    return round(score, 1)


def score_variant_b_wikidata(c: dict[str, Any], wd: dict[str, Any] | None) -> tuple[float, str]:
    """Wikidata only: Sitelinks logarithmic scale (0-60) + Heritage (20) + Category (20)."""
    score = 20.0
    reason_parts = ["Category baseline"]
    
    if wd and not wd.get("missing"):
        sitelinks = wd.get("sitelinks_count", 0)
        if sitelinks > 0:
            # log10(sitelinks + 1) / log10(101) * 60
            sl_score = min(1.0, math.log10(sitelinks + 1) / math.log10(101)) * 60.0
            score += sl_score
            reason_parts.append(f"{sitelinks} Wikidata sitelinks (+{sl_score:.1f})")

        # Heritage designation
        heritage = wd.get("heritage_designation", [])
        if heritage or c["tags"].get("historic") or c["tags"].get("heritage"):
            score += 20.0
            reason_parts.append("Heritage / Monument (+20)")
    else:
        # Fallback to OSM tags if no Wikidata
        if c["tags"].get("historic") or c["tags"].get("heritage"):
            score += 15.0
            reason_parts.append("OSM Historic tag (+15)")
        elif c["tags"].get("tourism") == "attraction":
            score += 10.0
            reason_parts.append("OSM Tourism attraction (+10)")

    return round(score, 1), "; ".join(reason_parts)


def score_variant_c_wikipedia(
    c: dict[str, Any],
    wd: dict[str, Any] | None,
    pageviews: int,
) -> tuple[float, str]:
    """Wikidata + Wikipedia: Sitelinks (40) + Pageviews (30) + Heritage (15) + Category (15)."""
    score = 15.0
    reason_parts = ["Category baseline"]

    if wd and not wd.get("missing"):
        sitelinks = wd.get("sitelinks_count", 0)
        if sitelinks > 0:
            sl_score = min(1.0, math.log10(sitelinks + 1) / math.log10(101)) * 40.0
            score += sl_score
            reason_parts.append(f"{sitelinks} sitelinks (+{sl_score:.1f})")

        # Pageviews (90 days)
        if pageviews > 0:
            # Scale log10(views + 1) / log10(100,001) * 30
            pv_score = min(1.0, math.log10(pageviews + 1) / math.log10(100001)) * 30.0
            score += pv_score
            reason_parts.append(f"{pageviews:,} 90d pageviews (+{pv_score:.1f})")

        if wd.get("heritage_designation") or c["tags"].get("historic") or c["tags"].get("heritage"):
            score += 15.0
            reason_parts.append("Heritage landmark (+15)")
    else:
        if c["tags"].get("historic") or c["tags"].get("heritage"):
            score += 15.0
            reason_parts.append("OSM Historic tag (+15)")
        elif c["tags"].get("tourism") == "attraction":
            score += 10.0
            reason_parts.append("OSM Tourism attraction (+10)")

    return round(score, 1), "; ".join(reason_parts)


def score_variant_d_audiala(
    c: dict[str, Any],
    wd: dict[str, Any] | None,
    pageviews: int,
    aud_match: dict[str, Any] | None,
) -> tuple[float, str]:
    """Wikidata + Wikipedia + Audiala: Sitelinks (30) + Pageviews (25) + Audiala PR (20) + Heritage (10) + Baseline (15)."""
    score = 15.0
    reason_parts = ["Category baseline"]

    sitelinks = 0
    if wd and not wd.get("missing"):
        sitelinks = wd.get("sitelinks_count", 0)
    elif aud_match:
        sitelinks = aud_match["audiala_record"].get("sitelinks") or 0

    if sitelinks > 0:
        sl_score = min(1.0, math.log10(sitelinks + 1) / math.log10(101)) * 30.0
        score += sl_score
        reason_parts.append(f"{sitelinks} sitelinks (+{sl_score:.1f})")

    if pageviews > 0:
        pv_score = min(1.0, math.log10(pageviews + 1) / math.log10(100001)) * 25.0
        score += pv_score
        reason_parts.append(f"{pageviews:,} 90d pageviews (+{pv_score:.1f})")

    # Audiala match & PageRank
    if aud_match:
        rec = aud_match["audiala_record"]
        pr = rec.get("wikidata_pagerank")
        if pr is not None and pr > 0:
            # danker PageRank for top landmarks ranges from ~3.0 to ~10.0
            pr_score = min(1.0, pr / 10.0) * 20.0
            score += pr_score
            reason_parts.append(f"Audiala PR {pr:.2f} (+{pr_score:.1f})")
        else:
            score += 10.0
            reason_parts.append("Audiala editorial guide (+10)")

    # Heritage
    has_heritage = (
        (wd and wd.get("heritage_designation"))
        or c["tags"].get("historic")
        or c["tags"].get("heritage")
    )
    if has_heritage:
        score += 10.0
        reason_parts.append("Heritage monument (+10)")

    return round(score, 1), "; ".join(reason_parts)


# =====================================================================
# MAIN EXPERIMENT RUNNER
# =====================================================================

async def run_city_experiment(city_key: str, city_meta: dict[str, Any], audiala_data: list[dict[str, Any]]) -> dict[str, Any]:
    print(f"\n=======================================================")
    print(f"RUNNING EXPERIMENT FOR: {city_meta['name'].upper()}")
    print(f"=======================================================")

    # Step 1: Candidate Discovery & Deduplication & Suitability
    raw_data = await fetch_city_candidates(city_key, city_meta)
    processed = process_candidates(city_key, city_meta, raw_data)
    candidates = processed["final_candidates"]
    print(f"[{city_meta['name']}] Raw: {processed['total_raw']}, Dupes removed: {processed['duplicates_removed']}, Suitability dropped: {processed['suitability_filtered']}, Final candidates: {len(candidates)}")

    # Step 2: OSM Metadata Analysis
    osm_analysis = analyze_osm_metadata(candidates)
    print(f"[{city_meta['name']}] OSM Metadata Coverage:")
    for k, v in osm_analysis["percentages"].items():
        print(f"    {k:15}: {v}")

    # Step 3: Collect Wikidata QIDs & Enrich
    qids = {c["tags"]["wikidata"] for c in candidates if c["tags"].get("wikidata")}
    print(f"[{city_meta['name']}] Found {len(qids)} unique Wikidata QIDs from OSM tags.")
    wd_cache = await enrich_with_wikidata(qids)

    # Step 4: Collect Wikipedia articles & Enrich Pageviews
    articles = set()
    for c in candidates:
        # Check OSM wikipedia tag
        wiki_tag = c["tags"].get("wikipedia")
        if wiki_tag:
            # Format is usually 'en:Article Title' or 'hi:...'
            if wiki_tag.startswith("en:"):
                articles.add(wiki_tag[3:])
            elif ":" not in wiki_tag:
                articles.add(wiki_tag)
        # Check Wikidata sitelink title
        qid = c["tags"].get("wikidata")
        if qid and qid in wd_cache:
            en_title = wd_cache[qid].get("en_wiki_title")
            if en_title:
                articles.add(en_title)

    print(f"[{city_meta['name']}] Found {len(articles)} distinct English Wikipedia articles.")
    pv_cache = await enrich_with_pageviews(articles)

    # Step 5: Audiala Matching
    audiala_by_qid = {a["wikidata_id"]: a for a in audiala_data if a.get("wikidata_id")}
    audiala_matches: dict[str, dict[str, Any]] = {}
    
    for c in candidates:
        match = match_audiala_poi(c, audiala_by_qid, audiala_data)
        if match:
            audiala_matches[c["id"]] = match

    print(f"[{city_meta['name']}] Matched {len(audiala_matches)} candidates with Audiala Open Data ({len(audiala_matches) / max(len(candidates), 1) * 100:.1f}%).")

    # Step 6: Compute Scores for Variants A, B, C, D
    scored_candidates = []
    for c in candidates:
        cid = c["id"]
        qid = c["tags"].get("wikidata")
        wd = wd_cache.get(qid) if qid else None
        
        # Get article title
        art_title = None
        if c["tags"].get("wikipedia", "").startswith("en:"):
            art_title = c["tags"]["wikipedia"][3:]
        elif wd and wd.get("en_wiki_title"):
            art_title = wd.get("en_wiki_title")
        
        views = pv_cache.get(art_title, 0) if art_title else 0
        aud = audiala_matches.get(cid)

        score_a = score_variant_a_current(c)
        score_b, reason_b = score_variant_b_wikidata(c, wd)
        score_c, reason_c = score_variant_c_wikipedia(c, wd, views)
        score_d, reason_d = score_variant_d_audiala(c, wd, views, aud)

        sitelinks = wd.get("sitelinks_count", 0) if wd else (aud["audiala_record"].get("sitelinks", 0) if aud else 0)
        aud_pr = aud["audiala_record"].get("wikidata_pagerank") if aud else None

        scored_candidates.append({
            "id": cid,
            "external_id": c["external_place_id"],
            "name": c["name"],
            "category": c["category"],
            "matched_categories": c["matched_categories"],
            "latitude": c["latitude"],
            "longitude": c["longitude"],
            "wikidata_id": qid,
            "en_wiki_title": art_title,
            "sitelinks": sitelinks,
            "pageviews_90d": views,
            "audiala_match": bool(aud),
            "audiala_pagerank": aud_pr,
            "audiala_method": aud["match_method"] if aud else None,
            "score_a": score_a,
            "score_b": score_b,
            "reason_b": reason_b,
            "score_c": score_c,
            "reason_c": reason_c,
            "score_d": score_d,
            "reason_d": reason_d,
        })

    # Sort rankings
    ranking_a = sorted(scored_candidates, key=lambda x: x["score_a"], reverse=True)
    ranking_b = sorted(scored_candidates, key=lambda x: x["score_b"], reverse=True)
    ranking_c = sorted(scored_candidates, key=lambda x: x["score_c"], reverse=True)
    ranking_d = sorted(scored_candidates, key=lambda x: x["score_d"], reverse=True)

    city_results = {
        "city_key": city_key,
        "city_name": city_meta["name"],
        "metadata_stats": osm_analysis,
        "audiala_matched_count": len(audiala_matches),
        "candidates_count": len(candidates),
        "top_20_variant_a": ranking_a[:20],
        "top_20_variant_b": ranking_b[:20],
        "top_20_variant_c": ranking_c[:20],
        "top_20_variant_d": ranking_d[:20],
        "all_candidates_scored": scored_candidates,
    }

    results_file = os.path.join(RESULTS_DIR, f"{city_key}.json")
    save_json(results_file, city_results)
    print(f"[{city_meta['name']}] Saved full results to {results_file}")
    return city_results


async def main():
    print("=================================================================")
    print("YATRACANVAS POI IMPORTANCE REAL-DATA FEASIBILITY EXPERIMENT")
    print("=================================================================")
    audiala_data = load_audiala_data()
    print(f"Loaded {len(audiala_data)} Audiala India records.")

    all_results = {}
    for city_key, city_meta in TEST_CITIES.items():
        all_results[city_key] = await run_city_experiment(city_key, city_meta, audiala_data)

    print("\nAll 5 cities processed successfully!")


if __name__ == "__main__":
    asyncio.run(main())
