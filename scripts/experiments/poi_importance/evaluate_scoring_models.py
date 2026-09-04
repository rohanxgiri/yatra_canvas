"""Evaluation of candidate importance scoring models against real-world test cases.

Compares:
- Baseline (no importance; current YatraCanvas)
- Model 1 (Naive linear PageRank: pr * 2.5) -> expected to fail / blow up
- Model 2 (Sitelinks only, log-scaled)
- Model 3 (PageRank only, log-scaled)
- Model 4 (Balanced Composite: 60% log-sitelinks + 40% log-pagerank, clamped [0, 1])

Tests Scenarios A, B, C, D, E and runs across real Jaipur, Ahmedabad, Surat, Delhi, Varanasi candidates.
"""

from __future__ import annotations

import json
import math
import os
import sys
from dataclasses import dataclass
from typing import Any

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
BACKEND_DIR = os.path.join(PROJECT_ROOT, "backend")
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

from app.models.entities import Place
from app.schemas.recommendation import DiscoveryCategory
from app.services.place_suitability_service import AccessConfidence
from app.services.preference_model import (
    DEFAULT_PREFERENCE_CONFIG,
    PreferenceWeightingConfig,
    evaluate_preference_fit,
)
from app.services.recommendation_service import (
    DEFAULT_RECOMMENDATION_WEIGHTS,
    RecommendationWeights,
    calculate_recommendation_score,
)

RESULTS_DIR = os.path.join(os.path.dirname(__file__), "results")


def normalize_sitelinks(sitelinks: int | None) -> float:
    """Bounded log10 normalization for sitelinks [0.0, 1.0]."""
    if sitelinks is None or sitelinks <= 0:
        return 0.0
    # 100 sitelinks represents world-class icon (Taj Mahal ~180, Hawa Mahal ~59)
    return min(1.0, math.log10(sitelinks + 1) / math.log10(101))


def normalize_pagerank(pagerank: float | None) -> float:
    """Bounded log10 normalization for Wikidata PageRank [0.0, 1.0]."""
    if pagerank is None or pagerank <= 0.0:
        return 0.0
    # PageRank 25 represents the 99th percentile of Indian heritage entities
    return min(1.0, math.log10(pagerank + 1) / math.log10(26))


def calculate_composite_prominence(
    sitelinks: int | None,
    pagerank: float | None,
) -> float:
    """Calculate composite prominence score in [0.0, 1.0]."""
    sl_norm = normalize_sitelinks(sitelinks)
    pr_norm = normalize_pagerank(pagerank)

    if sitelinks is not None and pagerank is not None:
        # Sitelinks is primary (60%), PageRank is supporting (40%)
        return round(0.60 * sl_norm + 0.40 * pr_norm, 4)
    elif sitelinks is not None:
        return round(sl_norm, 4)
    elif pagerank is not None:
        return round(pr_norm, 4)
    return 0.0


def score_candidate(
    place: Place,
    place_tags: set[str],
    *,
    purposes: list[str] | None = None,
    interests: list[str] | None = None,
    sitelinks: int | None = None,
    pagerank: float | None = None,
    model_name: str = "baseline",
    importance_weight: float = 15.0,
    config: PreferenceWeightingConfig = DEFAULT_PREFERENCE_CONFIG,
    weights: RecommendationWeights = DEFAULT_RECOMMENDATION_WEIGHTS,
) -> tuple[float, dict[str, float]]:
    """Score place under specified model."""
    has_prefs = bool(purposes or interests)
    relevance_score = None
    if has_prefs:
        rel, _, _ = evaluate_preference_fit(
            place, place_tags, purposes=purposes, interests=interests, config=config
        )
        if rel < config.min_relevance_score:
            return 0.0, {"relevance": 0.0, "base": 0.0, "importance": 0.0, "total": 0.0}
        relevance_score = rel

    base_score = calculate_recommendation_score(
        place,
        access_confidence=AccessConfidence.PUBLIC_LIKELY,
        weights=weights,
        relevance_score=relevance_score,
    )

    importance_boost = 0.0

    if model_name == "baseline":
        importance_boost = 0.0
    elif model_name == "naive_linear_pr":
        # Unbounded linear PageRank
        importance_boost = (pagerank or 0.0) * 2.5
    elif model_name == "sitelinks_only":
        sl_score = normalize_sitelinks(sitelinks)
        importance_boost = sl_score * importance_weight
    elif model_name == "pagerank_only":
        pr_score = normalize_pagerank(pagerank)
        importance_boost = pr_score * importance_weight
    elif model_name == "composite":
        prominence = calculate_composite_prominence(sitelinks, pagerank)
        importance_boost = prominence * importance_weight

    final_score = round(min(max(base_score + importance_boost, 0.0), 100.0), 1)

    breakdown = {
        "relevance": round(relevance_score or 0.0, 1),
        "base": base_score,
        "importance": round(importance_boost, 1),
        "total": final_score,
    }
    return final_score, breakdown


def run_synthetic_scenarios():
    print("===================================================================")
    print("PHASE 8: SYNTHETIC SCENARIO COMPARISONS (A, B, C, D, E)")
    print("===================================================================")

    # Scenario A: Famous Sightseeing Destination
    # User: purpose = sightseeing (heritage), interest = heritage
    print("\n--- SCENARIO A: Famous Sightseeing Destination (Purpose: heritage, Interest: heritage) ---")
    hawa_mahal = Place(
        name="Hawa Mahal",
        category="tourism",
        latitude=26.9239,
        longitude=75.8267,
        is_heritage=True,
    )
    hawa_tags = {"tourism", "heritage", "attraction", "historic"}

    roundabout = Place(
        name="Vichar Kranti Circle",
        category="heritage",
        latitude=26.9240,
        longitude=75.8268,
        is_heritage=True,
    )
    roundabout_tags = {"heritage", "historic"}

    local_hotel = Place(
        name="Hotel Raj Palace",
        category="tourism",
        latitude=26.9241,
        longitude=75.8269,
        is_heritage=False,
    )
    hotel_tags = {"tourism", "hotel"}

    candidates_a = [
        ("Hawa Mahal (Major Landmark, 59 sl, PR 4.32)", hawa_mahal, hawa_tags, 59, 4.32),
        ("Vichar Kranti Circle (Roundabout tagged historic, 0 sl, 0 PR)", roundabout, roundabout_tags, 0, 0.0),
        ("Hotel Raj Palace (Generic tourist POI, 0 sl, 0 PR)", local_hotel, hotel_tags, 0, 0.0),
    ]

    for model in ["baseline", "naive_linear_pr", "composite"]:
        print(f"\nModel: {model}")
        scores = []
        for label, pl, tags, sl, pr in candidates_a:
            sc, bd = score_candidate(
                pl, tags, purposes=["heritage"], interests=["heritage"], sitelinks=sl, pagerank=pr, model_name=model
            )
            scores.append((sc, label, bd))
        scores.sort(reverse=True)
        for rank, (sc, label, bd) in enumerate(scores, 1):
            print(f"  Rank {rank}: {label} -> Total: {sc} (Base: {bd['base']}, Imp: {bd['importance']})")

    # Scenario B: Food-Focused Traveler
    # User: purpose = food, interest = cafes
    print("\n--- SCENARIO B: Food-Focused Traveler (Purpose: food, Interest: cafes) ---")
    local_dhaba = Place(
        name="Laxmi Mishthan Bhandar (LMB)",
        category="food",
        latitude=26.9200,
        longitude=75.8200,
        is_local_speciality=True,
    )
    dhaba_tags = {"food", "restaurant", "local_speciality", "street_food"}

    famous_monument = Place(
        name="Hawa Mahal",
        category="tourism",
        latitude=26.9239,
        longitude=75.8267,
        is_heritage=True,
    )
    monument_tags = {"tourism", "heritage", "attraction"}

    popular_cafe = Place(
        name="Anokhi Cafe",
        category="cafes",
        latitude=26.9100,
        longitude=75.8000,
        is_popular=True,
    )
    cafe_tags = {"cafes", "cafe", "organic", "coffee"}

    candidates_b = [
        ("LMB Traditional Sweetshop (Food, no Wikidata)", local_dhaba, dhaba_tags, 0, 0.0),
        ("Anokhi Cafe (Popular cafe, 0 sl, 0 PR)", popular_cafe, cafe_tags, 0, 0.0),
        ("Hawa Mahal (Monument with 59 sitelinks, PR 4.32)", famous_monument, monument_tags, 59, 4.32),
    ]

    for model in ["baseline", "naive_linear_pr", "composite"]:
        print(f"\nModel: {model}")
        scores = []
        for label, pl, tags, sl, pr in candidates_b:
            sc, bd = score_candidate(
                pl, tags, purposes=["food"], interests=["cafes"], sitelinks=sl, pagerank=pr, model_name=model
            )
            scores.append((sc, label, bd))
        scores.sort(reverse=True)
        for rank, (sc, label, bd) in enumerate(scores, 1):
            print(f"  Rank {rank}: {label} -> Total: {sc} (Relevance: {bd['relevance']}, Base: {bd['base']}, Imp: {bd['importance']})")

    # Scenario C: Religious Trip
    # User: purpose = religious, interest = temples
    print("\n--- SCENARIO C: Religious Trip (Purpose: religious, Interest: religious) ---")
    kashi_vishwanath = Place(
        name="Kashi Vishwanath Temple",
        category="religious",
        latitude=25.3108,
        longitude=83.0107,
        is_heritage=True,
    )
    kv_tags = {"religious", "place_of_worship", "temple", "hindu", "historic"}

    small_shrine = Place(
        name="Local Street Shrine",
        category="religious",
        latitude=25.3110,
        longitude=83.0110,
        is_heritage=False,
    )
    shrine_tags = {"religious", "place_of_worship", "temple"}

    candidates_c = [
        ("Kashi Vishwanath (Major Temple, 41 sl, PR 6.12)", kashi_vishwanath, kv_tags, 41, 6.12),
        ("Local Street Shrine (Small shrine, 0 sl, 0 PR)", small_shrine, shrine_tags, 0, 0.0),
    ]

    for model in ["baseline", "composite"]:
        print(f"\nModel: {model}")
        scores = []
        for label, pl, tags, sl, pr in candidates_c:
            sc, bd = score_candidate(
                pl, tags, purposes=["religious"], interests=["religious"], sitelinks=sl, pagerank=pr, model_name=model
            )
            scores.append((sc, label, bd))
        scores.sort(reverse=True)
        for rank, (sc, label, bd) in enumerate(scores, 1):
            print(f"  Rank {rank}: {label} -> Total: {sc} (Base: {bd['base']}, Imp: {bd['importance']})")

    # Scenario D: Local-speciality Place with No Wikidata Signal
    print("\n--- SCENARIO D: Local-Speciality Place with No Wikidata Signal ---")
    local_eatery = Place(
        name="Old Famous Jalebi Wala",
        category="food",
        latitude=28.6500,
        longitude=77.2300,
        is_local_speciality=True,
    )
    eatery_tags = {"food", "restaurant", "local_speciality"}

    generic_fast_food = Place(
        name="Generic Burger Joint",
        category="food",
        latitude=28.6510,
        longitude=77.2310,
        is_local_speciality=False,
    )
    fast_food_tags = {"food", "restaurant"}

    candidates_d = [
        ("Old Famous Jalebi Wala (Local Speciality, 0 sl)", local_eatery, eatery_tags, 0, 0.0),
        ("Generic Burger Joint (Generic food, 0 sl)", generic_fast_food, fast_food_tags, 0, 0.0),
    ]

    for model in ["baseline", "composite"]:
        print(f"\nModel: {model}")
        scores = []
        for label, pl, tags, sl, pr in candidates_d:
            sc, bd = score_candidate(
                pl, tags, purposes=["food"], interests=["food"], sitelinks=sl, pagerank=pr, model_name=model
            )
            scores.append((sc, label, bd))
        scores.sort(reverse=True)
        for rank, (sc, label, bd) in enumerate(scores, 1):
            print(f"  Rank {rank}: {label} -> Total: {sc} (Base: {bd['base']}, Imp: {bd['importance']})")

    # Scenario E: Two Equally Relevant Attractions (Tie-breaker)
    print("\n--- SCENARIO E: Two Equally Relevant Attractions (Tie-breaker) ---")
    jantar_mantar = Place(
        name="Jantar Mantar",
        category="tourism",
        latitude=26.9247,
        longitude=75.8245,
        is_heritage=True,
    )
    jm_tags = {"tourism", "heritage", "historic", "attraction"}

    minor_monument = Place(
        name="Paanch Batti Gateway",
        category="tourism",
        latitude=26.9200,
        longitude=75.8200,
        is_heritage=True,
    )
    pb_tags = {"tourism", "heritage", "historic", "attraction"}

    candidates_e = [
        ("Jantar Mantar (UNESCO Observatory, 47 sl, PR 18.56)", jantar_mantar, jm_tags, 47, 18.56),
        ("Paanch Batti Gateway (Minor arch, 0 sl, 0 PR)", minor_monument, pb_tags, 0, 0.0),
    ]

    for model in ["baseline", "composite"]:
        print(f"\nModel: {model}")
        scores = []
        for label, pl, tags, sl, pr in candidates_e:
            sc, bd = score_candidate(
                pl, tags, purposes=["sightseeing"], interests=["heritage"], sitelinks=sl, pagerank=pr, model_name=model
            )
            scores.append((sc, label, bd))
        scores.sort(reverse=True)
        for rank, (sc, label, bd) in enumerate(scores, 1):
            print(f"  Rank {rank}: {label} -> Total: {sc} (Base: {bd['base']}, Imp: {bd['importance']})")


def run_city_candidate_evaluation():
    print("\n===================================================================")
    print("PHASE 8: REAL CANDIDATE EVALUATIONS (JAIPUR & VARANASI)")
    print("===================================================================")

    output_data: dict[str, Any] = {}

    for city_key in ["jaipur", "varanasi"]:
        path = os.path.join(RESULTS_DIR, f"{city_key}.json")
        if not os.path.exists(path):
            continue
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)

        candidates = data.get("all_candidates_scored", [])
        if not candidates:
            continue

        print(f"\n--- CITY: {city_key.upper()} (Total Candidates: {len(candidates)}) ---")

        # Evaluate Top 10 under Baseline vs Composite
        scored_baseline = []
        scored_composite = []

        for c in candidates:
            name = c["name"]
            cat = c["category"]
            sl = c.get("sitelinks")
            pr = c.get("audiala_pagerank")

            pl = Place(
                name=name,
                category=cat,
                latitude=c["latitude"],
                longitude=c["longitude"],
                is_heritage="heritage" in c.get("matched_categories", []),
            )
            tags = set(c.get("matched_categories", []))

            # Score for Sightseeing purpose
            sc_base, _ = score_candidate(
                pl, tags, purposes=["sightseeing"], interests=["heritage"], sitelinks=sl, pagerank=pr, model_name="baseline"
            )
            sc_comp, bd = score_candidate(
                pl, tags, purposes=["sightseeing"], interests=["heritage"], sitelinks=sl, pagerank=pr, model_name="composite", importance_weight=15.0
            )

            scored_baseline.append((sc_base, name, cat, sl, pr))
            scored_composite.append((sc_comp, name, cat, sl, pr, bd["importance"]))

        scored_baseline.sort(key=lambda x: (-x[0], x[1].casefold()))
        scored_composite.sort(key=lambda x: (-x[0], x[1].casefold()))

        print("\nTOP 8 - BASELINE (WITHOUT IMPORTANCE):")
        for i, (sc, name, cat, sl, pr) in enumerate(scored_baseline[:8], 1):
            print(f"  {i:2d}. {name:<35} | {cat:<10} | Score: {sc:4.1f} | Sitelinks: {sl or 0:2d} | PR: {pr or 0.0:.2f}")

        print("\nTOP 8 - COMPOSITE IMPORTANCE (WEIGHT = 15.0):")
        for i, (sc, name, cat, sl, pr, imp) in enumerate(scored_composite[:8], 1):
            print(f"  {i:2d}. {name:<35} | {cat:<10} | Score: {sc:4.1f} (+{imp:4.1f}) | Sitelinks: {sl or 0:2d} | PR: {pr or 0.0:.2f}")

        output_data[city_key] = {
            "top_baseline": [
                {"name": name, "category": cat, "score": sc, "sitelinks": sl, "pagerank": pr}
                for sc, name, cat, sl, pr in scored_baseline[:15]
            ],
            "top_composite": [
                {"name": name, "category": cat, "score": sc, "importance_boost": imp, "sitelinks": sl, "pagerank": pr}
                for sc, name, cat, sl, pr, imp in scored_composite[:15]
            ],
        }

    out_file = os.path.join(RESULTS_DIR, "importance_scoring_evaluation_results.json")
    os.makedirs(RESULTS_DIR, exist_ok=True)
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(output_data, f, indent=2)
    print(f"\nSaved evaluation results to {out_file}")


if __name__ == "__main__":
    run_synthetic_scenarios()
    run_city_candidate_evaluation()
