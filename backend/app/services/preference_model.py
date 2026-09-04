"""Centralized preference model and category/tag weighting for recommendations.

Maps user trip purposes and secondary interests to normalized place categories
and tags, applying deterministic weighting and explainable reason generation.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

from app.models.entities import Place
from app.schemas.recommendation import DiscoveryCategory
from app.services.place_suitability_service import AccessConfidence


@dataclass(frozen=True, slots=True)
class PreferenceWeightingConfig:
    """Centralized tuning weights and multipliers for recommendation scoring."""

    # Base score components (total base = 100 points)
    relevance_weight: float = 55.0  # Dominant preference fit component
    rating_confidence_weight: float = 30.0  # Real verified rating & review volume
    importance_weight: float = 15.0  # Normalized Wikidata/Audiala prominence signal
    popular_bonus: float = 6.0
    heritage_bonus: float = 5.0
    local_speciality_bonus: float = 4.0

    # Weight multipliers for preference tiers
    purpose_multiplier: float = 2.5  # Primary trip purpose is 2.5x stronger than secondary interest
    interest_multiplier: float = 1.0  # Secondary interest base weight

    # Category and tag match weights
    primary_category_fit: float = 1.0
    secondary_category_fit: float = 0.5
    tag_high_fit: float = 0.35
    tag_medium_fit: float = 0.15

    # Penalties
    unknown_access_penalty: float = 12.0

    # Low relevance cutoff threshold
    min_relevance_score: float = 8.0  # Omit places below this relevance fit when preferences exist

    # Diversity safeguards
    max_consecutive_same_category: int = 2  # Max items in sequence from same category in mixed trips
    diversity_candidate_threshold_ratio: float = 0.70  # Only elevate diverse candidates if score >= 70% of top

    # Review confidence normalization
    review_reference_count: int = 20000
    review_confidence_floor: float = 0.35


DEFAULT_PREFERENCE_CONFIG = PreferenceWeightingConfig()


@dataclass(frozen=True, slots=True)
class PreferenceAffinity:
    """Targeted categories and affinity tags for a normalized preference."""

    primary_categories: tuple[DiscoveryCategory, ...]
    secondary_categories: tuple[DiscoveryCategory, ...]
    high_affinity_tags: frozenset[str]
    medium_affinity_tags: frozenset[str]


# Centralized taxonomy mapping from normalized preference strings to place categories and tags
_PREFERENCE_AFFINITIES: dict[str, PreferenceAffinity] = {
    "food": PreferenceAffinity(
        primary_categories=(DiscoveryCategory.FOOD,),
        secondary_categories=(DiscoveryCategory.CAFES,),
        high_affinity_tags=frozenset({
            "restaurant",
            "food",
            "food_court",
            "fast_food",
            "dhaba",
            "bhojanalaya",
            "vegetarian",
            "thali",
            "street_food",
            "local_speciality",
        }),
        medium_affinity_tags=frozenset({
            "cafe",
            "bakery",
            "ice_cream",
            "tea",
            "coffee_shop",
            "sweets",
            "snacks",
        }),
    ),
    "religious": PreferenceAffinity(
        primary_categories=(DiscoveryCategory.RELIGIOUS,),
        secondary_categories=(DiscoveryCategory.HERITAGE,),
        high_affinity_tags=frozenset({
            "place_of_worship",
            "religious",
            "temple",
            "mandir",
            "derasar",
            "gurdwara",
            "mosque",
            "dargah",
            "church",
            "ashram",
            "ghat",
            "monastery",
            "hindu",
            "jain",
            "sikh",
            "muslim",
            "christian",
            "buddhist",
        }),
        medium_affinity_tags=frozenset({
            "historic",
            "heritage",
            "monument",
            "pilgrimage",
            "spiritual",
        }),
    ),
    "heritage": PreferenceAffinity(
        primary_categories=(DiscoveryCategory.HERITAGE,),
        secondary_categories=(DiscoveryCategory.TOURISM, DiscoveryCategory.RELIGIOUS),
        high_affinity_tags=frozenset({
            "historic",
            "heritage",
            "monument",
            "fort",
            "palace",
            "ruins",
            "archaeological_site",
            "castle",
            "memorial",
            "unesco",
        }),
        medium_affinity_tags=frozenset({
            "museum",
            "gallery",
            "attraction",
            "arts_centre",
            "viewpoint",
            "place_of_worship",
        }),
    ),
    "nature": PreferenceAffinity(
        primary_categories=(DiscoveryCategory.TOURISM,),
        secondary_categories=(DiscoveryCategory.HERITAGE,),
        high_affinity_tags=frozenset({
            "park",
            "garden",
            "nature_reserve",
            "waterfall",
            "lake",
            "viewpoint",
            "zoo",
            "beach",
            "forest",
            "scenic",
        }),
        medium_affinity_tags=frozenset({
            "attraction",
            "memorial",
            "tourism",
        }),
    ),
    "sightseeing": PreferenceAffinity(
        primary_categories=(DiscoveryCategory.TOURISM, DiscoveryCategory.HERITAGE),
        secondary_categories=(DiscoveryCategory.RELIGIOUS,),
        high_affinity_tags=frozenset({
            "attraction",
            "viewpoint",
            "monument",
            "fort",
            "palace",
            "museum",
            "historic",
            "heritage",
        }),
        medium_affinity_tags=frozenset({
            "park",
            "place_of_worship",
            "gallery",
            "square",
        }),
    ),
    "cafes": PreferenceAffinity(
        primary_categories=(DiscoveryCategory.CAFES,),
        secondary_categories=(DiscoveryCategory.FOOD,),
        high_affinity_tags=frozenset({
            "cafe",
            "cafes",
            "coffee_shop",
            "tea",
            "bakery",
            "dessert",
        }),
        medium_affinity_tags=frozenset({
            "restaurant",
            "fast_food",
            "snacks",
            "ice_cream",
        }),
    ),
    "shopping": PreferenceAffinity(
        primary_categories=(DiscoveryCategory.TOURISM,),
        secondary_categories=(DiscoveryCategory.FOOD,),
        high_affinity_tags=frozenset({
            "marketplace",
            "market",
            "bazaar",
            "mall",
            "craft",
            "shopping",
        }),
        medium_affinity_tags=frozenset({
            "attraction",
            "street_food",
            "cafe",
        }),
    ),
    "photography": PreferenceAffinity(
        primary_categories=(DiscoveryCategory.HERITAGE, DiscoveryCategory.TOURISM),
        secondary_categories=(DiscoveryCategory.RELIGIOUS,),
        high_affinity_tags=frozenset({
            "viewpoint",
            "monument",
            "fort",
            "palace",
            "lake",
            "ruins",
            "attraction",
            "scenic",
        }),
        medium_affinity_tags=frozenset({
            "park",
            "place_of_worship",
            "heritage",
            "garden",
        }),
    ),
    "relaxation": PreferenceAffinity(
        primary_categories=(DiscoveryCategory.TOURISM,),
        secondary_categories=(DiscoveryCategory.CAFES, DiscoveryCategory.HERITAGE),
        high_affinity_tags=frozenset({
            "park",
            "garden",
            "lake",
            "scenic",
            "cafe",
            "viewpoint",
        }),
        medium_affinity_tags=frozenset({
            "attraction",
            "heritage",
            "temple",
        }),
    ),
    "family": PreferenceAffinity(
        primary_categories=(DiscoveryCategory.TOURISM, DiscoveryCategory.HERITAGE),
        secondary_categories=(DiscoveryCategory.FOOD,),
        high_affinity_tags=frozenset({
            "park",
            "garden",
            "zoo",
            "museum",
            "attraction",
            "theme_park",
            "monument",
        }),
        medium_affinity_tags=frozenset({
            "restaurant",
            "food",
            "viewpoint",
        }),
    ),
    "mixed": PreferenceAffinity(
        primary_categories=(
            DiscoveryCategory.TOURISM,
            DiscoveryCategory.HERITAGE,
            DiscoveryCategory.FOOD,
            DiscoveryCategory.RELIGIOUS,
            DiscoveryCategory.CAFES,
        ),
        secondary_categories=(),
        high_affinity_tags=frozenset(),
        medium_affinity_tags=frozenset(),
    ),
}


def normalize_preference_key(raw_value: str) -> str:
    """Normalize user-facing purpose/interest strings into canonical lookup keys."""
    val = raw_value.strip().casefold()
    if "food" in val or "dining" in val or "culinary" in val:
        return "food"
    if "religio" in val or "spiritual" in val or "pilgrimage" in val or "temple" in val:
        return "religious"
    if "heritage" in val or "culture" in val or "historic" in val or "monument" in val:
        return "heritage"
    if "cafe" in val or "coffee" in val:
        return "cafes"
    if "nature" in val or "wildlife" in val or "outdoor" in val:
        return "nature"
    if "sightseeing" in val or "touris" in val:
        return "sightseeing"
    if "shopping" in val or "market" in val or "bazaar" in val:
        return "shopping"
    if "photo" in val:
        return "photography"
    if "relax" in val or "wellness" in val:
        return "relaxation"
    if "family" in val:
        return "family"
    if "mixed" in val:
        return "mixed"
    return val


def get_categories_for_preferences(
    purposes: Sequence[str],
    interests: Sequence[str] = (),
) -> list[DiscoveryCategory]:
    """Return the set of DiscoveryCategory items required to cover the selected purposes and interests."""
    categories: list[DiscoveryCategory] = []
    seen: set[DiscoveryCategory] = set()

    for item in [*purposes, *interests]:
        key = normalize_preference_key(item)
        affinity = _PREFERENCE_AFFINITIES.get(key)
        if affinity:
            for cat in (*affinity.primary_categories, *affinity.secondary_categories):
                if cat not in seen:
                    seen.add(cat)
                    categories.append(cat)
        else:
            # Check if it directly matches a DiscoveryCategory enum value
            for cat in DiscoveryCategory:
                if cat.value.casefold() == key and cat not in seen:
                    seen.add(cat)
                    categories.append(cat)

    if not categories:
        return list(DiscoveryCategory)
    return categories


def evaluate_preference_fit(
    place: Place,
    place_tags: set[str],
    *,
    purposes: Sequence[str],
    interests: Sequence[str],
    config: PreferenceWeightingConfig = DEFAULT_PREFERENCE_CONFIG,
) -> tuple[float, list[str], list[str]]:
    """Evaluate how strongly a place matches the user's purposes and secondary interests.

    Returns:
        (relevance_score, matched_purpose_keys, matched_interest_keys)
        relevance_score is normalized in [0.0, config.relevance_weight].
    """
    if not purposes and not interests:
        # Neutral fallback when no specific preferences are provided
        return config.relevance_weight * 0.5, [], []

    place_cat = place.category.casefold()
    norm_tags = {t.casefold() for t in place_tags}
    signals = {place_cat, *norm_tags}

    purpose_keys = [normalize_preference_key(p) for p in purposes]
    interest_keys = [normalize_preference_key(i) for i in interests]

    matched_purposes: list[str] = []
    matched_interests: list[str] = []

    raw_purpose_score = 0.0
    raw_interest_score = 0.0

    # 1. Purpose scoring (stronger tier: purpose_multiplier)
    for p_key in purpose_keys:
        affinity = _PREFERENCE_AFFINITIES.get(p_key)
        if not affinity:
            if p_key in signals:
                raw_purpose_score += config.primary_category_fit
                matched_purposes.append(p_key)
            continue

        p_fit = 0.0
        primary_match = any(c.value.casefold() in signals for c in affinity.primary_categories)
        secondary_match = any(c.value.casefold() in signals for c in affinity.secondary_categories)

        if primary_match:
            p_fit += config.primary_category_fit
        elif secondary_match:
            p_fit += config.secondary_category_fit

        if norm_tags & affinity.high_affinity_tags:
            p_fit += config.tag_high_fit
        if norm_tags & affinity.medium_affinity_tags:
            p_fit += config.tag_medium_fit

        if place.is_local_speciality and p_key == "food":
            p_fit += 0.25
        if place.is_heritage and p_key in ("heritage", "religious", "sightseeing"):
            p_fit += 0.25

        if p_fit > 0.0:
            raw_purpose_score += p_fit
            matched_purposes.append(p_key)

    # 2. Interest scoring (secondary tier: interest_multiplier)
    for i_key in interest_keys:
        if i_key in purpose_keys:
            continue  # Already accounted for in primary purpose

        affinity = _PREFERENCE_AFFINITIES.get(i_key)
        if not affinity:
            if i_key in signals:
                raw_interest_score += config.primary_category_fit
                matched_interests.append(i_key)
            continue

        i_fit = 0.0
        primary_match = any(c.value.casefold() in signals for c in affinity.primary_categories)
        secondary_match = any(c.value.casefold() in signals for c in affinity.secondary_categories)

        if primary_match:
            i_fit += config.primary_category_fit
        elif secondary_match:
            i_fit += config.secondary_category_fit

        if norm_tags & affinity.high_affinity_tags:
            i_fit += config.tag_high_fit
        if norm_tags & affinity.medium_affinity_tags:
            i_fit += config.tag_medium_fit

        if i_fit > 0.0:
            raw_interest_score += i_fit
            matched_interests.append(i_key)

    # Combine weighted fit
    # Max achievable single match is around 1.6 (primary + tag + attribute)
    weighted_fit = (
        (raw_purpose_score * config.purpose_multiplier)
        + (raw_interest_score * config.interest_multiplier)
    )

    # Normalization baseline: scale against primary purpose dominance
    max_baseline = (
        (len(purpose_keys) * config.purpose_multiplier * 1.5)
        + (len(interest_keys) * config.interest_multiplier * 1.2)
    )
    if max_baseline <= 0.0:
        max_baseline = 1.0

    normalized_ratio = min(weighted_fit / max_baseline, 1.0)
    final_relevance = round(normalized_ratio * config.relevance_weight, 2)

    return final_relevance, matched_purposes, matched_interests


def generate_preference_explanation(
    place: Place,
    matched_purposes: Sequence[str],
    matched_interests: Sequence[str],
    access_confidence: AccessConfidence,
) -> str:
    """Generate a natural, truthful, provider-neutral reason explaining the match."""
    p_set = set(matched_purposes)
    i_set = set(matched_interests)

    # Combined purpose + interest matches
    if "food" in p_set and "cafes" in i_set:
        return "Matches your food focus and interest in cafes"
    if "food" in p_set and "heritage" in i_set:
        return "Matches your food focus and historic interests"
    if "religious" in p_set and "heritage" in i_set:
        return "Spiritual landmark matching your heritage interest"
    if "heritage" in p_set and "food" in i_set:
        return "Heritage site matching your local food interest"

    # Purpose matches
    if "food" in p_set:
        if place.is_local_speciality:
            return "Local speciality matching your food-focused trip"
        return "Matches your food-focused trip"

    if "religious" in p_set:
        return "Place of worship matching your spiritual journey"

    if "heritage" in p_set:
        if place.is_heritage:
            return "Historic landmark matching your heritage focus"
        return "Matches your culture & heritage focus"

    if "nature" in p_set:
        return "Scenic outdoor spot matching your nature focus"

    if "cafes" in p_set:
        return "Cafe matching your trip focus"

    if "sightseeing" in p_set:
        return "Notable attraction matching your sightseeing trip"

    if "photography" in p_set:
        return "Scenic spot matching your photography focus"

    if "shopping" in p_set:
        return "Marketplace matching your shopping interests"

    # Secondary interest matches
    if "food" in i_set:
        return "Matches your interest in local food"
    if "cafes" in i_set:
        return "Matches your interest in cafes"
    if "heritage" in i_set:
        return "Matches your interest in history"
    if "religious" in i_set:
        return "Matches your interest in religious sites"
    if "nature" in i_set:
        return "Matches your interest in nature"

    if place.is_heritage:
        return "Historic landmark for your itinerary"
    if place.is_local_speciality:
        return "Local dining spot for your trip"

    return "Recommended for your trip itinerary"
