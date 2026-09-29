"""Validation schemas for city endpoints."""

from datetime import datetime
from uuid import UUID

from pydantic import field_validator, model_validator
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
        value = " ".join(value.split()).strip(" ,")
        if not value:
            raise ValueError("must not be blank")
        return value

    @field_validator("state", "google_place_id")
    @classmethod
    def strip_optional_text(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = " ".join(value.split()).strip(" ,")
        return value or None


class CityCreate(CityBase):
    """Fields accepted when creating a city."""


class CityResolve(CityBase):
    """Normalized provider city accepted by the resolve endpoint."""

    provider_place_id: str | None = Field(default=None, max_length=255)
    provider_name: str | None = Field(default="geoapify", max_length=50)

    @field_validator("provider_place_id", "provider_name")
    @classmethod
    def strip_provider_identity(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        return value or None

    @model_validator(mode="after")
    def remove_redundant_state_suffix(self) -> "CityResolve":
        if not self.state:
            return self
        name_words = self.name.casefold().replace(",", " ").split()
        state_words = self.state.casefold().split()
        if (
            len(name_words) > len(state_words)
            and name_words[-len(state_words) :] == state_words
        ):
            kept = self.name.replace(",", " ").split()[: -len(state_words)]
            normalized_name = " ".join(kept).strip(" ,")
            if normalized_name:
                self.name = normalized_name
        return self


class CitySuggestion(SQLModel):
    """Normalized provider city prediction returned to Flutter."""

    provider_place_id: str
    name: str
    description: str


class CityDetails(CityResolve):
    """Normalized provider place details response used by city resolution."""


class CityRead(CityBase):
    """Public city representation returned by the API."""

    id: UUID
    created_at: datetime
