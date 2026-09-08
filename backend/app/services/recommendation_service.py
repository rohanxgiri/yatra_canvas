"""Explainable ranking and multi-stage pipeline for place recommendations.

Implements:
1. Candidate Retrieval across requested categories
2. Identity & Spatial Deduplication
3. Traveller-Suitability & Access Confidence Filtering
4. Category Normalization & Category Filter Interaction
5. Purpose (2.5x) vs Interest (1.0x) Relevance Scoring
6. Low-relevance Filtering (no arbitrary filler dilution)
7. Diversity-aware Final Ranking (soft interleaving for mixed trips)
8. Truthful, preference-derived Explanation Generation
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from math import log10
from typing import Any, Protocol
from uuid import UUID

from sqlmodel import Session, select

logger = logging.getLogger(__name__)

from app.models.entities import (
    City,
    Place,
    PlaceSource,
    PlaceTag,
    Trip,
    TripPreference,
    UserSavedPlace,
)
from app.schemas.recommendation import (
    DiscoveryCategory,
    RecommendationRead,
    RecommendationRequest,
)
from app.services.place_deduplication_service import (
    are_names_similar,
    deduplicate_places,
    haversine_distance_meters,
)
from app.services.place_importance_scorer import PlaceImportanceScorer
from app.services.place_suitability_service import (
    AccessConfidence,
    is_traveller_suitable,
)
from app.services.preference_model import (
    DEFAULT_PREFERENCE_CONFIG,
    PreferenceWeightingConfig,
    evaluate_preference_fit,
    generate_preference_explanation,
    normalize_preference_key,
)


class RecommendationDiscovery(Protocol):
    async def discover(
        self,
        *,
        session: Session,
        city: City,
        category: DiscoveryCategory,
    ) -> list[Place]: ...


@dataclass(frozen=True, slots=True)
class RecommendationWeights:
    """Tunable score weights; normalized to 100 points."""

    category_match: float = 40.0
    rating_confidence: float = 35.0
    importance_weight: float = 15.0
    popular_bonus: float = 10.0
    heritage_bonus: float = 8.0
    local_speciality_bonus: float = 7.0
    unknown_access_penalty: float = 15.0
    review_reference_count: int = 20000
    review_confidence_floor: float = 0.35
    start_proximity_bonus: float = 8.0
    start_proximity_radius_km: float = 20.0


DEFAULT_RECOMMENDATION_WEIGHTS = RecommendationWeights()


def calculate_recommendation_score(
    place: Place,
    *,
    matched_category_count: int = 1,
    selected_category_count: int = 1,
    access_confidence: AccessConfidence = AccessConfidence.PUBLIC_LIKELY,
    distance_from_city_km: float | None = None,
    weights: RecommendationWeights = DEFAULT_RECOMMENDATION_WEIGHTS,
    relevance_score: float | None = None,
    prominence_score: float | None = None,
) -> float:
    """Return a 0-100 score combining preference fit, access confidence, verified quality, and prominence."""
    # 1. Category / Preference fit
    if relevance_score is not None:
        category_score = relevance_score
    else:
        category_ratio = (
            matched_category_count / selected_category_count
            if selected_category_count > 0
            else 0.0
        )
        category_score = weights.category_match * min(category_ratio, 1.0)

    # 2. Verified rating & review confidence (only if real data exists)
    rating_score = 0.0
    if place.rating is not None:
        review_confidence = min(
            log10(max(place.review_count, 0) + 1)
            / log10(weights.review_reference_count + 1),
            1.0,
        )
        confidence_multiplier = weights.review_confidence_floor + (
            (1.0 - weights.review_confidence_floor) * review_confidence
        )
        rating_score = (
            weights.rating_confidence * (place.rating / 5.0) * confidence_multiplier
        )

    # 3. Prominence / Importance scoring (Wikidata / Audiala signals)
    # Prominence operates within relevant candidates; if category_score == 0, it contributes 0.
    prominence_addition = 0.0
    if category_score > 0.0 and weights.importance_weight > 0.0:
        eff_prominence = prominence_score
        if eff_prominence is None:
            eff_prominence = getattr(place, "importance_score", None)
        if eff_prominence is None and getattr(place, "wikidata_id", None):
            eff_prominence = PlaceImportanceScorer.lookup_audiala_prominence(
                place.wikidata_id
            )

        if eff_prominence is not None and eff_prominence > 0.0:
            bounded_prominence = min(max(float(eff_prominence), 0.0), 1.0)
            prominence_addition = weights.importance_weight * bounded_prominence

    total = category_score + rating_score + prominence_addition
    if place.is_popular:
        total += weights.popular_bonus
    if place.is_heritage:
        total += weights.heritage_bonus
    if place.is_local_speciality:
        total += weights.local_speciality_bonus
    if distance_from_city_km is not None:
        proximity_ratio = max(
            0.0,
            1.0 - (distance_from_city_km / weights.start_proximity_radius_km),
        )
        total += weights.start_proximity_bonus * proximity_ratio

    # 4. Access confidence adjustment
    if access_confidence == AccessConfidence.UNKNOWN:
        total = max(0.0, total - weights.unknown_access_penalty)
    elif access_confidence in (
        AccessConfidence.RESTRICTED,
        AccessConfidence.RESTRICTED_LIKELY,
    ):
        total = 0.0

    return round(min(max(total, 0.0), 100.0), 1)


def explain_recommendation_score(
    place: Place,
    *,
    matched_category_count: int = 1,
    selected_category_count: int = 1,
    access_confidence: AccessConfidence = AccessConfidence.PUBLIC_LIKELY,
    distance_from_city_km: float | None = None,
    weights: RecommendationWeights = DEFAULT_RECOMMENDATION_WEIGHTS,
    relevance_score: float | None = None,
    prominence_score: float | None = None,
) -> dict[str, Any]:
    """Inspectable breakdown of all score components for debugging and tests."""
    if relevance_score is not None:
        category_score = relevance_score
    else:
        category_ratio = (
            matched_category_count / selected_category_count
            if selected_category_count > 0
            else 0.0
        )
        category_score = weights.category_match * min(category_ratio, 1.0)

    rating_score = 0.0
    if place.rating is not None:
        review_confidence = min(
            log10(max(place.review_count, 0) + 1)
            / log10(weights.review_reference_count + 1),
            1.0,
        )
        confidence_multiplier = weights.review_confidence_floor + (
            (1.0 - weights.review_confidence_floor) * review_confidence
        )
        rating_score = (
            weights.rating_confidence * (place.rating / 5.0) * confidence_multiplier
        )

    prominence_addition = 0.0
    eff_prominence = prominence_score
    if eff_prominence is None:
        eff_prominence = getattr(place, "importance_score", None)
    if eff_prominence is None and getattr(place, "wikidata_id", None):
        eff_prominence = PlaceImportanceScorer.lookup_audiala_prominence(
            place.wikidata_id
        )

    if (
        category_score > 0.0
        and weights.importance_weight > 0.0
        and eff_prominence is not None
        and eff_prominence > 0.0
    ):
        bounded_prominence = min(max(float(eff_prominence), 0.0), 1.0)
        prominence_addition = weights.importance_weight * bounded_prominence

    bonuses = {
        "popular": weights.popular_bonus if place.is_popular else 0.0,
        "heritage": weights.heritage_bonus if place.is_heritage else 0.0,
        "local_speciality": weights.local_speciality_bonus
        if place.is_local_speciality
        else 0.0,
        "start_proximity": (
            weights.start_proximity_bonus
            * max(
                0.0,
                1.0 - (distance_from_city_km / weights.start_proximity_radius_km),
            )
            if distance_from_city_km is not None
            else 0.0
        ),
    }
    penalties = {
        "access": weights.unknown_access_penalty
        if access_confidence == AccessConfidence.UNKNOWN
        else 0.0
    }

    raw_total = (
        category_score
        + rating_score
        + prominence_addition
        + sum(bonuses.values())
        - sum(penalties.values())
    )
    if access_confidence in (
        AccessConfidence.RESTRICTED,
        AccessConfidence.RESTRICTED_LIKELY,
    ):
        final_score = 0.0
    else:
        final_score = round(min(max(raw_total, 0.0), 100.0), 1)

    return {
        "final_score": final_score,
        "category_relevance": round(category_score, 2),
        "rating_score": round(rating_score, 2),
        "prominence_score": round(eff_prominence or 0.0, 4),
        "prominence_addition": round(prominence_addition, 2),
        "bonuses": bonuses,
        "penalties": penalties,
    }


def generate_recommendation_reason(
    place: Place,
    matched_categories: list[DiscoveryCategory],
    access_confidence: AccessConfidence,
) -> str:
    """Fallback reason generator using matched DiscoveryCategory values."""
    matched_names = [c.value for c in matched_categories]
    if DiscoveryCategory.FOOD.value in matched_names:
        if place.is_local_speciality:
            return "Local speciality dining matching your food interest"
        if place.is_popular:
            return "Popular dining spot for your trip"
        return "Matches your food preferences"

    if DiscoveryCategory.HERITAGE.value in matched_names:
        if place.is_heritage:
            return "Historic landmark matching your heritage interest"
        return "Heritage attraction in the city"

    if DiscoveryCategory.RELIGIOUS.value in matched_names:
        return "Place of worship matching your spiritual interests"

    if DiscoveryCategory.CAFES.value in matched_names:
        return "Public cafe matching your trip preferences"

    if DiscoveryCategory.TOURISM.value in matched_names:
        if place.is_popular:
            return "Notable attraction for travellers"
        return "Scenic or cultural highlight"

    return "Recommended for your trip itinerary"


class RecommendationService:
    """Discover, deduplicate, filter for suitability, and rank places for travellers."""

    def __init__(
        self,
        discovery: RecommendationDiscovery,
        *,
        weights: RecommendationWeights = DEFAULT_RECOMMENDATION_WEIGHTS,
        preference_config: PreferenceWeightingConfig = DEFAULT_PREFERENCE_CONFIG,
    ) -> None:
        self._discovery = discovery
        self._weights = weights
        self._preference_config = preference_config

    async def recommend(
        self,
        *,
        session: Session,
        city: City,
        request: RecommendationRequest,
    ) -> list[RecommendationRead]:
        t_rec_start = time.monotonic()
        # Stage 1: Candidate Retrieval
        categories_to_retrieve = list(dict.fromkeys(request.categories))
        if (
            request.category_filter is not None
            and request.category_filter not in categories_to_retrieve
        ):
            categories_to_retrieve.append(request.category_filter)

        discover_many = getattr(self._discovery, "discover_many", None)
        if callable(discover_many):
            places_by_category = await discover_many(  # type: ignore[misc]
                session=session,
                city=city,
                categories=categories_to_retrieve,
            )
        else:
            places_by_category = {}
            for category in categories_to_retrieve:
                places_by_category[category] = await self._discovery.discover(
                    session=session,
                    city=city,
                    category=category,
                )

        raw_candidates: list[Place] = []
        for category in categories_to_retrieve:
            raw_candidates.extend(places_by_category.get(category, []))

        t_retrieval_ms = (time.monotonic() - t_rec_start) * 1000
        if not raw_candidates:
            logger.info(
                "Recommendation candidate retrieval empty for city=%s: retrieval=%.1fms",
                city.name,
                t_retrieval_ms,
            )
            return []

        logger.info(
            "Recommendation candidate retrieval for city=%s: %d raw candidates across %d categories in %.1fms",
            city.name,
            len(raw_candidates),
            len(categories_to_retrieve),
            t_retrieval_ms,
        )

        # Fetch PlaceSource records for identity deduplication
        candidate_ids = list({p.id for p in raw_candidates})
        place_sources = list(
            session.exec(
                select(PlaceSource).where(
                    PlaceSource.place_id.in_(candidate_ids)  # type: ignore[union-attr]
                )
            ).all()
        )

        # Stage 2: Canonical & Spatial Deduplication
        deduped_candidates = deduplicate_places(
            places=raw_candidates,
            place_sources=place_sources,
        )

        logger.info(
            "Recommendation candidates after deduplication for city=%s: %d (from %d raw)",
            city.name,
            len(deduped_candidates),
            len(raw_candidates),
        )

        # Fetch tags for suitability and category/preference matching
        deduped_ids = [p.id for p in deduped_candidates]
        tags_by_place: dict[UUID, set[str]] = {pid: set() for pid in deduped_ids}
        tag_rows = session.exec(
            select(PlaceTag).where(
                PlaceTag.place_id.in_(deduped_ids)  # type: ignore[union-attr]
            )
        ).all()
        for tag_row in tag_rows:
            tags_by_place.setdefault(tag_row.place_id, set()).add(tag_row.tag)

        # Check existing saved places & stored preferences if trip_id is provided
        saved_place_ids: set[UUID] = set()
        stored_purposes: list[str] = []
        stored_interests: list[str] = []
        ranking_origin: tuple[float, float] | None = None
        if request.trip_id is not None:
            trip = session.get(Trip, request.trip_id)
            if (
                trip is not None
                and trip.start_latitude is not None
                and trip.start_longitude is not None
            ):
                ranking_origin = (trip.start_latitude, trip.start_longitude)
            saved_rows = session.exec(
                select(UserSavedPlace.place_id).where(
                    UserSavedPlace.trip_id == request.trip_id
                )
            ).all()
            saved_place_ids = set(saved_rows)

            pref_rows = session.exec(
                select(TripPreference).where(TripPreference.trip_id == request.trip_id)
            ).all()
            for pref in pref_rows:
                # Weight > 1.0 indicates primary purpose, <= 1.0 indicates secondary interest
                if pref.weight > 1.0:
                    stored_purposes.append(pref.preference)
                else:
                    stored_interests.append(pref.preference)

        # Determine effective purposes and interests
        effective_purposes: list[str] = (
            request.purposes if request.purposes is not None else stored_purposes
        )
        effective_interests: list[str] = (
            request.interests if request.interests is not None else stored_interests
        )

        has_explicit_preferences = bool(effective_purposes or effective_interests)

        # Stage 3: Traveller Suitability, Filtering & Quality Scoring
        evaluated: list[tuple[float, RecommendationRead]] = []

        for place in deduped_candidates:
            place_tags = tags_by_place.get(place.id, set())

            # 3a. Evaluate suitability (drop institutional canteens/messes immediately)
            suitable, access_conf = is_traveller_suitable(
                name=place.name,
                category=place.category,
                tags=place_tags,
            )
            if not suitable:
                continue

            # 3b. Category filter interaction: if filter is applied, narrow candidate set
            match_signals = {
                place.category.casefold(),
                *(t.casefold() for t in place_tags),
            }
            if request.category_filter is not None:
                filter_val = request.category_filter.value.casefold()
                if (
                    filter_val not in match_signals
                    and place.category.casefold() != filter_val
                ):
                    continue

            # 3c. Matched categories
            matched_categories = [
                category
                for category in request.categories
                if category.value.casefold() in match_signals
            ]
            if not matched_categories:
                matched_categories = [
                    cat
                    for cat in request.categories
                    if cat.value.casefold() == place.category.casefold()
                ]

            # 3d. Preference fit and relevance score
            relevance_score, matched_purposes, matched_interests = (
                evaluate_preference_fit(
                    place,
                    place_tags,
                    purposes=effective_purposes,
                    interests=effective_interests,
                    config=self._preference_config,
                )
            )

            # Low relevance cutoff: omit places with near-zero fit when preferences exist
            if (
                has_explicit_preferences
                and relevance_score < self._preference_config.min_relevance_score
            ):
                continue

            # 3e. Score calculation
            dist_km: float | None = None
            if ranking_origin is not None:
                dist_m = haversine_distance_meters(
                    ranking_origin[0],
                    ranking_origin[1],
                    place.latitude,
                    place.longitude,
                )
                dist_km = dist_m / 1000.0

            # Prominence resolution: check Place.importance_score, then place_tags, then Audiala lookup
            prominence = getattr(place, "importance_score", None)
            if prominence is None:
                prominence = PlaceImportanceScorer.extract_prominence_from_tags(
                    place_tags
                )
                if (prominence is None or prominence == 0.0) and place.wikidata_id:
                    prominence = PlaceImportanceScorer.lookup_audiala_prominence(
                        place.wikidata_id
                    )

            score = calculate_recommendation_score(
                place,
                matched_category_count=len(matched_categories),
                selected_category_count=len(request.categories),
                access_confidence=access_conf,
                distance_from_city_km=dist_km,
                weights=self._weights,
                relevance_score=relevance_score if has_explicit_preferences else None,
                prominence_score=prominence,
            )

            # 3f. Recommendation reason
            if has_explicit_preferences:
                reason = generate_preference_explanation(
                    place,
                    matched_purposes=matched_purposes,
                    matched_interests=matched_interests,
                    access_confidence=access_conf,
                )
            else:
                reason = generate_recommendation_reason(
                    place,
                    matched_categories,
                    access_conf,
                )

            is_saved = place.id in saved_place_ids

            read_model = RecommendationRead(
                id=place.id,
                name=place.name,
                category=place.category,
                latitude=place.latitude,
                longitude=place.longitude,
                rating=place.rating,
                review_count=place.review_count,
                is_popular=place.is_popular,
                is_heritage=place.is_heritage,
                is_local_speciality=place.is_local_speciality,
                matched_categories=matched_categories,
                recommendation_score=score,
                recommendation_reason=reason,
                access_confidence=access_conf.value,
                is_saved=is_saved,
            )
            evaluated.append((score, read_model))

        logger.info(
            "Recommendation candidates after suitability filtering for city=%s: %d (from %d deduped)",
            city.name,
            len(evaluated),
            len(deduped_candidates),
        )

        # Stage 4: Ranking & Soft Diversity
        # Sort initially by score descending, then rating, review count, name
        evaluated.sort(
            key=lambda item: (
                -item[0],  # highest score first
                -(item[1].rating if item[1].rating is not None else -1.0),
                -item[1].review_count,
                item[1].name.casefold(),
            )
        )

        # Stage 4b: Soft diversity interleaving
        # In mixed-interest trips, ensure secondary requested interests are represented
        # without allowing an abundant primary category to completely monopolize recommendations.
        has_mixed_prefs = len(effective_purposes) + len(effective_interests) > 1 or any(
            normalize_preference_key(p) in ("mixed", "family")
            for p in effective_purposes
        )

        ranked: list[RecommendationRead] = []
        pool = [item[1] for item in evaluated]
        consecutive_cat_count = 0
        current_cat: str | None = None

        while pool:
            if (
                not has_mixed_prefs
                or consecutive_cat_count
                < self._preference_config.max_consecutive_same_category
            ):
                chosen = pool.pop(0)
            else:
                # Seek best available candidate from an alternative category
                alt_idx = next(
                    (
                        idx
                        for idx, p in enumerate(pool)
                        if p.category.casefold() != current_cat
                    ),
                    None,
                )
                if alt_idx is not None:
                    chosen = pool.pop(alt_idx)
                else:
                    chosen = pool.pop(0)

            if current_cat == chosen.category.casefold():
                consecutive_cat_count += 1
            else:
                current_cat = chosen.category.casefold()
                consecutive_cat_count = 1

            ranked.append(chosen)

        # Stage 5: Final Deduplication & Multi-Outlet Brand Capping Safeguard
        final_results: list[RecommendationRead] = []
        seen_venue_names: set[str] = set()

        for item in ranked:
            name_norm = item.name.strip().casefold()

            # 5a. Cap multi-outlet identical chain/brand names to 1 representative instance
            # (e.g. avoid recommending 6 Domino's or 3 Burger Kings across a city)
            if name_norm in seen_venue_names:
                continue

            # 5b. Near-duplicate and spatial proximity merge (<= 150m with similar name)
            is_dup = False
            for prev in final_results:
                dist = haversine_distance_meters(
                    prev.latitude,
                    prev.longitude,
                    item.latitude,
                    item.longitude,
                )
                if dist <= 150.0 and are_names_similar(prev.name, item.name):
                    is_dup = True
                    break

            if not is_dup:
                seen_venue_names.add(name_norm)
                final_results.append(item)
                if len(final_results) >= request.limit:
                    break

        total_rec_ms = (time.monotonic() - t_rec_start) * 1000
        logger.info(
            "Recommendation completed for city=%s: candidates=%d final=%d total=%.1fms",
            city.name,
            len(raw_candidates),
            len(final_results),
            total_rec_ms,
        )
        return final_results
