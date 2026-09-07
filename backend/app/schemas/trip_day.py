"""TripDay schemas for individual day configuration."""

import datetime as dt
from datetime import datetime, time
from enum import Enum
from uuid import UUID

from pydantic import ConfigDict, model_validator
from sqlmodel import SQLModel


class DayType(str, Enum):
    FULL_DAY = "FULL_DAY"
    HALF_DAY = "HALF_DAY"
    REST = "REST"
    TRAVEL = "TRAVEL"


class TripDayRead(SQLModel):
    id: UUID
    trip_id: UUID
    day_number: int
    date: dt.date
    day_type: DayType
    start_time: time | None = None
    end_time: time | None = None
    created_at: datetime | None = None


class TripDayUpdate(SQLModel):
    """Update schema for configuring day type and daily touring window."""

    model_config = ConfigDict(extra="forbid")

    day_type: DayType | None = None
    start_time: time | None = None
    end_time: time | None = None

    @model_validator(mode="after")
    def validate_times(self) -> "TripDayUpdate":
        if self.start_time is not None and self.end_time is not None:
            if self.end_time <= self.start_time:
                raise ValueError("End time must be after start time.")
        return self
