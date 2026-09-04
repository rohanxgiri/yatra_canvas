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
# Matches e.g. "College Canteen", "Hostel Mess", "Staff Dining", "Employee Cafeteria", "Officers Mess", "Campus Food Court"
_INSTITUTIONAL_NAME_PATTERNS: Final[tuple[re.Pattern[str], ...]] = (
    re.compile(r"\b(canteen|mess|cafeteria|dining\s+hall)\b", re.IGNORECASE),
    re.compile(r"\b(staff|employee|faculty|student|officers?|hostel)\s+(dining|canteen|mess|lunch|food|cafe)\b", re.IGNORECASE),
    re.compile(
        r"\b(campus|college|school|university|institute|academy|hospital|office|cantonment|hostel|faculty)\s+(canteen|cafeteria|mess|dining|food\s+(court|corner|point|hub|plaza))\b",
        re.IGNORECASE,
    ),
    re.compile(r"\b(residential|internal)\s+(canteen|cafeteria|mess|dining)\b", re.IGNORECASE),
    # Academic/research institute acronyms paired with dining/mess/food court/point
    re.compile(
        r"\b(iit|nit|iim|aiims|iisc|iiit|isro|drdo)\b.*\b(canteen|mess|cafeteria|dining|food\s+(court|corner|point|hub|plaza)|hostel)\b",
        re.IGNORECASE,
    ),
)

# Operators that indicate an educational, healthcare, military, or institutional facility
_INSTITUTIONAL_OPERATOR_PATTERNS: Final[tuple[re.Pattern[str], ...]] = (
    re.compile(r"\b(university|college|institute|polytechnic|academy|vidyapith|campus|hostel|dormitory)\b", re.IGNORECASE),
    re.compile(r"\b(hospital|medical\s+college|nursing\s+home|clinic|healthcare|dispensary)\b", re.IGNORECASE),
    re.compile(r"\b(police|armed\s+forces|military|cantonment|army|navy|air\s+force|secretariat|ministry|railway\s+colony)\b", re.IGNORECASE),
    re.compile(r"\b(iit|nit|iim|aiims|iisc|iiit|bits|isro|drdo|ongc|bhel|sail)\b", re.IGNORECASE),
)

# Building types that indicate internal/restricted premises
_INSTITUTIONAL_BUILDINGS: Final[set[str]] = {
    "university",
    "college",
    "school",
    "dormitory",
    "hostel",
    "hospital",
    "barracks",
    "military",
    "office",
}

# Non-tourist commercial, financial, or administrative facilities that are not visitor attractions
# (e.g. retail bank branches, ATMs, corporate offices entering via open datasets)
_NON_TOURIST_FACILITY_PATTERNS: Final[tuple[re.Pattern[str], ...]] = (
    re.compile(r"\b(bank(\s+branch)?|atm|branch\s+office|regional\s+office|head\s+office|corporate\s+office|zonal\s+office|substation|customer\s+care|insurance\s+office)\b", re.IGNORECASE),
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
    """Classify access confidence based on tags, operator, building context, and name patterns."""
    raw_tags: dict[str, str] = {}
    tag_set: set[str] = set()
    if isinstance(tags, dict):
        raw_tags = {k.casefold(): v.casefold() for k, v in tags.items()}
        tag_set = {f"{k}={v}" for k, v in raw_tags.items()} | set(raw_tags.keys()) | set(raw_tags.values())
    elif isinstance(tags, set):
        tag_set = {t.casefold() for t in tags}
        # Parse key=value strings into raw_tags dictionary
        for t in tag_set:
            if "=" in t:
                k, v = t.split("=", 1)
                raw_tags[k.strip()] = v.strip()

    # 1. Check explicit access tag
    access_val = raw_tags.get("access")
    if access_val in _RESTRICTED_ACCESS_VALUES:
        return AccessConfidence.RESTRICTED
    if access_val in _PUBLIC_ACCESS_VALUES:
        return AccessConfidence.PUBLIC_LIKELY

    # 2. Check non-tourist commercial/financial facilities (e.g. retail bank branches)
    # Museum and heritage places are exempt (e.g. RBI Museum)
    cat_lower = category.casefold()
    clean_name = name.strip()
    is_museum_or_heritage = cat_lower in ("museum", "heritage") or "museum" in clean_name.casefold()
    if not is_museum_or_heritage:
        for non_tourist_pattern in _NON_TOURIST_FACILITY_PATTERNS:
            if non_tourist_pattern.search(clean_name):
                return AccessConfidence.RESTRICTED_LIKELY

    # 3. Check explicit restricted amenity / tags
    amenity_val = raw_tags.get("amenity")
    if amenity_val in _RESTRICTED_AMENITIES or "amenity=canteen" in tag_set or "canteen" in tag_set:
        if access_val not in _PUBLIC_ACCESS_VALUES:
            return AccessConfidence.RESTRICTED_LIKELY

    # 4. Check operator context for institutional ownership
    operator_val = raw_tags.get("operator", "")
    if operator_val:
        for op_pattern in _INSTITUTIONAL_OPERATOR_PATTERNS:
            if op_pattern.search(operator_val):
                if access_val not in _PUBLIC_ACCESS_VALUES:
                    return AccessConfidence.RESTRICTED_LIKELY

    # 5. Check building context for institutional premises (e.g. university/college/hospital/dormitory)
    building_val = raw_tags.get("building", "")
    if building_val in _INSTITUTIONAL_BUILDINGS:
        # Food amenities inside institutional buildings are internal unless explicitly public
        if cat_lower in ("food", "cafes") or amenity_val in ("fast_food", "food_court", "restaurant", "cafe"):
            if access_val not in _PUBLIC_ACCESS_VALUES:
                return AccessConfidence.RESTRICTED_LIKELY

    # 6. Check general institutional patterns in name
    for pattern in _INSTITUTIONAL_NAME_PATTERNS:
        if pattern.search(clean_name):
            return AccessConfidence.RESTRICTED_LIKELY

    # 7. If category is known public and no restriction flags exist
    if cat_lower in _PUBLIC_CATEGORIES:
        return AccessConfidence.PUBLIC_LIKELY

    # 8. Default conservative fallback
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
