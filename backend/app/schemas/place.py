"""Validation schemas for place endpoints."""

from datetime import datetime
from uuid import UUID

from pydantic import field_validator
from sqlmodel import Field, SQLModel


class PlaceBase(SQLModel):
    name: str = Field(min_length=1, max_length=200)
    category: str = Field(min_length=1, max_length=80)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    rating: float | None = Field(default=None, ge=0, le=5)
    review_count: int = Field(default=0, ge=0)
    is_popular: bool = False
    is_heritage: bool = False
    is_local_speciality: bool = False
    wikidata_id: str | None = None
    importance_score: float | None = Field(default=None, ge=0, le=1)
    last_fetched_at: datetime | None = None

    @field_validator("name", "category")
    @classmethod
    def strip_required_text(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("must not be blank")
        return value


class PlaceCreate(PlaceBase):
    """Fields accepted when creating a place."""

    city_id: UUID


class PlaceRead(PlaceBase):
    """Public place representation returned by the API."""

    id: UUID
    city_id: UUID
    created_at: datetime


class GoogleNearbyPlace(SQLModel):
    """Normalized Google place data used only inside the backend."""

    google_place_id: str = Field(min_length=1, max_length=255)
    name: str = Field(min_length=1, max_length=200)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    rating: float | None = Field(default=None, ge=0, le=5)
    review_count: int = Field(default=0, ge=0)
    primary_type: str | None = None
    types: list[str] = Field(default_factory=list)


class PlacePrefetchRequest(SQLModel):
    city_id: UUID
    stage: str = "destination_confirmed"
    categories: list[str] | None = None


class PlacePrefetchResponse(SQLModel):
    city_id: UUID
    city_name: str
    stage: str
    categories_requested: list[str]
    categories_skipped_sufficient: list[str]
    categories_enriched: list[str]
    duplicate_refreshes_prevented: int
