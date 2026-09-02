"""Centralized itinerary planning constants, daily windows, and visit duration heuristics.

These heuristics represent product planning estimates derived from taxonomy/category,
not factual opening hours or official provider visit claims.
"""

from datetime import time
from typing import Final

# --- Daily Planning Touring Windows ---
DEFAULT_DAY_START_TIME: Final[time] = time(9, 0)   # 09:00 AM
DEFAULT_DAY_END_TIME: Final[time] = time(19, 0)     # 07:00 PM
DEFAULT_DAILY_BUDGET_MINUTES: Final[int] = 600       # 10 hours max touring window

# --- Midday / Lunch Break Settings ---
LUNCH_BREAK_EARLIEST_START: Final[time] = time(12, 30)  # 12:30 PM
LUNCH_BREAK_LATEST_START: Final[time] = time(14, 0)     # 02:00 PM
DEFAULT_LUNCH_BREAK_MINUTES: Final[int] = 60            # 1 hour break

# --- Travel & Transition Buffer ---
# Minimum travel buffer between consecutive stops to account for disembarkation/parking
MIN_TRAVEL_BUFFER_MINUTES: Final[int] = 5

# --- Category-Based Visit Duration Heuristics (in minutes) ---
# Heuristics derived from general tourism guidelines for tourist satisfaction:
CATEGORY_VISIT_DURATIONS_MINUTES: Final[dict[str, int]] = {
    # Major heritage & architectural sites: ~2 hours
    "fort": 120,
    "palace": 120,
    "heritage": 120,
    "ruins": 90,
    "zoo": 120,
    "theme_park": 180,

    # Cultural & educational exhibits: ~1.5 hours
    "museum": 90,
    "art_gallery": 90,
    "gallery": 75,
    "cultural_centre": 90,
    "cultural_center": 90,

    # Shopping & commercial centers: ~1.5 hours
    "mall": 90,
    "shopping_mall": 90,
    "market": 75,
    "bazaar": 75,

    # Leisure & outdoor nature spaces: ~1 hour
    "park": 60,
    "garden": 60,
    "viewpoint": 45,
    "nature": 60,
    "nature_reserve": 90,
    "lake": 60,
    "beach": 90,
    "promenade": 45,

    # Quick monuments, stepwells & memorials: ~45 minutes
    "monument": 45,
    "historic": 45,
    "stepwell": 45,
    "ghat": 45,
    "waterfall": 60,
    "sightseeing": 60,

    # Places of worship: ~45 minutes
    "religious": 45,
    "temple": 45,
    "mosque": 45,
    "church": 45,
    "ashram": 60,
    "monastery": 60,

    # Dining & food stops: ~45 minutes
    "food": 45,
    "restaurant": 45,
    "cafe": 45,
    "cafes": 45,
    "bakery": 30,

    # General sightseeing fallback
    "tourism": 60,
}

# Fallback visit duration when category is unmapped
DEFAULT_FALLBACK_VISIT_DURATION_MINUTES: Final[int] = 75


def estimate_visit_duration(category: str, tags: list[str] | None = None) -> int:
    """Return a deterministic estimated visit duration in minutes based on category and tags."""
    cat_lower = (category or "").lower().strip()
    if cat_lower in CATEGORY_VISIT_DURATIONS_MINUTES:
        return CATEGORY_VISIT_DURATIONS_MINUTES[cat_lower]

    for tag in tags or []:
        tag_lower = tag.lower().strip()
        if tag_lower in CATEGORY_VISIT_DURATIONS_MINUTES:
            return CATEGORY_VISIT_DURATIONS_MINUTES[tag_lower]

    # Keyword matching
    for key, duration in CATEGORY_VISIT_DURATIONS_MINUTES.items():
        if key in cat_lower:
            return duration

    return DEFAULT_FALLBACK_VISIT_DURATION_MINUTES
