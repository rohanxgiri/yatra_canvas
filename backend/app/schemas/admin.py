"""Admin dashboard, management, and moderation schemas."""

from datetime import date, datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class AdminDashboardMetrics(BaseModel):
    """Aggregated operational metrics for the admin dashboard home."""

    total_users: int
    total_trips: int
    total_places: int
    total_destinations: int
    active_destinations: int
    places_by_status: dict[str, int]
    open_reports_count: int
    recent_trips: list[dict[str, Any]]
    recent_reports: list[dict[str, Any]]
    provider_health: dict[str, Any]


class AdminUserRead(BaseModel):
    """Admin view of a user account with trip count."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    email: str
    role: str
    is_active: bool
    created_at: datetime | None = None
    trip_count: int = 0


class AdminUserUpdate(BaseModel):
    """Fields allowed to be updated by an administrator."""

    model_config = ConfigDict(extra="forbid")

    is_active: bool | None = None
    role: str | None = None
    name: str | None = None


class AdminDestinationRead(BaseModel):
    """Admin view of a city/destination with operational metrics."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    state: str | None = None
    country: str
    latitude: float
    longitude: float
    google_place_id: str | None = None
    is_enabled: bool
    is_featured: bool
    is_popular: bool
    image_url: str | None = None
    description: str | None = None
    display_order: int
    places_count: int = 0
    trips_count: int = 0


class AdminDestinationCreate(BaseModel):
    """Payload to create a new destination."""

    model_config = ConfigDict(extra="forbid")

    name: str = Field(min_length=1, max_length=120)
    state: str | None = Field(default=None, max_length=120)
    country: str = Field(default="India", max_length=120)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    is_enabled: bool = True
    is_featured: bool = False
    is_popular: bool = False
    image_url: str | None = Field(default=None, max_length=1000)
    description: str | None = Field(default=None, max_length=1000)
    display_order: int = Field(default=0)


class AdminDestinationUpdate(BaseModel):
    """Payload to update an existing destination."""

    model_config = ConfigDict(extra="forbid")

    name: str | None = Field(default=None, min_length=1, max_length=120)
    state: str | None = Field(default=None, max_length=120)
    country: str | None = Field(default=None, max_length=120)
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    is_enabled: bool | None = None
    is_featured: bool | None = None
    is_popular: bool | None = None
    image_url: str | None = Field(default=None, max_length=1000)
    description: str | None = Field(default=None, max_length=1000)
    display_order: int | None = None


class AdminPlaceRead(BaseModel):
    """Admin summary of a POI with moderation status and counts."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    city_id: UUID
    city_name: str | None = None
    name: str
    category: str
    latitude: float
    longitude: float
    rating: float | None = None
    review_count: int = 0
    is_popular: bool = False
    is_heritage: bool = False
    is_local_speciality: bool = False
    wikidata_id: str | None = None
    importance_score: float | None = None
    opening_hours_status: str = "UNKNOWN"
    raw_opening_hours: str | None = None
    moderation_status: str = "ACTIVE"
    sources_count: int = 0
    reports_count: int = 0


class AdminPlaceDetailRead(AdminPlaceRead):
    """Detailed place information including provider provenance and reports."""

    sources: list[dict[str, Any]] = []
    opening_hours: list[dict[str, Any]] = []
    tags: list[str] = []
    reports: list[dict[str, Any]] = []


class AdminPlaceUpdate(BaseModel):
    """Payload to moderate or adjust a place."""

    model_config = ConfigDict(extra="forbid")

    moderation_status: str | None = Field(
        default=None,
        pattern=r"^(ACTIVE|HIDDEN|RESTRICTED|DUPLICATE|INVALID)$",
    )
    is_popular: bool | None = None
    is_heritage: bool | None = None
    is_local_speciality: bool | None = None


class AdminTripRead(BaseModel):
    """Admin summary view of a user trip."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    user_name: str | None = None
    city_id: UUID
    city_name: str | None = None
    trip_name: str
    days: int
    start_date: date | None = None
    arrival_place: str | None = None
    start_location_type: str | None = None
    start_location_name: str | None = None
    saved_places_count: int = 0
    itinerary_stops_count: int = 0
    created_at: datetime | None = None


class AdminTripDetailRead(AdminTripRead):
    """Full trip breakdown for administrative inspection and debugging."""

    trip_days: list[dict[str, Any]] = []
    preferences: list[dict[str, Any]] = []
    saved_places: list[dict[str, Any]] = []
    itinerary: list[dict[str, Any]] = []


class AdminReportRead(BaseModel):
    """Issue report submitted on a place."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    place_id: UUID
    place_name: str | None = None
    city_name: str | None = None
    user_id: UUID | None = None
    reason: str
    details: str | None = None
    status: str
    admin_notes: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None


class AdminReportUpdate(BaseModel):
    """Update status or notes on a place report."""

    model_config = ConfigDict(extra="forbid")

    status: str | None = Field(
        default=None,
        pattern=r"^(OPEN|REVIEWING|RESOLVED|REJECTED)$",
    )
    admin_notes: str | None = Field(default=None, max_length=1000)


class AdminProviderStatus(BaseModel):
    """Operational health overview of external data providers."""

    providers: dict[str, Any]
