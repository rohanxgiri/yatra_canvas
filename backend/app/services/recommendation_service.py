"""Explainable ranking for multi-category place recommendations."""

from dataclasses import dataclass
from math import log10
from typing import Protocol
from uuid import UUID

from sqlmodel import Session, select

from app.models import City, Place, PlaceTag
from app.schemas import (
    DiscoveryCategory,
    RecommendationRead,
    RecommendationRequest,
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
    """Tunable score weights; the defaults add up to 100 points."""

    category_match: float = 40.0
    rating_confidence: float = 35.0
    popular_bonus: float = 10.0
    heritage_bonus: float = 8.0
    local_speciality_bonus: float = 7.0
    review_reference_count: int = 20000
    review_confidence_floor: float = 0.35


DEFAULT_RECOMMENDATION_WEIGHTS = RecommendationWeights()


def calculate_recommendation_score(
    place: Place,
    *,
    matched_category_count: int,
    selected_category_count: int,
    weights: RecommendationWeights = DEFAULT_RECOMMENDATION_WEIGHTS,
) -> float:
    """Return a 0-100 score combining preference fit and place quality."""

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

    total = category_score + rating_score
    if place.is_popular:
        total += weights.popular_bonus
    if place.is_heritage:
        total += weights.heritage_bonus
    if place.is_local_speciality:
        total += weights.local_speciality_bonus
    return round(min(max(total, 0.0), 100.0), 1)


class RecommendationService:
    """Discover selected categories, deduplicate, and rank their places."""

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
        candidates: dict[UUID, Place] = {}
        discover_many = getattr(self._discovery, "discover_many", None)
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

        for category in request.categories:
            places = places_by_category.get(category, [])
            for place in places:
                candidates[place.id] = place

        if not candidates:
            return []

        tags_by_place: dict[UUID, set[str]] = {
            place_id: set() for place_id in candidates
        }
        tag_rows = session.exec(
            select(PlaceTag).where(
                PlaceTag.place_id.in_(list(candidates))  # type: ignore[union-attr]
            )
        ).all()
        for tag_row in tag_rows:
            tags_by_place.setdefault(tag_row.place_id, set()).add(tag_row.tag)

        recommendations: list[RecommendationRead] = []
        for place in candidates.values():
            match_signals = {place.category, *tags_by_place.get(place.id, set())}
            matched_categories = [
                category
                for category in request.categories
                if category.value in match_signals
            ]
            score = calculate_recommendation_score(
                place,
                matched_category_count=len(matched_categories),
                selected_category_count=len(request.categories),
                weights=self._weights,
            )
            recommendations.append(
                RecommendationRead(
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
                )
            )

        recommendations.sort(
            key=lambda item: (
                -item.recommendation_score,
                -(item.rating if item.rating is not None else -1.0),
                -item.review_count,
                item.name.casefold(),
            )
        )
        return recommendations[: request.limit]
