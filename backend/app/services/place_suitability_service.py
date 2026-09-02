"""Traveller suitability and access confidence evaluation for place recommendations.

Determines whether places are genuinely public-facing and useful for travellers
versus internal, institutional, restricted, or private facilities.
Does NOT blacklist specific entity names (e.g. no hardcoded 'SVNIT').
Uses general context signals, access tags, and institutional patterns.
"""

from enum import Enum
import re
from typing import Final


class AccessConfidence(str, Enum):
    PUBLIC_LIKELY = "PUBLIC_LIKELY"
    UNKNOWN = "UNKNOWN"
    RESTRICTED_LIKELY = "RESTRICTED_LIKELY"
    RESTRICTED = "RESTRICTED"


# Explicit restriction access tag values in OSM / POI data
_RESTRICTED_ACCESS_VALUES: Final[set[str]] = {
    "private",
    "no",
    "permit",
    "students",
    "employees",
    "members",
    "resident",
    "residents",
}

# Explicit public access tag values in OSM / POI data
_PUBLIC_ACCESS_VALUES: Final[set[str]] = {
    "yes",
    "public",
    "permissive",
}

# General patterns indicating internal/institutional facilities
# Matches e.g. "College Canteen", "Hostel Mess", "Staff Dining", "Employee Cafeteria", "Officers Mess"
_INSTITUTIONAL_NAME_PATTERNS: Final[tuple[re.Pattern[str], ...]] = (
    re.compile(r"\b(canteen|mess|cafeteria|dining\s+hall)\b", re.IGNORECASE),
    re.compile(r"\b(staff|employee|faculty|student|officers?|hostel)\s+(dining|canteen|mess|lunch)\b", re.IGNORECASE),
    re.compile(r"\b(campus|college|school|university|institute|academy|hospital|office)\s+(canteen|cafeteria|mess)\b", re.IGNORECASE),
    re.compile(r"\b(residential|internal)\s+(canteen|cafeteria)\b", re.IGNORECASE),
)

# Categories or amenities that are inherently internal/restricted unless proven otherwise
_RESTRICTED_AMENITIES: Final[set[str]] = {
    "canteen",
    "student_hall",
    "dormitory",
}

# Category types that are typically public-facing
_PUBLIC_CATEGORIES: Final[set[str]] = {
    "food",
    "cafes",
    "tourism",
    "restaurant",
    "cafe",
    "fast_food",
    "food_court",
    "bakery",
    "museum",
    "art_gallery",
    "theme_park",
    "zoo",
    "viewpoint",
    "park",
    "place_of_worship",
    "temple",
    "monument",
    "historic",
    "heritage",
}


def evaluate_access_confidence(
    *,
    name: str,
    category: str,
    tags: dict[str, str] | set[str] | None = None,
) -> AccessConfidence:
    """Classify access confidence based on tags, name patterns, and categories."""
    raw_tags: dict[str, str] = {}
    tag_set: set[str] = set()
    if isinstance(tags, dict):
        raw_tags = {k.casefold(): v.casefold() for k, v in tags.items()}
        tag_set = {f"{k}={v}" for k, v in raw_tags.items()} | set(raw_tags.keys()) | set(raw_tags.values())
    elif isinstance(tags, set):
        tag_set = {t.casefold() for t in tags}

    # 1. Check explicit access tag
    access_val = raw_tags.get("access")
    if access_val in _RESTRICTED_ACCESS_VALUES:
        return AccessConfidence.RESTRICTED
    if access_val in _PUBLIC_ACCESS_VALUES:
        return AccessConfidence.PUBLIC_LIKELY

    # 2. Check explicit restricted amenity / tags
    amenity_val = raw_tags.get("amenity")
    if amenity_val in _RESTRICTED_AMENITIES or "amenity=canteen" in tag_set or "canteen" in tag_set:
        # Check if explicitly public despite being a canteen
        if access_val not in _PUBLIC_ACCESS_VALUES:
            return AccessConfidence.RESTRICTED_LIKELY

    # 3. Check general institutional patterns in name
    clean_name = name.strip()
    for pattern in _INSTITUTIONAL_NAME_PATTERNS:
        if pattern.search(clean_name):
            # If explicit public access tag was present, we already returned PUBLIC_LIKELY above.
            return AccessConfidence.RESTRICTED_LIKELY

    # 4. If category is known public and no restriction flags exist
    cat_lower = category.casefold()
    if cat_lower in _PUBLIC_CATEGORIES:
        return AccessConfidence.PUBLIC_LIKELY

    # 5. Default conservative fallback
    return AccessConfidence.UNKNOWN


def is_traveller_suitable(
    *,
    name: str,
    category: str,
    tags: dict[str, str] | set[str] | None = None,
) -> tuple[bool, AccessConfidence]:
    """Return whether a place is suitable for normal public travellers."""
    confidence = evaluate_access_confidence(
        name=name,
        category=category,
        tags=tags,
    )
    # RESTRICTED and RESTRICTED_LIKELY are not suitable for general tourist discovery
    suitable = confidence in (AccessConfidence.PUBLIC_LIKELY, AccessConfidence.UNKNOWN)
    return suitable, confidence
