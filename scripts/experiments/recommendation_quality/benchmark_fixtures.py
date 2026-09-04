"""Deterministic benchmark fixtures for multi-city recommendation quality evaluation.

Provides candidate pools and ground-truth reference sets for:
1. Jaipur (heritage, sightseeing)
2. Varanasi (religious, temples, sightseeing, ghats)
3. Surat (food - including institutional/SVNIT regression fixtures)
4. Ahmedabad (food + heritage, and heritage)
5. Udaipur (sightseeing, heritage)
6. Mumbai (sightseeing + food + cafes)
7. Delhi (heritage + food + sightseeing)

Operates 100% offline using local datasets and deterministic fixtures.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from typing import Any
from uuid import UUID, uuid5, NAMESPACE_DNS

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
POI_RESULTS_DIR = os.path.join(PROJECT_ROOT, "scripts/experiments/poi_importance/results")
AUDIALA_DATA_PATH = os.path.join(PROJECT_ROOT, "backend/app/data/audiala_places.json")


def _deterministic_uuid(key: str) -> UUID:
    return uuid5(NAMESPACE_DNS, key)


@dataclass(frozen=True)
class CandidatePOI:
    id: UUID
    name: str
    category: str
    latitude: float
    longitude: float
    rating: float | None = None
    review_count: int = 0
    is_popular: bool = False
    is_local_speciality: bool = False
    is_heritage: bool = False
    importance_score: float | None = None
    wikidata_id: str | None = None
    tags: dict[str, str] = field(default_factory=dict)
    # Ground truth annotations for evaluation
    is_institution_or_restricted: bool = False
    is_gold_major_poi: bool = False
    relevance_labels: dict[str, bool] = field(default_factory=dict)


@dataclass(frozen=True)
class BenchmarkScenario:
    city_key: str
    city_name: str
    latitude: float
    longitude: float
    purposes: list[str]
    interests: list[str]
    categories: list[str]
    gold_major_pois: list[str]
    candidates: list[CandidatePOI]
    expected_characteristics: str


def load_audiala_data() -> list[dict[str, Any]]:
    if os.path.exists(AUDIALA_DATA_PATH):
        with open(AUDIALA_DATA_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    return []


def load_poi_importance_results(city_key: str) -> list[dict[str, Any]]:
    filepath = os.path.join(POI_RESULTS_DIR, f"{city_key}.json")
    if os.path.exists(filepath):
        with open(filepath, "r", encoding="utf-8") as f:
            data = json.load(f)
            return data.get("all_candidates_scored", [])
    return []


def _create_candidates_from_poi_data(
    city_key: str,
    poi_items: list[dict[str, Any]],
    gold_names: set[str],
) -> list[CandidatePOI]:
    candidates: list[CandidatePOI] = []
    for item in poi_items:
        name = item.get("name", "").strip()
        if not name:
            continue
        cid = _deterministic_uuid(f"{city_key}:{name}:{item.get('id', '')}")
        cat = item.get("category", "tourism")
        lat = float(item.get("latitude", 0.0))
        lon = float(item.get("longitude", 0.0))
        score_d = float(item.get("score_d", 0.0))
        imp_score = round(min(1.0, score_d / 50.0), 3) if score_d > 0 else None
        
        # Tags reconstruction
        tags: dict[str, str] = {cat: "yes"}
        if cat == "heritage":
            tags["historic"] = "yes"
            tags["heritage"] = "yes"
        elif cat == "religious":
            tags["amenity"] = "place_of_worship"
        elif cat == "food":
            tags["amenity"] = "restaurant"
        elif cat == "cafes":
            tags["amenity"] = "cafe"
        elif cat == "tourism":
            tags["tourism"] = "attraction"

        is_gold = any(g.casefold() in name.casefold() for g in gold_names)

        candidates.append(
            CandidatePOI(
                id=cid,
                name=name,
                category=cat,
                latitude=lat,
                longitude=lon,
                importance_score=imp_score,
                wikidata_id=item.get("wikidata_id"),
                tags=tags,
                is_gold_major_poi=is_gold,
            )
        )
    return candidates


def get_all_benchmark_scenarios() -> list[BenchmarkScenario]:
    """Assemble all multi-city benchmark scenarios."""
    scenarios: list[BenchmarkScenario] = []

    # -------------------------------------------------------------------------
    # 1. JAIPUR (Heritage, Sightseeing)
    # -------------------------------------------------------------------------
    jaipur_gold = [
        "Amber Fort",
        "Hawa Mahal",
        "City Palace",
        "Jantar Mantar",
        "Nahargarh Fort",
        "Jaigarh Fort",
        "Jal Mahal",
        "Albert Hall Museum",
    ]
    jaipur_raw = load_poi_importance_results("jaipur")
    jaipur_candidates = _create_candidates_from_poi_data("jaipur", jaipur_raw, set(jaipur_gold))
    
    # Ensure all gold attractions exist in candidates with appropriate metadata
    jaipur_gold_coords = {
        "Amber Fort": (26.9863, 75.8507, 0.95),
        "Hawa Mahal": (26.9239, 75.8269, 0.92),
        "City Palace": (26.9255, 75.8236, 0.90),
        "Jantar Mantar": (26.9248, 75.8246, 0.88),
        "Nahargarh Fort": (26.9374, 75.8157, 0.85),
        "Jaigarh Fort": (26.9847, 75.8454, 0.80),
        "Jal Mahal": (26.9535, 75.8461, 0.82),
        "Albert Hall Museum": (26.9116, 75.8195, 0.84),
    }
    existing_j_names = {c.name for c in jaipur_candidates}
    for g_name, (glat, glon, gimp) in jaipur_gold_coords.items():
        if not any(g_name.casefold() in n.casefold() for n in existing_j_names):
            jaipur_candidates.append(
                CandidatePOI(
                    id=_deterministic_uuid(f"jaipur:{g_name}"),
                    name=g_name,
                    category="heritage",
                    latitude=glat,
                    longitude=glon,
                    importance_score=gimp,
                    is_heritage=True,
                    is_popular=True,
                    is_gold_major_poi=True,
                    tags={"historic": "yes", "tourism": "attraction", "heritage": "yes"},
                )
            )

    # Add duplicate gate scenario for Jaipur:
    # "Ajmeri Gate" and a near-duplicate "Ajmeri Gate Jaipur" 35m away
    jaipur_candidates.append(
        CandidatePOI(
            id=_deterministic_uuid("jaipur:Ajmeri Gate"),
            name="Ajmeri Gate",
            category="heritage",
            latitude=26.9174,
            longitude=75.8202,
            importance_score=0.45,
            is_heritage=True,
            tags={"historic": "gate"},
        )
    )
    jaipur_candidates.append(
        CandidatePOI(
            id=_deterministic_uuid("jaipur:Ajmeri Gate Jaipur (Duplicate)"),
            name="Ajmeri Gate Jaipur",
            category="heritage",
            latitude=26.9176,
            longitude=75.8204,
            importance_score=0.40,
            is_heritage=True,
            tags={"historic": "gate"},
        )
    )

    scenarios.append(
        BenchmarkScenario(
            city_key="jaipur",
            city_name="Jaipur",
            latitude=26.9124,
            longitude=75.7873,
            purposes=["heritage"],
            interests=["sightseeing"],
            categories=["heritage", "tourism"],
            gold_major_pois=jaipur_gold,
            candidates=jaipur_candidates,
            expected_characteristics="Major forts and palaces rank high; near-duplicate gates merged; high intent precision.",
        )
    )

    # -------------------------------------------------------------------------
    # 2. VARANASI (Religious, Temples, Sightseeing, Ghats)
    # -------------------------------------------------------------------------
    varanasi_gold = [
        "Kashi Vishwanath Temple",
        "Dashashwamedh Ghat",
        "Assi Ghat",
        "Manikarnika Ghat",
        "Sarnath Deer Park & Dhamek Stupa",
        "Ramnagar Fort",
        "Sankat Mochan Hanuman Temple",
    ]
    varanasi_raw = load_poi_importance_results("varanasi")
    varanasi_candidates = _create_candidates_from_poi_data("varanasi", varanasi_raw, set(varanasi_gold))
    
    varanasi_gold_coords = {
        "Kashi Vishwanath Temple": (25.3108, 83.0106, "religious", 0.96),
        "Dashashwamedh Ghat": (25.3072, 83.0103, "heritage", 0.90),
        "Assi Ghat": (25.2895, 83.0065, "heritage", 0.88),
        "Manikarnika Ghat": (25.3109, 83.0141, "heritage", 0.86),
        "Sarnath Deer Park & Dhamek Stupa": (25.3810, 83.0245, "heritage", 0.91),
        "Ramnagar Fort": (25.2695, 83.0251, "heritage", 0.82),
        "Sankat Mochan Hanuman Temple": (25.2815, 82.9985, "religious", 0.85),
    }
    existing_v_names = {c.name for c in varanasi_candidates}
    for g_name, (glat, glon, gcat, gimp) in varanasi_gold_coords.items():
        if not any(g_name.casefold() in n.casefold() for n in existing_v_names):
            varanasi_candidates.append(
                CandidatePOI(
                    id=_deterministic_uuid(f"varanasi:{g_name}"),
                    name=g_name,
                    category=gcat,
                    latitude=glat,
                    longitude=glon,
                    importance_score=gimp,
                    is_heritage=(gcat == "heritage"),
                    is_popular=True,
                    is_gold_major_poi=True,
                    tags={"amenity": "place_of_worship"} if gcat == "religious" else {"historic": "ghat"},
                )
            )

    scenarios.append(
        BenchmarkScenario(
            city_key="varanasi",
            city_name="Varanasi",
            latitude=25.3176,
            longitude=82.9739,
            purposes=["religious"],
            interests=["temples", "sightseeing", "ghats"],
            categories=["religious", "heritage", "tourism"],
            gold_major_pois=varanasi_gold,
            candidates=varanasi_candidates,
            expected_characteristics="Major temples and sacred ghats rank strongly; cafes do not dominate temple trip; distinct ghats preserved.",
        )
    )

    # -------------------------------------------------------------------------
    # 3. SURAT (Food - including SVNIT institutional regression fixtures)
    # -------------------------------------------------------------------------
    surat_gold = [
        "Sasumaa Gujarati Thali",
        "Kansar Gujarati Thali",
        "Jaani Locho",
        "Rander Biryani House",
        "Dumas Beach Food Plaza",
    ]
    surat_raw = load_poi_importance_results("surat")
    surat_candidates = _create_candidates_from_poi_data("surat", surat_raw, set(surat_gold))

    # Add public visitor-relevant food places
    public_surat_food = [
        CandidatePOI(
            id=_deterministic_uuid("surat:Sasumaa Gujarati Thali"),
            name="Sasumaa Gujarati Thali",
            category="food",
            latitude=21.1710,
            longitude=72.8315,
            rating=4.6,
            review_count=1850,
            is_popular=True,
            is_local_speciality=True,
            is_gold_major_poi=True,
            tags={"amenity": "restaurant", "cuisine": "gujarati", "access": "yes"},
        ),
        CandidatePOI(
            id=_deterministic_uuid("surat:Kansar Gujarati Thali"),
            name="Kansar Gujarati Thali",
            category="food",
            latitude=21.1730,
            longitude=72.8320,
            rating=4.5,
            review_count=1400,
            is_popular=True,
            is_local_speciality=True,
            is_gold_major_poi=True,
            tags={"amenity": "restaurant", "cuisine": "gujarati", "access": "public"},
        ),
        CandidatePOI(
            id=_deterministic_uuid("surat:Jaani Locho"),
            name="Jaani Locho",
            category="food",
            latitude=21.1720,
            longitude=72.8330,
            rating=4.7,
            review_count=2200,
            is_popular=True,
            is_local_speciality=True,
            is_gold_major_poi=True,
            tags={"amenity": "fast_food", "cuisine": "gujarati", "snack": "locho"},
        ),
        CandidatePOI(
            id=_deterministic_uuid("surat:Rander Biryani House"),
            name="Rander Biryani House",
            category="food",
            latitude=21.2150,
            longitude=72.7950,
            rating=4.4,
            review_count=890,
            is_local_speciality=True,
            is_gold_major_poi=True,
            tags={"amenity": "restaurant", "cuisine": "biryani"},
        ),
        CandidatePOI(
            id=_deterministic_uuid("surat:Dumas Beach Food Plaza"),
            name="Dumas Beach Food Plaza",
            category="food",
            latitude=21.0775,
            longitude=72.7090,
            rating=4.3,
            review_count=1100,
            is_popular=True,
            is_local_speciality=True,
            is_gold_major_poi=True,
            tags={"amenity": "food_court", "cuisine": "street_food"},
        ),
        CandidatePOI(
            id=_deterministic_uuid("surat:Gopal Locho Centre"),
            name="Gopal Locho Centre",
            category="food",
            latitude=21.1760,
            longitude=72.8340,
            rating=4.4,
            review_count=650,
            is_local_speciality=True,
            tags={"amenity": "fast_food", "cuisine": "gujarati"},
        ),
    ]
    surat_candidates.extend(public_surat_food)

    # REGRESSION FIXTURES: Institutional / Private / Restricted venues
    # Reproduces the SVNIT and similar institutional dining failures
    institutional_surat_fixtures = [
        # Scenario A: Explicit canteen with institutional operator
        CandidatePOI(
            id=_deterministic_uuid("surat:SVNIT Canteen A"),
            name="SVNIT Student Canteen",
            category="food",
            latitude=21.1660,
            longitude=72.7830,
            tags={
                "amenity": "canteen",
                "operator": "Sardar Vallabhbhai National Institute of Technology",
                "building": "university",
            },
            is_institution_or_restricted=True,
        ),
        # Scenario B: Fast food outlet with university operator tag and campus building (no access tag!)
        CandidatePOI(
            id=_deterministic_uuid("surat:SVNIT Food Point"),
            name="SVNIT Food Point",
            category="food",
            latitude=21.1665,
            longitude=72.7835,
            rating=4.0,
            review_count=150,
            tags={
                "amenity": "fast_food",
                "operator": "Sardar Vallabhbhai National Institute of Technology",
                "building": "university",
            },
            is_institution_or_restricted=True,
        ),
        # Scenario C: Campus food court inside institute without access tag
        CandidatePOI(
            id=_deterministic_uuid("surat:Central Campus Dining"),
            name="Central Campus Dining",
            category="food",
            latitude=21.1655,
            longitude=72.7825,
            rating=3.9,
            review_count=90,
            tags={
                "amenity": "food_court",
                "operator": "SVNIT",
                "building": "university",
            },
            is_institution_or_restricted=True,
        ),
        # Scenario D: Hostel mess with student access
        CandidatePOI(
            id=_deterministic_uuid("surat:Hostel 4 Dining Hall"),
            name="Hostel 4 Dining Hall",
            category="food",
            latitude=21.1650,
            longitude=72.7820,
            tags={
                "amenity": "canteen",
                "building": "dormitory",
                "access": "students",
            },
            is_institution_or_restricted=True,
        ),
        # Scenario E: Corporate/Industrial staff cafeteria
        CandidatePOI(
            id=_deterministic_uuid("surat:ONGC Staff Cafeteria"),
            name="ONGC Staff Cafeteria",
            category="food",
            latitude=21.1400,
            longitude=72.7200,
            tags={
                "amenity": "canteen",
                "operator": "Oil and Natural Gas Corporation",
                "access": "employees",
            },
            is_institution_or_restricted=True,
        ),
        # Scenario F: Hospital staff dining room
        CandidatePOI(
            id=_deterministic_uuid("surat:Civil Hospital Staff Mess"),
            name="Civil Hospital Staff Dining Room",
            category="food",
            latitude=21.1850,
            longitude=72.8250,
            tags={
                "amenity": "canteen",
                "building": "hospital",
                "access": "private",
            },
            is_institution_or_restricted=True,
        ),
    ]
    surat_candidates.extend(institutional_surat_fixtures)

    scenarios.append(
        BenchmarkScenario(
            city_key="surat",
            city_name="Surat",
            latitude=21.1702,
            longitude=72.8311,
            purposes=["food"],
            interests=["food"],
            categories=["food", "cafes"],
            gold_major_pois=surat_gold,
            candidates=surat_candidates,
            expected_characteristics="Public visitor-relevant food places; local speciality thalis/locho; zero institutional canteens/messes.",
        )
    )

    # -------------------------------------------------------------------------
    # 4. AHMEDABAD (A: Food + Heritage mixed; B: Heritage only)
    # -------------------------------------------------------------------------
    ahmedabad_gold = [
        "Sabarmati Ashram",
        "Adalaj Stepwell",
        "Sidi Saiyyed Mosque",
        "Sarkhej Roza",
        "Hutheesing Jain Temple",
        "Manek Chowk",
        "Agashiye",
    ]
    ahmedabad_raw = load_poi_importance_results("ahmedabad")
    ahmedabad_candidates = _create_candidates_from_poi_data("ahmedabad", ahmedabad_raw, set(ahmedabad_gold))

    # Add key Ahmedabad heritage and food places if not present
    ahmedabad_extra = [
        CandidatePOI(
            id=_deterministic_uuid("ahmedabad:Sabarmati Ashram"),
            name="Sabarmati Ashram",
            category="heritage",
            latitude=23.0600,
            longitude=72.5808,
            importance_score=0.96,
            is_heritage=True,
            is_popular=True,
            is_gold_major_poi=True,
            tags={"historic": "monument", "tourism": "attraction", "heritage": "yes"},
        ),
        CandidatePOI(
            id=_deterministic_uuid("ahmedabad:Adalaj Stepwell"),
            name="Adalaj Stepwell",
            category="heritage",
            latitude=23.1667,
            longitude=72.5800,
            importance_score=0.90,
            is_heritage=True,
            is_popular=True,
            is_gold_major_poi=True,
            tags={"historic": "stepwell", "heritage": "yes"},
        ),
        CandidatePOI(
            id=_deterministic_uuid("ahmedabad:Sidi Saiyyed Mosque"),
            name="Sidi Saiyyed Mosque",
            category="heritage",
            latitude=23.0268,
            longitude=72.5810,
            importance_score=0.88,
            is_heritage=True,
            is_popular=True,
            is_gold_major_poi=True,
            tags={"historic": "mosque", "heritage": "yes"},
        ),
        CandidatePOI(
            id=_deterministic_uuid("ahmedabad:Manek Chowk"),
            name="Manek Chowk Night Market",
            category="food",
            latitude=23.0246,
            longitude=72.5901,
            rating=4.6,
            review_count=3200,
            is_popular=True,
            is_local_speciality=True,
            is_gold_major_poi=True,
            tags={"amenity": "food_court", "cuisine": "street_food"},
        ),
        CandidatePOI(
            id=_deterministic_uuid("ahmedabad:Agashiye"),
            name="Agashiye Heritage Lounge",
            category="food",
            latitude=23.0270,
            longitude=72.5830,
            rating=4.7,
            review_count=1900,
            is_popular=True,
            is_local_speciality=True,
            is_gold_major_poi=True,
            tags={"amenity": "restaurant", "cuisine": "gujarati_thali"},
        ),
        # Institutional cafeteria regression candidate
        CandidatePOI(
            id=_deterministic_uuid("ahmedabad:IIMA Student Mess"),
            name="IIMA Campus Cafeteria",
            category="food",
            latitude=23.0310,
            longitude=72.5310,
            tags={"amenity": "canteen", "operator": "Indian Institute of Management Ahmedabad", "building": "university"},
            is_institution_or_restricted=True,
        ),
    ]
    for ex in ahmedabad_extra:
        if not any(ex.name.casefold() in c.name.casefold() for c in ahmedabad_candidates):
            ahmedabad_candidates.append(ex)

    # 4A: Mixed Food + Heritage
    scenarios.append(
        BenchmarkScenario(
            city_key="ahmedabad_mixed",
            city_name="Ahmedabad",
            latitude=23.0225,
            longitude=72.5714,
            purposes=["food"],
            interests=["heritage"],
            categories=["food", "heritage"],
            gold_major_pois=ahmedabad_gold,
            candidates=ahmedabad_candidates,
            expected_characteristics="Mixed intent preserves both food and heritage; no institutional canteens; local speciality competitive.",
        )
    )

    # 4B: Heritage only
    scenarios.append(
        BenchmarkScenario(
            city_key="ahmedabad_heritage",
            city_name="Ahmedabad",
            latitude=23.0225,
            longitude=72.5714,
            purposes=["heritage"],
            interests=["sightseeing"],
            categories=["heritage", "tourism"],
            gold_major_pois=["Sabarmati Ashram", "Adalaj Stepwell", "Sidi Saiyyed Mosque", "Sarkhej Roza"],
            candidates=ahmedabad_candidates,
            expected_characteristics="Heritage-only strongly prefers heritage; top historical landmarks dominate.",
        )
    )

    # -------------------------------------------------------------------------
    # 5. UDAIPUR (Sightseeing, Heritage)
    # -------------------------------------------------------------------------
    udaipur_gold = [
        "City Palace Udaipur",
        "Lake Pichola",
        "Bagore Ki Haveli",
        "Saheliyon-ki-Bari",
        "Jagdish Temple",
        "Monsoon Palace",
        "Ambrai Ghat",
    ]
    audiala_items = load_audiala_data()
    udaipur_aud = [a for a in audiala_items if a.get("city_en") == "Udaipur"]
    udaipur_candidates: list[CandidatePOI] = []
    
    for a in udaipur_aud:
        aname = a.get("name_en", "").strip()
        if not aname:
            continue
        pr = a.get("wikidata_pagerank") or 5.0
        imp = round(min(1.0, pr / 10.0), 3)
        cat = "heritage" if "palace" in aname.lower() or "haveli" in aname.lower() or "cenotaph" in aname.lower() else "tourism"
        is_gold = any(g.casefold() in aname.casefold() for g in udaipur_gold)
        udaipur_candidates.append(
            CandidatePOI(
                id=_deterministic_uuid(f"udaipur:{aname}"),
                name=aname,
                category=cat,
                latitude=float(a.get("latitude", 24.5854)),
                longitude=float(a.get("longitude", 73.7125)),
                importance_score=imp,
                wikidata_id=a.get("wikidata_id"),
                is_gold_major_poi=is_gold,
                is_heritage=(cat == "heritage"),
                tags={"historic": "yes"} if cat == "heritage" else {"tourism": "attraction"},
            )
        )

    # Add Udaipur key destinations if missing
    udaipur_defaults = [
        CandidatePOI(
            id=_deterministic_uuid("udaipur:City Palace Udaipur"),
            name="City Palace Udaipur",
            category="heritage",
            latitude=24.5764,
            longitude=73.6835,
            importance_score=0.96,
            is_heritage=True,
            is_popular=True,
            is_gold_major_poi=True,
            tags={"historic": "palace", "tourism": "attraction"},
        ),
        CandidatePOI(
            id=_deterministic_uuid("udaipur:Lake Pichola"),
            name="Lake Pichola",
            category="tourism",
            latitude=24.5700,
            longitude=73.6780,
            importance_score=0.94,
            is_popular=True,
            is_gold_major_poi=True,
            tags={"tourism": "attraction", "natural": "water"},
        ),
        CandidatePOI(
            id=_deterministic_uuid("udaipur:Bagore Ki Haveli"),
            name="Bagore Ki Haveli",
            category="heritage",
            latitude=24.5794,
            longitude=73.6811,
            importance_score=0.88,
            is_heritage=True,
            is_popular=True,
            is_gold_major_poi=True,
            tags={"historic": "haveli", "museum": "yes"},
        ),
        CandidatePOI(
            id=_deterministic_uuid("udaipur:Saheliyon-ki-Bari"),
            name="Saheliyon-ki-Bari",
            category="tourism",
            latitude=24.6008,
            longitude=73.6872,
            importance_score=0.86,
            is_heritage=True,
            is_popular=True,
            is_gold_major_poi=True,
            tags={"leisure": "garden", "tourism": "attraction"},
        ),
        CandidatePOI(
            id=_deterministic_uuid("udaipur:Jagdish Temple"),
            name="Jagdish Temple",
            category="heritage",
            latitude=24.5798,
            longitude=73.6839,
            importance_score=0.85,
            is_heritage=True,
            is_popular=True,
            is_gold_major_poi=True,
            tags={"amenity": "place_of_worship", "historic": "temple"},
        ),
    ]
    for ud in udaipur_defaults:
        if not any(ud.name.casefold() in c.name.casefold() for c in udaipur_candidates):
            udaipur_candidates.append(ud)

    scenarios.append(
        BenchmarkScenario(
            city_key="udaipur",
            city_name="Udaipur",
            latitude=24.5854,
            longitude=73.7125,
            purposes=["sightseeing"],
            interests=["heritage"],
            categories=["tourism", "heritage"],
            gold_major_pois=udaipur_gold,
            candidates=udaipur_candidates,
            expected_characteristics="Major palaces, lakes, and heritage rank high; generic amenities do not displace destination attractions.",
        )
    )

    # -------------------------------------------------------------------------
    # 6. MUMBAI (Mixed: Sightseeing + Food + Cafes)
    # -------------------------------------------------------------------------
    mumbai_gold = [
        "Gateway of India",
        "Marine Drive",
        "Chhatrapati Shivaji Maharaj Terminus",
        "Elephanta Caves",
        "Siddhivinayak Temple",
        "Leopold Cafe",
        "Britannia & Co. Restaurant",
    ]
    mumbai_aud = [a for a in audiala_items if a.get("city_en") == "Mumbai"]
    mumbai_candidates: list[CandidatePOI] = []
    
    for a in mumbai_aud:
        aname = a.get("name_en", "").strip()
        if not aname:
            continue
        pr = a.get("wikidata_pagerank") or 6.0
        imp = round(min(1.0, pr / 10.0), 3)
        cat = "heritage" if any(w in aname.lower() for w in ["terminus", "fort", "caves", "monument", "gateway"]) else "tourism"
        is_gold = any(g.casefold() in aname.casefold() for g in mumbai_gold)
        is_restricted = any(w in aname.lower() for w in ["bank", "atm", "branch office"])
        mumbai_candidates.append(
            CandidatePOI(
                id=_deterministic_uuid(f"mumbai:{aname}"),
                name=aname,
                category=cat,
                latitude=float(a.get("latitude", 18.9220)),
                longitude=float(a.get("longitude", 72.8347)),
                importance_score=imp,
                wikidata_id=a.get("wikidata_id"),
                is_gold_major_poi=is_gold,
                is_institution_or_restricted=is_restricted,
                is_heritage=(cat == "heritage"),
                tags={"historic": "yes"} if cat == "heritage" else {"tourism": "attraction"},
            )
        )

    # Add food and cafe candidates for Mumbai
    mumbai_food_and_cafes = [
        CandidatePOI(
            id=_deterministic_uuid("mumbai:Gateway of India"),
            name="Gateway of India",
            category="tourism",
            latitude=18.9220,
            longitude=72.8347,
            importance_score=0.98,
            is_popular=True,
            is_gold_major_poi=True,
            tags={"tourism": "attraction", "historic": "monument"},
        ),
        CandidatePOI(
            id=_deterministic_uuid("mumbai:Marine Drive"),
            name="Marine Drive",
            category="tourism",
            latitude=18.9432,
            longitude=72.8230,
            importance_score=0.95,
            is_popular=True,
            is_gold_major_poi=True,
            tags={"tourism": "attraction", "promenade": "yes"},
        ),
        CandidatePOI(
            id=_deterministic_uuid("mumbai:CSMT"),
            name="Chhatrapati Shivaji Maharaj Terminus",
            category="tourism",
            latitude=18.9400,
            longitude=72.8353,
            importance_score=0.97,
            is_heritage=True,
            is_popular=True,
            is_gold_major_poi=True,
            tags={"historic": "station", "heritage": "yes"},
        ),
        CandidatePOI(
            id=_deterministic_uuid("mumbai:Leopold Cafe"),
            name="Leopold Cafe",
            category="cafes",
            latitude=18.9230,
            longitude=72.8320,
            rating=4.4,
            review_count=4500,
            is_popular=True,
            is_local_speciality=True,
            is_gold_major_poi=True,
            tags={"amenity": "cafe", "cuisine": "parsi_continental"},
        ),
        CandidatePOI(
            id=_deterministic_uuid("mumbai:Britannia & Co."),
            name="Britannia & Co. Restaurant",
            category="food",
            latitude=18.9370,
            longitude=72.8380,
            rating=4.5,
            review_count=3200,
            is_popular=True,
            is_local_speciality=True,
            is_gold_major_poi=True,
            tags={"amenity": "restaurant", "cuisine": "parsi"},
        ),
        CandidatePOI(
            id=_deterministic_uuid("mumbai:Cafe Mondegar"),
            name="Cafe Mondegar",
            category="cafes",
            latitude=18.9245,
            longitude=72.8325,
            rating=4.3,
            review_count=3800,
            is_popular=True,
            tags={"amenity": "cafe"},
        ),
        CandidatePOI(
            id=_deterministic_uuid("mumbai:Bademiya"),
            name="Bademiya",
            category="food",
            latitude=18.9225,
            longitude=72.8335,
            rating=4.2,
            review_count=5200,
            is_local_speciality=True,
            tags={"amenity": "restaurant", "cuisine": "kebabs"},
        ),
        CandidatePOI(
            id=_deterministic_uuid("mumbai:Mahesh Lunch Home"),
            name="Mahesh Lunch Home",
            category="food",
            latitude=18.9320,
            longitude=72.8340,
            rating=4.4,
            review_count=2900,
            is_local_speciality=True,
            tags={"amenity": "restaurant", "cuisine": "seafood"},
        ),
        # Institutional dining regression candidate: IIT Bombay mess & campus food court
        CandidatePOI(
            id=_deterministic_uuid("mumbai:IITB Student Mess"),
            name="IIT Bombay Hostel 12 Mess",
            category="food",
            latitude=19.1334,
            longitude=72.9133,
            tags={"amenity": "canteen", "operator": "IIT Bombay", "building": "dormitory", "access": "students"},
            is_institution_or_restricted=True,
        ),
        CandidatePOI(
            id=_deterministic_uuid("mumbai:IITB Food Court"),
            name="IIT Bombay Campus Food Court",
            category="food",
            latitude=19.1340,
            longitude=72.9140,
            rating=4.1,
            review_count=120,
            tags={"amenity": "food_court", "operator": "IIT Bombay", "building": "university"},
            is_institution_or_restricted=True,
        ),
    ]
    for mfc in mumbai_food_and_cafes:
        if not any(mfc.name.casefold() in c.name.casefold() for c in mumbai_candidates):
            mumbai_candidates.append(mfc)

    scenarios.append(
        BenchmarkScenario(
            city_key="mumbai_mixed",
            city_name="Mumbai",
            latitude=18.9220,
            longitude=72.8347,
            purposes=["sightseeing"],
            interests=["food", "cafes"],
            categories=["tourism", "food", "cafes"],
            gold_major_pois=mumbai_gold,
            candidates=mumbai_candidates,
            expected_characteristics="Balanced mix of sightseeing landmarks, cafes, and food without category monopoly.",
        )
    )

    # -------------------------------------------------------------------------
    # 7. DELHI (Mixed: Heritage + Food + Sightseeing)
    # -------------------------------------------------------------------------
    delhi_gold = [
        "India Gate",
        "Red Fort",
        "Qutub Minar",
        "Humayun's Tomb",
        "Lotus Temple",
        "Jama Masjid",
        "Chandni Chowk",
        "Karim's",
    ]
    delhi_raw = load_poi_importance_results("delhi")
    delhi_candidates = _create_candidates_from_poi_data("delhi", delhi_raw, set(delhi_gold))

    delhi_key_places = [
        CandidatePOI(
            id=_deterministic_uuid("delhi:India Gate"),
            name="India Gate",
            category="heritage",
            latitude=28.6129,
            longitude=77.2295,
            importance_score=0.99,
            is_heritage=True,
            is_popular=True,
            is_gold_major_poi=True,
            tags={"historic": "monument", "tourism": "attraction"},
        ),
        CandidatePOI(
            id=_deterministic_uuid("delhi:Red Fort"),
            name="Red Fort",
            category="heritage",
            latitude=28.6562,
            longitude=77.2410,
            importance_score=0.98,
            is_heritage=True,
            is_popular=True,
            is_gold_major_poi=True,
            tags={"historic": "fort", "heritage": "unesco"},
        ),
        CandidatePOI(
            id=_deterministic_uuid("delhi:Qutub Minar"),
            name="Qutub Minar",
            category="heritage",
            latitude=28.5245,
            longitude=77.1855,
            importance_score=0.97,
            is_heritage=True,
            is_popular=True,
            is_gold_major_poi=True,
            tags={"historic": "minaret", "heritage": "unesco"},
        ),
        CandidatePOI(
            id=_deterministic_uuid("delhi:Humayuns Tomb"),
            name="Humayun's Tomb",
            category="heritage",
            latitude=28.5933,
            longitude=77.2507,
            importance_score=0.95,
            is_heritage=True,
            is_popular=True,
            is_gold_major_poi=True,
            tags={"historic": "tomb", "heritage": "unesco"},
        ),
        CandidatePOI(
            id=_deterministic_uuid("delhi:Karims"),
            name="Karim's Original Old Delhi",
            category="food",
            latitude=28.6508,
            longitude=77.2335,
            rating=4.5,
            review_count=6500,
            is_popular=True,
            is_local_speciality=True,
            is_gold_major_poi=True,
            tags={"amenity": "restaurant", "cuisine": "mughlai"},
        ),
        CandidatePOI(
            id=_deterministic_uuid("delhi:Chandni Chowk"),
            name="Chandni Chowk Food Street",
            category="food",
            latitude=28.6506,
            longitude=77.2303,
            rating=4.6,
            review_count=8900,
            is_popular=True,
            is_local_speciality=True,
            is_gold_major_poi=True,
            tags={"amenity": "food_court", "cuisine": "street_food"},
        ),
        # Institutional dining regression candidate: Delhi University / AIIMS
        CandidatePOI(
            id=_deterministic_uuid("delhi:AIIMS Doctor Mess"),
            name="AIIMS Doctors Dining Room",
            category="food",
            latitude=28.5672,
            longitude=77.2100,
            tags={"amenity": "canteen", "operator": "All India Institute of Medical Sciences", "building": "hospital"},
            is_institution_or_restricted=True,
        ),
        CandidatePOI(
            id=_deterministic_uuid("delhi:DU Student Mess"),
            name="Delhi University Staff Club Canteen",
            category="food",
            latitude=28.6890,
            longitude=77.2120,
            tags={"amenity": "canteen", "operator": "University of Delhi", "access": "members"},
            is_institution_or_restricted=True,
        ),
        CandidatePOI(
            id=_deterministic_uuid("delhi:AIIMS Campus Food Point"),
            name="AIIMS Campus Food Point",
            category="food",
            latitude=28.5675,
            longitude=77.2105,
            rating=4.0,
            review_count=180,
            tags={"amenity": "fast_food", "operator": "All India Institute of Medical Sciences", "building": "hospital"},
            is_institution_or_restricted=True,
        ),
    ]
    for dkp in delhi_key_places:
        if not any(dkp.name.casefold() in c.name.casefold() for c in delhi_candidates):
            delhi_candidates.append(dkp)

    scenarios.append(
        BenchmarkScenario(
            city_key="delhi_mixed",
            city_name="Delhi",
            latitude=28.6139,
            longitude=77.2090,
            purposes=["heritage"],
            interests=["food", "sightseeing"],
            categories=["heritage", "food", "tourism"],
            gold_major_pois=delhi_gold,
            candidates=delhi_candidates,
            expected_characteristics="Strong landmarks; authentic food venues; zero institutional dining; no single-category monopoly.",
        )
    )

    return scenarios
