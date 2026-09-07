"""Validation schemas for place endpoints."""

from datetime import datetime
from uuid import UUID

from typing import Any, Final
from pydantic import ValidationInfo, field_validator, model_validator
from sqlmodel import Field, SQLModel

WEEKDAY_NAMES: Final[list[str]] = [
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
    "sunday",
]


class OpeningHoursInterval(SQLModel):
    open: str = Field(description="Opening time in HH:MM format")
    close: str = Field(description="Closing time in HH:MM format")


class PlaceBase(SQLModel):
    name: str = Field(min_length=1, max_length=200)
    category: str = Field(min_length=1, max_length=80)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    rating: float | None = Field(default=None, ge=0, le=5)
    review_count: int = Field(default=0, ge=0)
    is_popular: bool = False
    is_heritage: bool = False
    is_local_speciality: bool = False
    wikidata_id: str | None = None
    importance_score: float | None = Field(default=None, ge=0, le=1)
    last_fetched_at: datetime | None = None
    opening_hours_status: str = Field(
        default="UNKNOWN",
        description="Opening hours status: KNOWN, CLOSED, or UNKNOWN",
    )
    raw_opening_hours: str | None = Field(
        default=None,
        description="Raw provider opening_hours string",
    )

    @field_validator("name", "category")
    @classmethod
    def strip_required_text(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("must not be blank")
        return value


class PlaceCreate(PlaceBase):
    """Fields accepted when creating a place."""

    city_id: UUID


class PlaceRead(PlaceBase):
    """Public place representation returned by the API."""

    id: UUID
    city_id: UUID
    created_at: datetime
    opening_hours: dict[str, list[OpeningHoursInterval]] = Field(
        default_factory=lambda: {d: [] for d in WEEKDAY_NAMES}
    )

    @field_validator("opening_hours", mode="before")
    @classmethod
    def populate_opening_hours(cls, v: Any, info: ValidationInfo) -> Any:
        if isinstance(v, dict) and v:
            return v
        if isinstance(v, list) and v:
            res: dict[str, list[dict[str, str]]] = {day: [] for day in WEEKDAY_NAMES}
            for item in v:
                d = getattr(item, "day_of_week", None)
                intervals = getattr(item, "intervals", [])
                if d is not None and 0 <= d < 7:
                    res[WEEKDAY_NAMES[d]] = intervals
            return res
        return {day: [] for day in WEEKDAY_NAMES}

    @model_validator(mode="after")
    def ensure_opening_hours(self) -> "PlaceRead":
        if self.raw_opening_hours and all(not intervals for intervals in self.opening_hours.values()):
            from app.services.opening_hours_parser import OpeningHoursParser

            parsed = OpeningHoursParser.parse(self.raw_opening_hours)
            self.opening_hours = {
                day: [OpeningHoursInterval(**i) for i in intervals]
                for day, intervals in parsed.to_dict().items()
            }
        return self


class GoogleNearbyPlace(SQLModel):
    """Normalized Google place data used only inside the backend."""

    google_place_id: str = Field(min_length=1, max_length=255)
    name: str = Field(min_length=1, max_length=200)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    rating: float | None = Field(default=None, ge=0, le=5)
    review_count: int = Field(default=0, ge=0)
    primary_type: str | None = None
    types: list[str] = Field(default_factory=list)


class PlacePrefetchRequest(SQLModel):
    city_id: UUID
    stage: str = "destination_confirmed"
    categories: list[str] | None = None


class PlacePrefetchResponse(SQLModel):
    city_id: UUID
    city_name: str
    stage: str
    categories_requested: list[str]
    categories_skipped_sufficient: list[str]
    categories_enriched: list[str]
    duplicate_refreshes_prevented: int


class PlaceSearchResult(SQLModel):
    name: str
    address: str | None = None
    latitude: float
    longitude: float
    category: str = "sightseeing"
    distance_meters: float | None = None
    place_id: UUID | None = None
    external_place_id: str | None = None
    source: str = "database"


class PlaceResolveRequest(SQLModel):
    name: str
    latitude: float
    longitude: float
    category: str = "sightseeing"
    external_place_id: str | None = None
    formatted_address: str | None = None
