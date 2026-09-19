"""Provider-neutral types for place image resolution."""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from uuid import UUID

from app.services.place_category_normalizer import NormalizedPlaceCategory


@dataclass(frozen=True)
class PlaceImageSourceContext:
    source: str
    external_place_id: str
    source_url: str | None = None
    locality: str | None = None
    region: str | None = None
    country_code: str | None = None
    identifiers: dict[str, str] = field(default_factory=dict)


@dataclass(frozen=True)
class PlaceImageContext:
    place_id: UUID
    name: str
    raw_category: str
    normalized_category: NormalizedPlaceCategory
    latitude: float
    longitude: float
    city: str
    state: str | None
    country: str
    wikidata_id: str | None
    sources: tuple[PlaceImageSourceContext, ...] = ()


@dataclass(frozen=True)
class PlaceImageCandidate:
    url: str
    thumbnail_url: str | None
    provider: str
    provider_place_id: str | None
    source_url: str | None
    attribution: str | None
    author: str | None
    license: str | None
    license_url: str | None


def first_identifier(context: PlaceImageContext, key: str) -> str | None:
    for source in context.sources:
        value = source.identifiers.get(key)
        if value:
            return value
    return None


def source_for(
    context: PlaceImageContext, provider: str
) -> PlaceImageSourceContext | None:
    return next(
        (source for source in context.sources if source.source == provider), None
    )


def place_image_identity_key(context: PlaceImageContext) -> str:
    """Return a deterministic POI-specific identity for diagnostics/provider work.

    The durable database cache remains keyed by the canonical ``Place.id``. This
    provider-aware key makes the underlying identity explicit and gives places
    without provider provenance a stable, collision-resistant fallback.
    """

    identified_sources = sorted(
        (
            source.source.strip().casefold(),
            source.external_place_id.strip(),
        )
        for source in context.sources
        if source.source.strip() and source.external_place_id.strip()
    )
    if identified_sources:
        source, external_place_id = identified_sources[0]
        return f"provider:{source}:{external_place_id}"

    normalized_name = re.sub(r"[^a-z0-9]+", "-", context.name.casefold()).strip("-")
    normalized_city = re.sub(r"[^a-z0-9]+", "-", context.city.casefold()).strip("-")
    return (
        f"place:{normalized_name}:{normalized_city}:"
        f"{context.latitude:.5f}:{context.longitude:.5f}"
    )


def place_image_search_query(context: PlaceImageContext) -> str:
    """Build the exact contextual search phrase shared by search providers."""

    return ", ".join(
        part.strip()
        for part in (context.name, context.city, context.state, context.country)
        if part and part.strip()
    )
