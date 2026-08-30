"""Validation schemas for city endpoints."""

from datetime import datetime
from uuid import UUID

from pydantic import field_validator
from sqlmodel import Field, SQLModel


class CityBase(SQLModel):
    name: str = Field(min_length=1, max_length=120)
    state: str | None = Field(default=None, max_length=120)
    country: str = Field(min_length=1, max_length=120)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    google_place_id: str | None = Field(default=None, max_length=255)

    @field_validator("name", "country")
    @classmethod
    def strip_required_text(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("must not be blank")
        return value

    @field_validator("state", "google_place_id")
    @classmethod
    def strip_optional_text(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        return value or None


class CityCreate(CityBase):
    """Fields accepted when creating a city."""


class CityResolve(CityBase):
    """Google city details accepted by the resolve endpoint."""

    google_place_id: str = Field(min_length=1, max_length=255)

    @field_validator("google_place_id")
    @classmethod
    def require_google_place_id(cls, value: str | None) -> str:
        if value is None or not value.strip():
            raise ValueError("must not be blank")
        return value.strip()


class CityRead(CityBase):
    """Public city representation returned by the API."""

    id: UUID
    created_at: datetime
