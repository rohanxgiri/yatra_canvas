"""Deterministic classification layer for indoor vs. outdoor place exposure.

Uses existing Place categories, tags, and names to evaluate whether an attraction
is exposed to adverse weather (heat, rain, storms, wind) or offers sheltered,
weather-friendly indoor spaces (e.g. museums, galleries, shopping centers).

Limitations:
This heuristic classification is derived strictly from open taxonomy and title tokens.
It does not incorporate micro-climate metadata, covered courtyards, or air-conditioning
status, which are not present in open datasets.
"""

from enum import StrEnum
from typing import Final


class PlaceEnvironment(StrEnum):
    INDOOR = "indoor"
    OUTDOOR = "outdoor"
    DUAL = "dual"
    UNKNOWN = "unknown"


# Tokens strongly indicative of outdoor exposure
OUTDOOR_TOKENS: Final[frozenset[str]] = frozenset(
    {
        "park",
        "garden",
        "monument",
        "fort",
        "ruins",
        "lake",
        "beach",
        "viewpoint",
        "hiking",
        "nature",
        "nature_reserve",
        "outdoor",
        "campground",
        "zoo",
        "wildlife",
        "sanctuary",
        "stepwell",
        "ghat",
        "promenade",
        "bazaar",
        "market",
        "square",
        "waterfall",
        "sightseeing",
        "historic",
        "heritage",
    }
)

# Tokens strongly indicative of indoor sheltered environments
INDOOR_TOKENS: Final[frozenset[str]] = frozenset(
    {
        "museum",
        "gallery",
        "art_gallery",
        "mall",
        "shopping_mall",
        "theatre",
        "theater",
        "cinema",
        "library",
        "aquarium",
        "planetarium",
        "indoor",
        "palace_interior",
        "restaurant",
        "cafe",
        "cultural_centre",
        "cultural_center",
    }
)

# Venues with significant indoor and outdoor sections
DUAL_TOKENS: Final[frozenset[str]] = frozenset(
    {
        "palace",
        "temple",
        "mosque",
        "church",
        "ashram",
        "monastery",
    }
)


def classify_place(
    category: str,
    tags: list[str] | None = None,
    name: str | None = None,
) -> PlaceEnvironment:
    """Classify a place into indoor, outdoor, dual, or unknown based on category, tags, and name."""
    normalized_category = (category or "").lower().strip()
    tag_set = {t.lower().strip() for t in (tags or [])}
    name_words = {w.lower().strip() for w in (name or "").split()}

    all_tokens = {normalized_category} | tag_set | name_words

    # Primary taxonomy category takes precedence over decorative tokens in venue names
    category_indoor = any(token in INDOOR_TOKENS or any(it in token for it in INDOOR_TOKENS) for token in {normalized_category})
    category_outdoor = any(token in OUTDOOR_TOKENS or any(ot in token for ot in OUTDOOR_TOKENS) for token in {normalized_category})

    if category_indoor and not category_outdoor:
        return PlaceEnvironment.INDOOR
    if category_outdoor and not category_indoor:
        return PlaceEnvironment.OUTDOOR

    # Explicit indoor indicators take precedence for shelters (e.g. "Albert Hall Museum")
    has_indoor = any(token in INDOOR_TOKENS or any(it in token for it in INDOOR_TOKENS) for token in all_tokens)
    has_outdoor = any(token in OUTDOOR_TOKENS or any(ot in token for ot in OUTDOOR_TOKENS) for token in all_tokens)
    has_dual = any(token in DUAL_TOKENS or any(dt in token for dt in DUAL_TOKENS) for token in all_tokens)

    if has_indoor and not has_outdoor:
        return PlaceEnvironment.INDOOR
    if has_outdoor and not has_indoor:
        return PlaceEnvironment.OUTDOOR
    if has_indoor and has_outdoor:
        # If it has both (e.g. "Museum at Fort"), treat as dual
        return PlaceEnvironment.DUAL
    if has_dual:
        return PlaceEnvironment.DUAL

    return PlaceEnvironment.UNKNOWN


def is_outdoor_exposed(
    category: str,
    tags: list[str] | None = None,
    name: str | None = None,
) -> bool:
    """Check if a place has substantial outdoor exposure vulnerable to heat/rain/storm."""
    env = classify_place(category, tags, name)
    # Both outdoor and dual venues are affected by extreme heat, heavy rain, and storms
    return env in (PlaceEnvironment.OUTDOOR, PlaceEnvironment.DUAL, PlaceEnvironment.UNKNOWN)


def is_indoor_sheltered(
    category: str,
    tags: list[str] | None = None,
    name: str | None = None,
) -> bool:
    """Check if a place provides a reliable sheltered indoor experience."""
    env = classify_place(category, tags, name)
    return env == PlaceEnvironment.INDOOR
