"""Validation schemas for user-customized trip places."""

from datetime import datetime
from enum import Enum
from uuid import UUID

from pydantic import field_validator, model_validator
from sqlmodel import Field, SQLModel

from app.schemas.place import PlaceRead


class AssignmentMode(str, Enum):
    AUTO = "AUTO"
    LOCKED = "LOCKED"


class SavedPlaceCreate(SQLModel):
    place_id: UUID
    custom_order: int | None = Field(default=None, ge=1)
    priority: int = Field(default=0, ge=0)
    is_locked: bool = False
    must_visit: bool = False
    assignment_mode: AssignmentMode = AssignmentMode.AUTO
    assigned_day_id: UUID | None = None
    notes: str | None = Field(default=None, max_length=1000)

    @field_validator("notes")
    @classmethod
    def normalize_notes(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        return value or None

    @model_validator(mode="after")
    def validate_assignment(self) -> "SavedPlaceCreate":
        if self.assignment_mode == AssignmentMode.LOCKED:
            if self.assigned_day_id is None:
                raise ValueError("assigned_day_id is required when assignment_mode is LOCKED.")
        elif self.assignment_mode == AssignmentMode.AUTO:
            if self.assigned_day_id is not None:
                raise ValueError("assigned_day_id must be null when assignment_mode is AUTO.")
        return self


class SavedPlaceUpdate(SQLModel):
    notes: str | None = Field(default=None, max_length=1000)
    priority: int | None = Field(default=None, ge=0)
    is_locked: bool | None = None
    must_visit: bool | None = None
    custom_order: int | None = Field(default=None, ge=1)
    assignment_mode: AssignmentMode | None = None
    assigned_day_id: UUID | None = None

    @field_validator("notes")
    @classmethod
    def normalize_notes(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        return value or None

    @model_validator(mode="after")
    def validate_assignment(self) -> "SavedPlaceUpdate":
        if self.assignment_mode == AssignmentMode.LOCKED:
            if self.assigned_day_id is None:
                raise ValueError("assigned_day_id is required when assignment_mode is LOCKED.")
        elif self.assignment_mode == AssignmentMode.AUTO:
            if self.assigned_day_id is not None:
                raise ValueError("assigned_day_id must be null when assignment_mode is AUTO.")
        return self


class SavedPlaceOrder(SQLModel):
    place_id: UUID
    custom_order: int = Field(ge=1)


class SavedPlaceReorder(SQLModel):
    places: list[SavedPlaceOrder] = Field(min_length=1, max_length=500)

    @model_validator(mode="after")
    def validate_unique_contiguous_order(self) -> "SavedPlaceReorder":
        place_ids = [item.place_id for item in self.places]
        orders = [item.custom_order for item in self.places]
        if len(set(place_ids)) != len(place_ids):
            raise ValueError("Each saved place may appear only once.")
        if len(set(orders)) != len(orders):
            raise ValueError("Each custom order value must be unique.")
        if sorted(orders) != list(range(1, len(orders) + 1)):
            raise ValueError("Custom order values must be contiguous from 1.")
        return self


class SavedPlaceRead(SQLModel):
    id: UUID
    trip_id: UUID
    place_id: UUID
    custom_order: int
    priority: int
    is_locked: bool
    must_visit: bool
    assignment_mode: AssignmentMode = AssignmentMode.AUTO
    assigned_day_id: UUID | None = None
    notes: str | None
    created_at: datetime
    place: PlaceRead
