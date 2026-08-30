"""Trip start-location schemas."""

from enum import Enum
from uuid import UUID

from pydantic import model_validator
from sqlmodel import Field, SQLModel


class StartLocationType(str, Enum):
    arrival = "arrival"
    hotel = "hotel"
    current_location = "current_location"
    custom = "custom"


class TripStartLocationUpdate(SQLModel):
    start_location_type: StartLocationType
    start_location_name: str | None = Field(default=None, max_length=255)
    start_latitude: float | None = Field(default=None, ge=-90, le=90)
    start_longitude: float | None = Field(default=None, ge=-180, le=180)

    @model_validator(mode="after")
    def validate_location(self) -> "TripStartLocationUpdate":
        if self.start_location_type == StartLocationType.arrival:
            return self
        if self.start_latitude is None or self.start_longitude is None:
            raise ValueError("The selected start location requires coordinates.")
        if not self.start_location_name or not self.start_location_name.strip():
            raise ValueError("The selected start location requires a name.")
        self.start_location_name = self.start_location_name.strip()
        return self


class TripStartLocationRead(SQLModel):
    trip_id: UUID
    start_location_type: StartLocationType
    start_location_name: str
    start_latitude: float
    start_longitude: float


class LocationSuggestion(SQLModel):
    google_place_id: str
    name: str
    description: str


class LocationDetails(SQLModel):
    google_place_id: str
    name: str
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
