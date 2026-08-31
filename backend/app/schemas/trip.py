"""Trip creation and start-location schemas."""

from datetime import date, datetime
from enum import Enum
from uuid import UUID

from pydantic import ConfigDict, field_validator, model_validator
from sqlmodel import Field, SQLModel


class StartLocationType(str, Enum):
    arrival = "arrival"
    hotel = "hotel"
    current_location = "current_location"
    custom = "custom"


class TripCreate(SQLModel):
    """Application-owned trip creation request; identity is server-derived."""

    model_config = ConfigDict(extra="forbid")

    city_id: UUID
    trip_name: str | None = Field(default=None, max_length=160)
    start_date: date
    end_date: date
    days: int = Field(ge=1)
    arrival_place: str = Field(min_length=1, max_length=255)
    arrival_latitude: float | None = Field(default=None, ge=-90, le=90)
    arrival_longitude: float | None = Field(default=None, ge=-180, le=180)
    start_location_type: StartLocationType | None = None
    start_location_name: str | None = Field(default=None, max_length=255)
    start_latitude: float | None = Field(default=None, ge=-90, le=90)
    start_longitude: float | None = Field(default=None, ge=-180, le=180)
    start_location_provider: str | None = Field(default=None, max_length=50)
    start_location_provider_place_id: str | None = Field(default=None, max_length=500)
    purposes: list[str] = Field(min_length=1)
    preferences: list[str] = Field(min_length=1)

    @field_validator(
        "trip_name",
        "start_location_name",
        "start_location_provider",
        "start_location_provider_place_id",
    )
    @classmethod
    def normalize_optional_text(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip()
        return normalized or None

    @field_validator("arrival_place")
    @classmethod
    def normalize_arrival_place(cls, value: str) -> str:
        normalized = value.strip()
        if not normalized:
            raise ValueError("Arrival place must not be blank.")
        return normalized

    @field_validator("purposes", "preferences")
    @classmethod
    def normalize_preferences(cls, values: list[str]) -> list[str]:
        normalized: list[str] = []
        seen: set[str] = set()
        for value in values:
            item = value.strip()
            if not item:
                raise ValueError("Trip preferences must not be blank.")
            if len(item) > 80:
                raise ValueError("Trip preferences cannot exceed 80 characters.")
            key = item.casefold()
            if key not in seen:
                seen.add(key)
                normalized.append(item)
        return normalized

    @model_validator(mode="after")
    def validate_trip(self) -> "TripCreate":
        if self.end_date < self.start_date:
            raise ValueError("End date cannot be before start date.")
        expected_days = (self.end_date - self.start_date).days + 1
        if self.days != expected_days:
            raise ValueError("Days must match the inclusive trip date range.")
        self._validate_coordinate_pair(
            self.arrival_latitude,
            self.arrival_longitude,
            "Arrival",
        )
        self._validate_coordinate_pair(
            self.start_latitude,
            self.start_longitude,
            "Start location",
        )
        if (self.start_location_provider is None) != (
            self.start_location_provider_place_id is None
        ):
            raise ValueError(
                "Location provider and provider place ID must be supplied together."
            )
        if self.start_location_type not in (None, StartLocationType.arrival):
            if self.start_location_name is None:
                raise ValueError("The selected start location requires a name.")
            if self.start_latitude is None:
                raise ValueError("The selected start location requires coordinates.")
        return self

    @staticmethod
    def _validate_coordinate_pair(
        latitude: float | None,
        longitude: float | None,
        label: str,
    ) -> None:
        if (latitude is None) != (longitude is None):
            raise ValueError(f"{label} latitude and longitude must be supplied together.")


class TripRead(SQLModel):
    trip_id: UUID
    city_id: UUID
    trip_name: str
    days: int
    start_date: date
    arrival_place: str
    arrival_latitude: float | None = None
    arrival_longitude: float | None = None
    start_location_type: StartLocationType | None = None
    start_location_name: str | None = None
    start_latitude: float | None = None
    start_longitude: float | None = None
    start_location_provider: str | None = None
    start_location_provider_place_id: str | None = None
    preferences: list[str]
    created_at: datetime | None = None


class TripStartLocationUpdate(SQLModel):
    start_location_type: StartLocationType
    start_location_name: str | None = Field(default=None, max_length=255)
    start_latitude: float | None = Field(default=None, ge=-90, le=90)
    start_longitude: float | None = Field(default=None, ge=-180, le=180)
    start_location_provider: str | None = Field(default=None, max_length=50)
    start_location_provider_place_id: str | None = Field(default=None, max_length=500)

    @model_validator(mode="after")
    def validate_location(self) -> "TripStartLocationUpdate":
        if self.start_location_type == StartLocationType.arrival:
            return self
        if self.start_latitude is None or self.start_longitude is None:
            raise ValueError("The selected start location requires coordinates.")
        if not self.start_location_name or not self.start_location_name.strip():
            raise ValueError("The selected start location requires a name.")
        self.start_location_name = self.start_location_name.strip()
        if (self.start_location_provider is None) != (
            self.start_location_provider_place_id is None
        ):
            raise ValueError(
                "Location provider and provider place ID must be supplied together."
            )
        if self.start_location_provider is not None:
            self.start_location_provider = self.start_location_provider.strip()
            self.start_location_provider_place_id = (
                self.start_location_provider_place_id or ""
            ).strip()
            if (
                not self.start_location_provider
                or not self.start_location_provider_place_id
            ):
                raise ValueError("Location provider identifiers must not be blank.")
        return self


class TripStartLocationRead(SQLModel):
    trip_id: UUID
    start_location_type: StartLocationType
    start_location_name: str
    start_latitude: float
    start_longitude: float
    start_location_provider: str | None = None
    start_location_provider_place_id: str | None = None


class LocationSuggestion(SQLModel):
    google_place_id: str
    name: str
    description: str


class LocationDetails(SQLModel):
    google_place_id: str
    name: str
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
