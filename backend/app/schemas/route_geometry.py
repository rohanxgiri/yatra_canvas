"""Normalized route-geometry API schemas."""

from uuid import UUID

from pydantic import Field
from sqlmodel import SQLModel


class RouteLegGeometryRead(SQLModel):
    start_latitude: float
    start_longitude: float
    end_latitude: float
    end_longitude: float
    distance_meters: float | None = Field(default=None, ge=0)
    duration_seconds: float | None = Field(default=None, ge=0)


class DayRouteGeometryRead(SQLModel):
    day_number: int = Field(ge=1)
    coordinates: list[list[float]] = Field(
        default_factory=list,
        description="List of [latitude, longitude] pairs following the real road path",
    )
    distance_meters: float | None = Field(default=None, ge=0)
    duration_seconds: float | None = Field(default=None, ge=0)
    legs: list[RouteLegGeometryRead] = Field(default_factory=list)


class TripRouteGeometryRead(SQLModel):
    trip_id: UUID
    days: list[DayRouteGeometryRead] = Field(default_factory=list)
    total_distance_meters: float | None = Field(default=None, ge=0)
    total_duration_seconds: float | None = Field(default=None, ge=0)
