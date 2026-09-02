"""Pydantic schemas for Weather-Aware Trip Assistance."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class WeatherAdvisoryRead(BaseModel):
    id: str
    day_number: int = Field(ge=1)
    condition: str
    severity: str
    affected_start: datetime | None = None
    affected_end: datetime | None = None
    summary: str
    affected_place_ids: list[UUID] = Field(default_factory=list)
    affected_place_names: list[str] = Field(default_factory=list)
    actions: list[str] = Field(default_factory=list)

    model_config = ConfigDict(from_attributes=True)


class TripWeatherAdvisoriesRead(BaseModel):
    trip_id: UUID
    status: str = "ok"
    advisories: list[WeatherAdvisoryRead] = Field(default_factory=list)

    model_config = ConfigDict(from_attributes=True)


class PlaceAlternativeRead(BaseModel):
    place_id: UUID
    name: str
    category: str
    reason: str
    environment: str = "indoor"

    model_config = ConfigDict(from_attributes=True)


class ProposedStopRead(BaseModel):
    place_id: UUID
    name: str
    visit_order: int = Field(ge=1)
    time_window: str | None = None
    is_alternative: bool = False
    environment: str = "unknown"

    model_config = ConfigDict(from_attributes=True)


class DayRearrangePreviewRead(BaseModel):
    trip_id: UUID
    day_number: int = Field(ge=1)
    original_places: list[ProposedStopRead] = Field(default_factory=list)
    proposed_places: list[ProposedStopRead] = Field(default_factory=list)
    explanation: str

    model_config = ConfigDict(from_attributes=True)


class ApplyRearrangementRequest(BaseModel):
    day_number: int = Field(ge=1)
    place_ids: list[UUID] = Field(min_length=1)


class RearrangePreviewRequest(BaseModel):
    day_number: int = Field(ge=1)
    alternative_place_ids: list[UUID] = Field(default_factory=list)
