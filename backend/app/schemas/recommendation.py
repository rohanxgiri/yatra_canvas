"""Validation schemas for multi-category place recommendations."""

from base64 import urlsafe_b64decode
from binascii import Error as BinasciiError

from enum import Enum
from uuid import UUID

from pydantic import field_validator
from sqlmodel import Field, SQLModel

from app.schemas.place_image import PlaceImageRead


class DiscoveryCategory(str, Enum):
    RELIGIOUS = "religious"
    FOOD = "food"
    TOURISM = "tourism"
    CAFES = "cafes"
    HERITAGE = "heritage"
    MARKETS = "markets"
    NATURE = "nature"


class RecommendationRequest(SQLModel):
    categories: list[DiscoveryCategory] = Field(min_length=1, max_length=7)
    limit: int = Field(default=30, ge=1, le=100)
    trip_id: UUID | None = None
    purposes: list[str] | None = None
    interests: list[str] | None = None
    category_filter: DiscoveryCategory | None = None
    cursor: str | None = Field(default=None, max_length=32)

    @field_validator("categories")
    @classmethod
    def remove_duplicate_categories(
        cls,
        categories: list[DiscoveryCategory],
    ) -> list[DiscoveryCategory]:
        return list(dict.fromkeys(categories))

    @field_validator("cursor")
    @classmethod
    def validate_cursor(cls, cursor: str | None) -> str | None:
        if cursor is None:
            return None
        try:
            decoded = urlsafe_b64decode(cursor.encode("ascii")).decode("ascii")
            if int(decoded) < 0:
                raise ValueError
        except (BinasciiError, UnicodeError, ValueError) as exc:
            raise ValueError("cursor is invalid") from exc
        return cursor

    @property
    def cursor_offset(self) -> int:
        if self.cursor is None:
            return 0
        return int(urlsafe_b64decode(self.cursor.encode("ascii")).decode("ascii"))


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
    normalized_category: str = "other"
    image: PlaceImageRead | None = None
