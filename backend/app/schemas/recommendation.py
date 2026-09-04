"""Validation schemas for multi-category place recommendations."""

from enum import Enum
from uuid import UUID

from pydantic import field_validator
from sqlmodel import Field, SQLModel


class DiscoveryCategory(str, Enum):
    RELIGIOUS = "religious"
    FOOD = "food"
    TOURISM = "tourism"
    CAFES = "cafes"
    HERITAGE = "heritage"
    MARKETS = "markets"
    NATURE = "nature"


class RecommendationRequest(SQLModel):
    categories: list[DiscoveryCategory] = Field(min_length=1, max_length=5)
    limit: int = Field(default=30, ge=1, le=100)
    trip_id: UUID | None = None
    purposes: list[str] | None = None
    interests: list[str] | None = None
    category_filter: DiscoveryCategory | None = None

    @field_validator("categories")
    @classmethod
    def remove_duplicate_categories(
        cls,
        categories: list[DiscoveryCategory],
    ) -> list[DiscoveryCategory]:
        return list(dict.fromkeys(categories))


class RecommendationRead(SQLModel):
    id: UUID
    name: str
    category: str
    latitude: float
    longitude: float
    rating: float | None
    review_count: int
    is_popular: bool
    is_heritage: bool
    is_local_speciality: bool
    matched_categories: list[DiscoveryCategory]
    recommendation_score: float
    recommendation_reason: str | None = None
    access_confidence: str = "PUBLIC_LIKELY"
    is_saved: bool = False
