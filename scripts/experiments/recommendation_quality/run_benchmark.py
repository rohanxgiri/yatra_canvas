"""Executable benchmark runner for multi-city recommendation quality.

Runs all 7 benchmark scenarios across K in [5, 10, 15, 20]:
- Jaipur (Heritage, Sightseeing)
- Varanasi (Religious, Temples, Sightseeing, Ghats)
- Surat (Food - with institutional SVNIT regression fixtures)
- Ahmedabad (Food + Heritage mixed, and Heritage only)
- Udaipur (Sightseeing, Heritage)
- Mumbai (Sightseeing + Food + Cafes)
- Delhi (Heritage + Food + Sightseeing)

Uses in-memory SQLite and production RecommendationService.
Completely offline, deterministic, and reproducible.
"""

from __future__ import annotations

import argparse
import asyncio
from datetime import datetime, timezone
import json
import os
import sys
import time
from typing import Any
from uuid import UUID, uuid4

# Add backend directory to sys.path
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
BACKEND_DIR = os.path.join(PROJECT_ROOT, "backend")
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.models.entities import City, Place, PlaceSource, PlaceTag
from app.schemas.recommendation import DiscoveryCategory, RecommendationRequest
from app.services.recommendation_service import RecommendationService

from benchmark_fixtures import BenchmarkScenario, CandidatePOI, get_all_benchmark_scenarios
from metrics import (
    ScenarioEvaluationResult,
    evaluate_category_diversity,
    evaluate_duplicates,
    evaluate_intent_precision,
    evaluate_major_poi_coverage,
    evaluate_restricted_pois,
)

RESULTS_DIR = os.path.join(os.path.dirname(__file__), "results")
os.makedirs(RESULTS_DIR, exist_ok=True)


class BenchmarkMockDiscovery:
    """Mock discovery that returns existing stored places by category."""

    def __init__(self, places_by_cat: dict[DiscoveryCategory, list[Place]]) -> None:
        self._places_by_cat = places_by_cat

    async def discover_many(
        self,
        *,
        session: Session,
        city: City,
        categories: list[DiscoveryCategory],
    ) -> dict[DiscoveryCategory, list[Place]]:
        return {cat: self._places_by_cat.get(cat, []) for cat in categories}


def create_in_memory_session():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)
    return Session(engine)


def populate_scenario_db(
    session: Session,
    scenario: BenchmarkScenario,
) -> tuple[City, dict[DiscoveryCategory, list[Place]], set[UUID]]:
    city = City(
        id=uuid4(),
        name=scenario.city_name,
        country="India",
        latitude=scenario.latitude,
        longitude=scenario.longitude,
    )
    session.add(city)

    places_by_cat: dict[DiscoveryCategory, list[Place]] = {}
    restricted_ids: set[UUID] = set()

    for cand in scenario.candidates:
        place = Place(
            id=cand.id,
            city_id=city.id,
            name=cand.name,
            category=cand.category,
            latitude=cand.latitude,
            longitude=cand.longitude,
            rating=cand.rating,
            review_count=cand.review_count,
            is_popular=cand.is_popular,
            is_local_speciality=cand.is_local_speciality,
            is_heritage=cand.is_heritage,
            importance_score=cand.importance_score,
            wikidata_id=cand.wikidata_id,
        )
        session.add(place)

        # Collect unique tags
        place_tag_set: set[str] = {cand.category}
        for tag_key, tag_val in cand.tags.items():
            if tag_val and tag_val != "no":
                place_tag_set.add(tag_key)
                place_tag_set.add(f"{tag_key}={tag_val}")

        for t in place_tag_set:
            session.add(PlaceTag(place_id=place.id, tag=t))

        # Add PlaceSource
        session.add(
            PlaceSource(
                place_id=place.id,
                source="benchmark_fixture",
                external_place_id=str(cand.id),
                wikidata_id=cand.wikidata_id,
                last_fetched_at=datetime.now(timezone.utc),
            )
        )

        try:
            d_cat = DiscoveryCategory(cand.category)
            places_by_cat.setdefault(d_cat, []).append(place)
        except ValueError:
            pass

        if cand.is_institution_or_restricted:
            restricted_ids.add(cand.id)

    session.commit()
    return city, places_by_cat, restricted_ids


async def run_scenario_evaluation(
    scenario: BenchmarkScenario,
    k_values: list[int] = [5, 10, 15, 20],
) -> list[ScenarioEvaluationResult]:
    results: list[ScenarioEvaluationResult] = []

    session = create_in_memory_session()
    city, places_by_cat, restricted_ids = populate_scenario_db(session, scenario)

    req_categories = [DiscoveryCategory(c) for c in scenario.categories if c in DiscoveryCategory._value2member_map_]
    discovery = BenchmarkMockDiscovery(places_by_cat)
    service = RecommendationService(discovery=discovery)

    for k in k_values:
        req = RecommendationRequest(
            limit=k,
            categories=req_categories,
            purposes=scenario.purposes,
            interests=scenario.interests,
        )

        t0 = time.perf_counter()
        recs1 = await service.recommend(session=session, city=city, request=req)
        runtime_ms = round((time.perf_counter() - t0) * 1000.0, 2)

        # Determinism check: rerun identical request
        recs2 = await service.recommend(session=session, city=city, request=req)
        is_deterministic = [r.id for r in recs1] == [r.id for r in recs2]

        rec_dicts = [
            {
                "id": str(r.id),
                "name": r.name,
                "category": r.category,
                "latitude": r.latitude,
                "longitude": r.longitude,
                "score": r.recommendation_score,
                "reason": r.recommendation_reason,
                "access_confidence": r.access_confidence,
                "matched_categories": [mc.value for mc in r.matched_categories],
            }
            for r in recs1
        ]

        # Calculate metrics
        precision = evaluate_intent_precision(
            rec_dicts,
            requested_categories=set(scenario.categories),
            requested_purposes=set(scenario.purposes),
            requested_interests=set(scenario.interests),
        )
        restr_count, restr_rate, leaked_restr = evaluate_restricted_pois(
            rec_dicts,
            restricted_ids,
        )
        canon_dupes, near_dupes, dupe_rate = evaluate_duplicates(rec_dicts)
        gold_recall, gold_found = evaluate_major_poi_coverage(
            rec_dicts,
            scenario.gold_major_pois,
        )
        cat_dist, entropy = evaluate_category_diversity(rec_dicts)

        funnel = {
            "raw_candidates": len(scenario.candidates),
            "returned_recommendations": len(rec_dicts),
        }

        eval_res = ScenarioEvaluationResult(
            scenario_key=scenario.city_key,
            city_name=scenario.city_name,
            k=k,
            requested_k=k,
            returned_k=len(rec_dicts),
            intent_precision=precision,
            restricted_count=restr_count,
            restricted_rate=restr_rate,
            canonical_duplicate_count=canon_dupes,
            near_duplicate_count=near_dupes,
            duplicate_rate=dupe_rate,
            gold_major_poi_recall=gold_recall,
            gold_pois_found=gold_found,
            category_distribution=cat_dist,
            category_diversity_entropy=entropy,
            is_deterministic=is_deterministic,
            pipeline_funnel=funnel,
            runtime_ms=runtime_ms,
            top_recommendations=rec_dicts,
            restricted_leakages=leaked_restr,
        )
        results.append(eval_res)

    return results


async def run_full_benchmark(output_filename: str = "benchmark_results.json") -> dict[str, Any]:
    scenarios = get_all_benchmark_scenarios()
    print(f"\n=========================================================================")
    print(f"RUNNING YATRACANVAS MULTI-CITY RECOMMENDATION QUALITY BENCHMARK")
    print(f"Total Scenarios: {len(scenarios)} | K sizes: [5, 10, 15, 20]")
    print(f"=========================================================================\n")

    all_scenario_results: list[ScenarioEvaluationResult] = []

    for sc in scenarios:
        print(f"Evaluating scenario: {sc.city_name.upper()} ({sc.city_key}) | Intent: {sc.purposes} + {sc.interests}...")
        sc_results = await run_scenario_evaluation(sc, k_values=[5, 10, 15, 20])
        all_scenario_results.extend(sc_results)

        for res in sc_results:
            status_restr = "PASSED" if res.restricted_count == 0 else f"FAILED ({res.restricted_count} leaked: {res.restricted_leakages})"
            print(
                f"  K={res.k:2d} -> Returned: {res.returned_k:2d} | "
                f"P@{res.k}: {res.intent_precision:.2f} | "
                f"Restricted: {status_restr} | "
                f"Dupes: {res.near_duplicate_count + res.canonical_duplicate_count} | "
                f"Gold Recall: {res.gold_major_poi_recall:.2f} ({len(res.gold_pois_found)}/{len(sc.gold_major_pois)}) | "
                f"Div Entropy: {res.category_diversity_entropy:.2f} | "
                f"Time: {res.runtime_ms:.1f}ms"
            )

    # Convert results to serializable dictionary
    serialized_results = {
        "timestamp": time.time(),
        "scenarios_count": len(scenarios),
        "total_evaluations": len(all_scenario_results),
        "results": [
            {
                "scenario_key": r.scenario_key,
                "city_name": r.city_name,
                "k": r.k,
                "requested_k": r.requested_k,
                "returned_k": r.returned_k,
                "intent_precision": r.intent_precision,
                "restricted_count": r.restricted_count,
                "restricted_rate": r.restricted_rate,
                "restricted_leakages": r.restricted_leakages,
                "canonical_duplicate_count": r.canonical_duplicate_count,
                "near_duplicate_count": r.near_duplicate_count,
                "duplicate_rate": r.duplicate_rate,
                "gold_major_poi_recall": r.gold_major_poi_recall,
                "gold_pois_found": r.gold_pois_found,
                "category_distribution": r.category_distribution,
                "category_diversity_entropy": r.category_diversity_entropy,
                "is_deterministic": r.is_deterministic,
                "pipeline_funnel": r.pipeline_funnel,
                "runtime_ms": r.runtime_ms,
                "top_recommendations": r.top_recommendations,
            }
            for r in all_scenario_results
        ],
    }

    if os.path.isabs(output_filename) or os.path.dirname(output_filename):
        output_path = output_filename
    else:
        output_path = os.path.join(RESULTS_DIR, output_filename)
    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(serialized_results, f, indent=2, ensure_ascii=False)

    print(f"\n=========================================================================")
    print(f"BENCHMARK COMPLETE. Results saved to: {output_path}")
    print(f"=========================================================================\n")
    return serialized_results


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="baseline.json", help="Output json filename in results/")
    args = parser.parse_args()
    asyncio.run(run_full_benchmark(args.output))
