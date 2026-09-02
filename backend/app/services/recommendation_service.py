"""Explainable ranking and multi-stage pipeline for place recommendations.

Implements:
1. Candidate Retrieval across requested categories
2. Canonical & Spatial Deduplication
3. Traveller-Suitability & Access Confidence Filtering
4. Food Intent & Category Relevance Matching
5. Deterministic Scoring without fabricated popularity/ratings
6. Diversity-aware Final Ranking and Explanation Generation
"""

from __future__ import annotations

from dataclasses import dataclass
from math import log10
from typing import Any, Protocol
from uuid import UUID

from sqlmodel import Session, select

from app.models.entities import City, Place, PlaceSource, PlaceTag, UserSavedPlace
from app.schemas.recommendation import (
    DiscoveryCategory,
    RecommendationRead,
    RecommendationRequest,
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
    popular_bonus: float = 10.0
    heritage_bonus: float = 8.0
    local_speciality_bonus: float = 7.0
    unknown_access_penalty: float = 15.0
    review_reference_count: int = 20000
    review_confidence_floor: float = 0.35


DEFAULT_RECOMMENDATION_WEIGHTS = RecommendationWeights()


def calculate_recommendation_score(
    place: Place,
    *,
    matched_category_count: int,
    selected_category_count: int,
    access_confidence: AccessConfidence = AccessConfidence.PUBLIC_LIKELY,
    distance_from_city_km: float | None = None,
    weights: RecommendationWeights = DEFAULT_RECOMMENDATION_WEIGHTS,
) -> float:
    """Return a 0-100 score combining preference fit, access confidence, and verified quality."""
    # 1. Category fit
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

    total = category_score + rating_score
    if place.is_popular:
        total += weights.popular_bonus
    if place.is_heritage:
        total += weights.heritage_bonus
    if place.is_local_speciality:
        total += weights.local_speciality_bonus

    # 3. Access confidence adjustment
    if access_confidence == AccessConfidence.UNKNOWN:
        total = max(0.0, total - weights.unknown_access_penalty)
    elif access_confidence in (AccessConfidence.RESTRICTED, AccessConfidence.RESTRICTED_LIKELY):
        total = 0.0

    return round(min(max(total, 0.0), 100.0), 1)


def generate_recommendation_reason(
    place: Place,
    matched_categories: list[DiscoveryCategory],
    access_confidence: AccessConfidence,
) -> str:
    """Generate a natural, provider-neutral reason explaining the recommendation."""
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
    ) -> None:
        self._discovery = discovery
        self._weights = weights

    async def recommend(
        self,
        *,
        session: Session,
        city: City,
        request: RecommendationRequest,
    ) -> list[RecommendationRead]:
        # Stage 1: Candidate Retrieval
        discover_many: Any = getattr(self._discovery, "discover_many", None)
        if callable(discover_many):
            places_by_category = await discover_many(
                session=session,
                city=city,
                categories=request.categories,
            )
        else:
            places_by_category = {}
            for category in request.categories:
                places_by_category[category] = await self._discovery.discover(
                    session=session,
                    city=city,
                    category=category,
                )

        raw_candidates: list[Place] = []
        for category in request.categories:
            raw_candidates.extend(places_by_category.get(category, []))

        if not raw_candidates:
            return []

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

        # Fetch tags for suitability and category matching
        deduped_ids = [p.id for p in deduped_candidates]
        tags_by_place: dict[UUID, set[str]] = {pid: set() for pid in deduped_ids}
        tag_rows = session.exec(
            select(PlaceTag).where(
                PlaceTag.place_id.in_(deduped_ids)  # type: ignore[union-attr]
            )
        ).all()
        for tag_row in tag_rows:
            tags_by_place.setdefault(tag_row.place_id, set()).add(tag_row.tag)

        # Check existing saved places if trip_id is provided
        saved_place_ids: set[UUID] = set()
        if request.trip_id is not None:
            saved_rows = session.exec(
                select(UserSavedPlace.place_id).where(
                    UserSavedPlace.trip_id == request.trip_id
                )
            ).all()
            saved_place_ids = set(saved_rows)

        # Stage 3: Traveller Suitability & Quality Scoring
        evaluated: list[tuple[float, RecommendationRead]] = []

        for place in deduped_candidates:
            place_tags = tags_by_place.get(place.id, set())

            # 3a. Evaluate suitability
            suitable, access_conf = is_traveller_suitable(
                name=place.name,
                category=place.category,
                tags=place_tags,
            )
            # Filter out unsuitable places (e.g. internal college canteens, staff cafeterias)
            if not suitable:
                continue

            # 3b. Matched categories
            match_signals = {place.category.casefold(), *(t.casefold() for t in place_tags)}
            matched_categories = [
                category
                for category in request.categories
                if category.value.casefold() in match_signals
            ]
            if not matched_categories:
                # If category didn't match via tags, check primary place category
                matched_categories = [
                    cat for cat in request.categories if cat.value.casefold() == place.category.casefold()
                ]

            # 3c. Distance to city coordinates
            dist_km: float | None = None
            if city.latitude is not None and city.longitude is not None:
                dist_m = haversine_distance_meters(
                    city.latitude,
                    city.longitude,
                    place.latitude,
                    place.longitude,
                )
                dist_km = dist_m / 1000.0

            # 3d. Score calculation
            score = calculate_recommendation_score(
                place,
                matched_category_count=len(matched_categories),
                selected_category_count=len(request.categories),
                access_confidence=access_conf,
                distance_from_city_km=dist_km,
                weights=self._weights,
            )

            # 3e. Recommendation reason
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

        # Stage 4: Ranking & Diversity
        evaluated.sort(
            key=lambda item: (
                -item[0],  # highest score first
                -(item[1].rating if item[1].rating is not None else -1.0),
                -item[1].review_count,
                item[1].name.casefold(),
            )
        )

        ranked = [item[1] for item in evaluated]

        # Stage 5: Final Canonical Safeguard
        final_results: list[RecommendationRead] = []
        final_seen_names: set[str] = set()
        for item in ranked:
            name_norm = item.name.strip().casefold()
            # Double check against identical exact names within 100m in final output
            is_dup = False
            for prev in final_results:
                if prev.name.strip().casefold() == name_norm:
                    dist = haversine_distance_meters(
                        prev.latitude,
                        prev.longitude,
                        item.latitude,
                        item.longitude,
                    )
                    if dist <= 100.0:
                        is_dup = True
                        break
            if not is_dup:
                final_results.append(item)
                if len(final_results) >= request.limit:
                    break

        return final_results
