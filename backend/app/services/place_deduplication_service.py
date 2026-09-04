"""Multi-stage canonical and spatial deduplication for place recommendations.

Resolves duplicate records from multiple categories, provider extracts,
and spatial node/way duplicates while preserving distinct branches of the same chain.
"""

from dataclasses import dataclass
from math import asin, cos, radians, sin, sqrt
import re
from typing import Final
from uuid import UUID

from app.models.entities import Place, PlaceSource

# Proximity threshold in meters to consider two similarly named places as the same physical venue.
SPATIAL_DEDUPE_DISTANCE_METERS: Final[float] = 75.0

# Noise tokens to strip during fuzzy name normalization
_NOISE_TOKENS: Final[set[str]] = {
    "restaurant",
    "cafe",
    "coffee",
    "dhaba",
    "hotel",
    "food",
    "court",
    "the",
    "and",
    "&",
    "bar",
    "bistro",
    "shree",
    "shri",
}


def haversine_distance_meters(
    lat1: float,
    lon1: float,
    lat2: float,
    lon2: float,
) -> float:
    """Return distance between two points in meters using Haversine formula."""
    r = 6371000.0  # Earth radius in meters
    phi1, phi2 = radians(lat1), radians(lat2)
    dphi = radians(lat2 - lat1)
    dlambda = radians(lon2 - lon1)

    a = sin(dphi / 2.0) ** 2 + cos(phi1) * cos(phi2) * sin(dlambda / 2.0) ** 2
    c = 2.0 * asin(min(1.0, sqrt(a)))
    return r * c


def normalize_name_for_dedupe(name: str) -> str:
    """Normalize venue name for canonical comparison."""
    clean = re.sub(r"[^\w\s]", " ", name.casefold())
    tokens = [t for t in clean.split() if t and t not in _NOISE_TOKENS]
    return " ".join(tokens) if tokens else clean.strip()


def _levenshtein_distance(s1: str, s2: str) -> int:
    """Calculate Levenshtein distance between two strings."""
    if len(s1) < len(s2):
        return _levenshtein_distance(s2, s1)
    if not s2:
        return len(s1)
    prev = list(range(len(s2) + 1))
    for i, c1 in enumerate(s1):
        curr = [i + 1] * (len(s2) + 1)
        for j, c2 in enumerate(s2):
            insertions = prev[j + 1] + 1
            deletions = curr[j] + 1
            substitutions = prev[j] + (c1 != c2)
            curr[j + 1] = min(insertions, deletions, substitutions)
        prev = curr
    return prev[-1]


def are_names_similar(name1: str, name2: str) -> bool:
    """Check if two names refer to the same venue."""
    n1 = normalize_name_for_dedupe(name1)
    n2 = normalize_name_for_dedupe(name2)
    if not n1 or not n2:
        return False
    if n1 == n2:
        return True
    if n1 in n2 or n2 in n1:
        return True

    tokens1 = set(n1.split())
    tokens2 = set(n2.split())
    intersection = tokens1 & tokens2
    if len(intersection) >= min(len(tokens1), len(tokens2)) and len(intersection) >= 2:
        return True

    # Fuzzy token matching for transliteration variations (e.g. Jaigarh vs Jaighar)
    matched_count = 0
    remaining_t2 = set(tokens2)
    for t1 in tokens1:
        if t1 in remaining_t2:
            matched_count += 1
            remaining_t2.remove(t1)
        else:
            cand_t2 = next(
                (
                    t2
                    for t2 in remaining_t2
                    if len(t1) >= 6
                    and len(t2) >= 6
                    and _levenshtein_distance(t1, t2) <= 2
                ),
                None,
            )
            if cand_t2 is not None:
                matched_count += 1
                remaining_t2.remove(cand_t2)

    if matched_count >= min(len(tokens1), len(tokens2)) and matched_count >= 2:
        return True

    return False


@dataclass
class DeduplicationCluster:
    canonical_place: Place
    sources: list[PlaceSource]
    all_place_ids: set[UUID]


def deduplicate_places(
    places: list[Place],
    place_sources: list[PlaceSource] | None = None,
    distance_threshold_meters: float = SPATIAL_DEDUPE_DISTANCE_METERS,
) -> list[Place]:
    """Deduplicate candidate places using ID, provider source, and spatial proximity."""
    if not places:
        return []

    # Map sources by place_id
    sources_by_place_id: dict[UUID, list[PlaceSource]] = {}
    if place_sources:
        for s in place_sources:
            sources_by_place_id.setdefault(s.place_id, []).append(s)

    clusters: list[DeduplicationCluster] = []
    seen_place_ids: set[UUID] = set()

    for place in places:
        if place.id in seen_place_ids:
            continue

        place_srcs = sources_by_place_id.get(place.id, [])
        place_ext_keys = {f"{s.source}:{s.external_place_id}" for s in place_srcs if s.external_place_id}

        matched_cluster: DeduplicationCluster | None = None

        # Check existing clusters
        for cluster in clusters:
            # 1. Exact Place.id
            if place.id in cluster.all_place_ids:
                matched_cluster = cluster
                break

            # 2. Shared external provider identity
            cluster_ext_keys = {
                f"{s.source}:{s.external_place_id}"
                for s in cluster.sources
                if s.external_place_id
            }
            if place_ext_keys and (place_ext_keys & cluster_ext_keys):
                matched_cluster = cluster
                break

            # 3. Spatial + Name similarity
            dist = haversine_distance_meters(
                place.latitude,
                place.longitude,
                cluster.canonical_place.latitude,
                cluster.canonical_place.longitude,
            )
            if dist <= distance_threshold_meters:
                if are_names_similar(place.name, cluster.canonical_place.name):
                    matched_cluster = cluster
                    break

        if matched_cluster is not None:
            matched_cluster.all_place_ids.add(place.id)
            matched_cluster.sources.extend(place_srcs)
            # Prefer place with more data / reviews as canonical representative
            if (place.review_count or 0) > (matched_cluster.canonical_place.review_count or 0):
                matched_cluster.canonical_place = place
            elif (place.rating or 0) > (matched_cluster.canonical_place.rating or 0):
                matched_cluster.canonical_place = place
        else:
            clusters.append(
                DeduplicationCluster(
                    canonical_place=place,
                    sources=list(place_srcs),
                    all_place_ids={place.id},
                )
            )
        seen_place_ids.add(place.id)

    return [c.canonical_place for c in clusters]
