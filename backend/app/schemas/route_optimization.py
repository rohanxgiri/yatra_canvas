"""Normalized route-optimization API responses with time-aware scheduling."""

from datetime import time
from typing import Literal
from uuid import UUID

from pydantic import Field
from sqlmodel import SQLModel

from app.schemas.route_geometry import TripRouteGeometryRead


class OptimizedPlaceRead(SQLModel):
    id: UUID | None = None
    place_id: UUID
    name: str
    day_number: int = Field(ge=1)
    visit_order: int = Field(ge=1)
    distance_from_previous: float = Field(ge=0)
    travel_time_minutes: int = Field(ge=0)
    planned_arrival_time: time | None = None
    planned_departure_time: time | None = None
    visit_duration_minutes: int = Field(default=60, ge=0)
    is_opening_hours_known: bool = False
    status: str = Field(default="PLANNED")



class ItineraryBreakRead(SQLModel):
    day_number: int = Field(ge=1)
    start_time: time
    end_time: time
    duration_minutes: int = Field(ge=0)
    label: str = "Midday Break"


class UnscheduledPlaceRead(SQLModel):
    place_id: UUID
    name: str
    reason: Literal[
        "NO_TIME_AVAILABLE",
        "CLOSED_ON_AVAILABLE_DAYS",
        "LOCKED_DAY_INFEASIBLE",
        "DAILY_CAPACITY_EXCEEDED",
        "NO_FEASIBLE_DAY",
    ]
    assigned_day_id: UUID | None = None


class RouteOptimizationRead(SQLModel):
    trip_id: UUID
    optimized_places: list[OptimizedPlaceRead]
    total_distance: float = Field(ge=0)
    total_travel_time_minutes: int = Field(ge=0)
    total_days: int = Field(default=1, ge=1)
    breaks: list[ItineraryBreakRead] = Field(default_factory=list)
    conflicts: list[str] = Field(default_factory=list)
    unscheduled_places: list[UnscheduledPlaceRead] = Field(default_factory=list)
    route_geometry: "TripRouteGeometryRead | None" = None
