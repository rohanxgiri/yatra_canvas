"""Evaluation metrics for multi-city recommendation quality benchmark.

Metrics implemented:
1. Intent Precision@K (P@5, P@10, P@15, P@20)
2. Restricted / unsuitable POI rate (Target: 0)
3. Duplicate rate (canonical & near-duplicate)
4. Major POI coverage (recall against curated gold sets)
5. Category diversity (entropy & category distribution across requested intents)
6. Recommendation stability (determinism check)
7. Candidate utilization funnel
8. Large-request robustness (count parity, runtime, errors)
"""

from __future__ import annotations

import math
import os
import sys
from dataclasses import dataclass, field
from typing import Any
from uuid import UUID

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
BACKEND_DIR = os.path.join(PROJECT_ROOT, "backend")
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

from app.services.place_deduplication_service import (
    are_names_similar,
    haversine_distance_meters,
)


@dataclass
class ScenarioEvaluationResult:
    scenario_key: str
    city_name: str
    k: int
    requested_k: int
    returned_k: int
    intent_precision: float
    restricted_count: int
    restricted_rate: float
    canonical_duplicate_count: int
    near_duplicate_count: int
    duplicate_rate: float
    gold_major_poi_recall: float
    gold_pois_found: list[str]
    category_distribution: dict[str, int]
    category_diversity_entropy: float
    is_deterministic: bool
    pipeline_funnel: dict[str, int]
    runtime_ms: float
    top_recommendations: list[dict[str, Any]] = field(default_factory=list)
    restricted_leakages: list[str] = field(default_factory=list)


def evaluate_intent_precision(
    recommendations: list[dict[str, Any]],
    requested_categories: set[str],
    requested_purposes: set[str],
    requested_interests: set[str],
) -> float:
    """Calculate Intent Precision@K: relevant places / K."""
    if not recommendations:
        return 0.0
    relevant_count = 0
    valid_intents = {c.casefold() for c in requested_categories} | {
        p.casefold() for p in requested_purposes
    } | {i.casefold() for i in requested_interests}

    # Map semantic categories
    intent_synonyms = {
        "sightseeing": {"tourism", "heritage", "nature"},
        "temples": {"religious"},
        "ghats": {"heritage", "religious", "tourism"},
        "heritage": {"heritage", "tourism"},
        "food": {"food", "cafes"},
        "cafes": {"cafes", "food"},
        "religious": {"religious"},
    }

    expanded_intents = set(valid_intents)
    for intent in valid_intents:
        if intent in intent_synonyms:
            expanded_intents.update(intent_synonyms[intent])

    for rec in recommendations:
        rec_cat = rec.get("category", "").casefold()
        matched_cats = [c.casefold() for c in rec.get("matched_categories", [])]
        tags = [t.casefold() for t in rec.get("tags", [])]
        all_signals = {rec_cat} | set(matched_cats) | set(tags)
        
        if bool(all_signals & expanded_intents):
            relevant_count += 1

    return round(relevant_count / len(recommendations), 4)


def evaluate_restricted_pois(
    recommendations: list[dict[str, Any]],
    known_restricted_ids: set[UUID],
) -> tuple[int, float, list[str]]:
    """Measure restricted / unsuitable POIs in top K."""
    if not recommendations:
        return 0, 0.0, []
    str_restricted = {str(x) for x in known_restricted_ids}
    leaked: list[str] = []
    for rec in recommendations:
        rid = str(rec.get("id"))
        if rid in str_restricted or rec.get("is_institution_or_restricted", False):
            leaked.append(rec.get("name", rid))
    count = len(leaked)
    rate = round(count / len(recommendations), 4)
    return count, rate, leaked


def evaluate_duplicates(
    recommendations: list[dict[str, Any]],
) -> tuple[int, int, float]:
    """Calculate canonical duplicates and near-duplicate representations in top K."""
    if not recommendations:
        return 0, 0, 0.0
    k = len(recommendations)
    seen_ids: set[Any] = set()
    canonical_dupes = 0
    for rec in recommendations:
        rid = rec.get("id")
        if rid in seen_ids:
            canonical_dupes += 1
        seen_ids.add(rid)

    near_dupes = 0
    for i in range(k):
        p1 = recommendations[i]
        for j in range(i + 1, k):
            p2 = recommendations[j]
            dist_m = haversine_distance_meters(
                p1["latitude"], p1["longitude"], p2["latitude"], p2["longitude"]
            )
            if dist_m <= 75.0 and are_names_similar(p1["name"], p2["name"]):
                near_dupes += 1

    total_dupes = canonical_dupes + near_dupes
    return canonical_dupes, near_dupes, round(total_dupes / k, 4)


def evaluate_major_poi_coverage(
    recommendations: list[dict[str, Any]],
    gold_major_pois: list[str],
) -> tuple[float, list[str]]:
    """Measure recall of curated gold attractions in top K."""
    if not gold_major_pois or not recommendations:
        return 0.0, []
    rec_names = [r.get("name", "").casefold() for r in recommendations]
    found: list[str] = []
    for gold in gold_major_pois:
        gold_cf = gold.casefold()
        if any(gold_cf in rn or rn in gold_cf for rn in rec_names):
            found.append(gold)
    
    recall = round(len(found) / min(len(gold_major_pois), len(recommendations)), 4)
    return recall, found


def evaluate_category_diversity(
    recommendations: list[dict[str, Any]],
) -> tuple[dict[str, int], float]:
    """Measure category distribution and Shannon entropy across recommendations."""
    if not recommendations:
        return {}, 0.0
    dist: dict[str, int] = {}
    for rec in recommendations:
        cat = rec.get("category", "unknown")
        dist[cat] = dist.get(cat, 0) + 1

    total = len(recommendations)
    entropy = 0.0
    for count in dist.values():
        p = count / total
        if p > 0:
            entropy -= p * math.log2(p)

    return dist, round(entropy, 3)
