"""Provider-neutral types for place image resolution."""

from __future__ import annotations

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


def source_for(context: PlaceImageContext, provider: str) -> PlaceImageSourceContext | None:
    return next((source for source in context.sources if source.source == provider), None)
