"""Normalized route-optimization API responses."""

from uuid import UUID

from pydantic import Field
from sqlmodel import SQLModel


class OptimizedPlaceRead(SQLModel):
    place_id: UUID
    name: str
    day_number: int = Field(ge=1)
    visit_order: int = Field(ge=1)
    distance_from_previous: float = Field(ge=0)
    travel_time_minutes: int = Field(ge=0)


class RouteOptimizationRead(SQLModel):
    trip_id: UUID
    optimized_places: list[OptimizedPlaceRead]
    total_distance: float = Field(ge=0)
    total_travel_time_minutes: int = Field(ge=0)
