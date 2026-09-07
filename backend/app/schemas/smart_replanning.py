"""Schemas for smart trip re-planning and change impact evaluation."""

from datetime import time
from enum import Enum
from uuid import UUID

from pydantic import Field
from sqlmodel import SQLModel

from app.schemas.route_optimization import (
    ItineraryBreakRead,
    OptimizedPlaceRead,
    RouteOptimizationRead,
    UnscheduledPlaceRead,
)


class ItineraryStopStatus(str, Enum):
    PLANNED = "PLANNED"
    COMPLETED = "COMPLETED"
    MISSED = "MISSED"
    SKIPPED = "SKIPPED"


class ItineraryStopStatusUpdate(SQLModel):
    status: ItineraryStopStatus


class MoveItineraryPlaceRequest(SQLModel):
    place_id: UUID
    target_day_number: int | None = Field(default=None, ge=1)
    target_day_id: UUID | None = None


class MoveItineraryPlaceResponse(SQLModel):
    success: bool
    reason: str | None = None
    trip_id: UUID
    place_id: UUID
    source_day_number: int | None = None
    target_day_number: int | None = None
    source_itinerary: list[OptimizedPlaceRead] = Field(default_factory=list)
    target_itinerary: list[OptimizedPlaceRead] = Field(default_factory=list)
    updated_itinerary: RouteOptimizationRead | None = None


class MovedPlaceRead(SQLModel):
    place_id: UUID
    name: str
    from_day: int = Field(ge=1)
    from_time: time | None = None
    to_day: int = Field(ge=1)
    to_time: time | None = None


class TripReplanImpactRead(SQLModel):
    trip_id: UUID
    is_stale: bool
    requires_replan_preview: bool
    reasons: list[str] = Field(default_factory=list)
    summary: str


class TripReplanPreviewRead(SQLModel):
    trip_id: UUID
    is_stale: bool
    summary: str
    added_places: list[str] = Field(default_factory=list)
    removed_places: list[str] = Field(default_factory=list)
    moved_places: list[MovedPlaceRead] = Field(default_factory=list)
    travel_time_delta_minutes: int = 0
    proposed_itinerary: list[OptimizedPlaceRead] = Field(default_factory=list)
    breaks: list[ItineraryBreakRead] = Field(default_factory=list)
    conflicts: list[str] = Field(default_factory=list)
    unscheduled_places: list[UnscheduledPlaceRead] = Field(default_factory=list)
