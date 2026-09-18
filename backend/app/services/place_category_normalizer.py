"""Single category vocabulary shared by image lookup, API, and UI fallbacks."""

from __future__ import annotations

import re
from collections.abc import Iterable
from enum import Enum


class NormalizedPlaceCategory(str, Enum):
    LANDMARK = "landmark"
    PLACE_OF_WORSHIP = "place_of_worship"
    MUSEUM = "museum"
    FORT_PALACE = "fort_palace"
    PARK_GARDEN = "park_garden"
    LAKE_RIVERFRONT = "lake_riverfront"
    HILL_VIEWPOINT = "hill_viewpoint"
    MARKET_SHOPPING = "market_shopping"
    CAFE = "cafe"
    RESTAURANT = "restaurant"
    HOTEL = "hotel"
    BEACH = "beach"
    DESERT = "desert"
    WATERFALL = "waterfall"
    FOREST = "forest"
    WILDLIFE = "wildlife"
    ENTERTAINMENT = "entertainment"
    OTHER = "other"


_RULES: tuple[tuple[NormalizedPlaceCategory, tuple[str, ...]], ...] = (
    (NormalizedPlaceCategory.PLACE_OF_WORSHIP, ("religious", "worship", "temple", "mandir", "mosque", "church", "gurudwara", "shrine")),
    (NormalizedPlaceCategory.MUSEUM, ("museum", "gallery")),
    (NormalizedPlaceCategory.FORT_PALACE, ("fort", "palace", "castle", "citadel")),
    (NormalizedPlaceCategory.PARK_GARDEN, ("park", "garden", "botanical")),
    (NormalizedPlaceCategory.LAKE_RIVERFRONT, ("lake", "river", "riverfront", "ghat", "reservoir", "waterfront")),
    (NormalizedPlaceCategory.HILL_VIEWPOINT, ("hill", "viewpoint", "mountain", "peak", "lookout")),
    (NormalizedPlaceCategory.MARKET_SHOPPING, ("market", "shopping", "bazaar", "mall", "commercial")),
    (NormalizedPlaceCategory.CAFE, ("cafe", "coffee", "tea")),
    (NormalizedPlaceCategory.RESTAURANT, ("food", "restaurant", "dining", "eatery", "fast_food")),
    (NormalizedPlaceCategory.HOTEL, ("hotel", "lodging", "accommodation", "resort", "hostel")),
    (NormalizedPlaceCategory.BEACH, ("beach", "coast", "seaside")),
    (NormalizedPlaceCategory.DESERT, ("desert", "dune")),
    (NormalizedPlaceCategory.WATERFALL, ("waterfall", "falls", "cascade")),
    (NormalizedPlaceCategory.FOREST, ("forest", "woods", "woodland")),
    (NormalizedPlaceCategory.WILDLIFE, ("wildlife", "zoo", "safari", "sanctuary", "national park")),
    (NormalizedPlaceCategory.ENTERTAINMENT, ("entertainment", "cinema", "theatre", "theater", "amusement", "nightlife")),
    (NormalizedPlaceCategory.LANDMARK, ("heritage", "tourism", "attraction", "historic", "monument", "landmark", "sightseeing")),
)


def normalize_place_category(
    category: str | None,
    *,
    name: str | None = None,
    tags: Iterable[str] = (),
) -> NormalizedPlaceCategory:
    """Normalize broad provider/app labels without depending on a provider schema."""

    haystack = " ".join(
        part for part in (category or "", name or "", *tags) if part
    ).casefold()
    tokens = set(re.findall(r"[a-z0-9_]+", haystack))
    for normalized, needles in _RULES:
        for needle in needles:
            if " " in needle:
                if needle in haystack:
                    return normalized
            elif needle in tokens:
                return normalized
    return NormalizedPlaceCategory.OTHER


def is_business_category(category: NormalizedPlaceCategory) -> bool:
    return category in {
        NormalizedPlaceCategory.CAFE,
        NormalizedPlaceCategory.RESTAURANT,
        NormalizedPlaceCategory.HOTEL,
        NormalizedPlaceCategory.MARKET_SHOPPING,
        NormalizedPlaceCategory.ENTERTAINMENT,
    }


def is_nature_category(category: NormalizedPlaceCategory) -> bool:
    return category in {
        NormalizedPlaceCategory.PARK_GARDEN,
        NormalizedPlaceCategory.LAKE_RIVERFRONT,
        NormalizedPlaceCategory.HILL_VIEWPOINT,
        NormalizedPlaceCategory.BEACH,
        NormalizedPlaceCategory.DESERT,
        NormalizedPlaceCategory.WATERFALL,
        NormalizedPlaceCategory.FOREST,
        NormalizedPlaceCategory.WILDLIFE,
    }
