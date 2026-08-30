"""SQLModel table definitions for YatraCanvas's initial data model."""

from datetime import date, datetime, time
from uuid import UUID, uuid4

from sqlalchemy import CheckConstraint, Column, DateTime, UniqueConstraint, func
from sqlmodel import Field, SQLModel


def created_at_column() -> Column[datetime]:
    """Build a timezone-aware, database-generated creation timestamp."""

    return Column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )


class City(SQLModel, table=True):
    __tablename__ = "cities"
    __table_args__ = (
        UniqueConstraint(
            "google_place_id",
            name="uq_cities_google_place_id",
        ),
        CheckConstraint("latitude BETWEEN -90 AND 90", name="ck_cities_latitude"),
        CheckConstraint(
            "longitude BETWEEN -180 AND 180", name="ck_cities_longitude"
        ),
    )

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    name: str = Field(max_length=120, index=True)
    state: str | None = Field(default=None, max_length=120)
    country: str = Field(max_length=120)
    latitude: float
    longitude: float
    google_place_id: str | None = Field(default=None, max_length=255, index=True)
    created_at: datetime | None = Field(
        default=None,
        sa_column=created_at_column(),
    )


class Place(SQLModel, table=True):
    __tablename__ = "places"
    __table_args__ = (
        CheckConstraint("latitude BETWEEN -90 AND 90", name="ck_places_latitude"),
        CheckConstraint(
            "longitude BETWEEN -180 AND 180", name="ck_places_longitude"
        ),
        CheckConstraint(
            "rating IS NULL OR (rating BETWEEN 0 AND 5)",
            name="ck_places_rating",
        ),
        CheckConstraint("review_count >= 0", name="ck_places_review_count"),
    )

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    city_id: UUID = Field(foreign_key="cities.id", index=True)
    name: str = Field(max_length=200, index=True)
    category: str = Field(max_length=80, index=True)
    latitude: float
    longitude: float
    rating: float | None = None
    review_count: int = Field(default=0)
    is_popular: bool = Field(default=False)
    is_heritage: bool = Field(default=False)
    is_local_speciality: bool = Field(default=False)
    last_fetched_at: datetime | None = Field(
        default=None,
        sa_column=Column(DateTime(timezone=True), nullable=True),
    )
    created_at: datetime | None = Field(
        default=None,
        sa_column=created_at_column(),
    )


class CityCategoryCache(SQLModel, table=True):
    __tablename__ = "city_category_cache"
    __table_args__ = (
        UniqueConstraint(
            "city_id",
            "category",
            name="uq_city_category_cache_city_category",
        ),
    )

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    city_id: UUID = Field(foreign_key="cities.id", index=True)
    category: str = Field(max_length=80, index=True)
    last_fetched_at: datetime = Field(
        sa_column=Column(DateTime(timezone=True), nullable=False)
    )
    expires_at: datetime = Field(
        sa_column=Column(DateTime(timezone=True), nullable=False, index=True)
    )


class PlaceTag(SQLModel, table=True):
    __tablename__ = "place_tags"
    __table_args__ = (
        UniqueConstraint("place_id", "tag", name="uq_place_tags_place_tag"),
    )

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    place_id: UUID = Field(foreign_key="places.id", index=True)
    tag: str = Field(max_length=80, index=True)


class PlaceSource(SQLModel, table=True):
    __tablename__ = "place_sources"
    __table_args__ = (
        UniqueConstraint(
            "place_id", "source", name="uq_place_sources_place_source"
        ),
        UniqueConstraint(
            "source",
            "external_place_id",
            name="uq_place_sources_source_external_place",
        ),
    )

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    place_id: UUID = Field(foreign_key="places.id", index=True)
    source: str = Field(max_length=50, index=True)
    external_place_id: str = Field(max_length=255, index=True)
    last_fetched_at: datetime = Field(
        sa_column=Column(DateTime(timezone=True), nullable=False)
    )


class Trip(SQLModel, table=True):
    __tablename__ = "trips"
    __table_args__ = (
        CheckConstraint("days > 0", name="ck_trips_days"),
        CheckConstraint(
            "arrival_latitude IS NULL OR "
            "(arrival_latitude BETWEEN -90 AND 90)",
            name="ck_trips_arrival_latitude",
        ),
        CheckConstraint(
            "arrival_longitude IS NULL OR "
            "(arrival_longitude BETWEEN -180 AND 180)",
            name="ck_trips_arrival_longitude",
        ),
        CheckConstraint(
            "start_location_type IS NULL OR start_location_type IN "
            "('arrival', 'hotel', 'current_location', 'custom')",
            name="ck_trips_start_location_type",
        ),
        CheckConstraint(
            "start_latitude IS NULL OR (start_latitude BETWEEN -90 AND 90)",
            name="ck_trips_start_latitude",
        ),
        CheckConstraint(
            "start_longitude IS NULL OR (start_longitude BETWEEN -180 AND 180)",
            name="ck_trips_start_longitude",
        ),
    )

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    # Supabase auth owns auth.users, so this is intentionally not a foreign key.
    user_id: UUID = Field(index=True)
    city_id: UUID = Field(foreign_key="cities.id", index=True)
    trip_name: str = Field(max_length=160)
    days: int
    arrival_place: str | None = Field(default=None, max_length=255)
    arrival_latitude: float | None = None
    arrival_longitude: float | None = None
    start_location_type: str | None = Field(default=None, max_length=30)
    start_location_name: str | None = Field(default=None, max_length=255)
    start_latitude: float | None = None
    start_longitude: float | None = None
    start_date: date | None = None
    created_at: datetime | None = Field(
        default=None,
        sa_column=created_at_column(),
    )


class TripPreference(SQLModel, table=True):
    __tablename__ = "trip_preferences"
    __table_args__ = (
        UniqueConstraint(
            "trip_id", "preference", name="uq_trip_preferences_trip_preference"
        ),
        CheckConstraint("weight >= 0", name="ck_trip_preferences_weight"),
    )

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    trip_id: UUID = Field(foreign_key="trips.id", index=True)
    preference: str = Field(max_length=80, index=True)
    weight: float = Field(default=1.0)


class UserSavedPlace(SQLModel, table=True):
    __tablename__ = "user_saved_places"
    __table_args__ = (
        UniqueConstraint(
            "trip_id", "place_id", name="uq_user_saved_places_trip_place"
        ),
        CheckConstraint(
            "custom_order IS NULL OR custom_order >= 0",
            name="ck_user_saved_places_custom_order",
        ),
        CheckConstraint("priority >= 0", name="ck_user_saved_places_priority"),
    )

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    trip_id: UUID = Field(foreign_key="trips.id", index=True)
    place_id: UUID = Field(foreign_key="places.id", index=True)
    custom_order: int | None = None
    priority: int = Field(default=0)
    is_locked: bool = Field(default=False)
    must_visit: bool = Field(default=False)
    notes: str | None = None
    created_at: datetime | None = Field(
        default=None,
        sa_column=created_at_column(),
    )


class RouteMatrixCache(SQLModel, table=True):
    __tablename__ = "route_matrix_cache"
    __table_args__ = (
        UniqueConstraint(
            "trip_id",
            "from_key",
            "to_key",
            "travel_mode",
            name="uq_route_matrix_cache_trip_pair_mode",
        ),
        CheckConstraint("distance_meters >= 0", name="ck_route_matrix_distance"),
        CheckConstraint(
            "static_duration_seconds >= 0",
            name="ck_route_matrix_static_duration",
        ),
        CheckConstraint(
            "traffic_duration_seconds IS NULL OR traffic_duration_seconds >= 0",
            name="ck_route_matrix_traffic_duration",
        ),
        CheckConstraint(
            "from_place_id IS NOT NULL OR "
            "(from_latitude IS NOT NULL AND from_longitude IS NOT NULL)",
            name="ck_route_matrix_from_location",
        ),
        CheckConstraint(
            "to_place_id IS NOT NULL OR "
            "(to_latitude IS NOT NULL AND to_longitude IS NOT NULL)",
            name="ck_route_matrix_to_location",
        ),
    )

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    trip_id: UUID = Field(foreign_key="trips.id", index=True)
    from_place_id: UUID | None = Field(
        default=None, foreign_key="places.id", index=True
    )
    to_place_id: UUID | None = Field(
        default=None, foreign_key="places.id", index=True
    )
    from_location_type: str = Field(max_length=30)
    from_name: str | None = Field(default=None, max_length=255)
    from_latitude: float | None = None
    from_longitude: float | None = None
    to_location_type: str = Field(max_length=30)
    to_name: str | None = Field(default=None, max_length=255)
    to_latitude: float | None = None
    to_longitude: float | None = None
    # Canonical non-null keys make pair uniqueness reliable even when a
    # location is coordinate-based and its place UUID is null.
    from_key: str = Field(max_length=350, index=True)
    to_key: str = Field(max_length=350, index=True)
    distance_meters: int
    static_duration_seconds: int
    traffic_duration_seconds: int | None = None
    travel_mode: str = Field(default="driving", max_length=30)
    calculated_at: datetime = Field(
        sa_column=Column(DateTime(timezone=True), nullable=False)
    )
    expires_at: datetime | None = Field(
        default=None,
        sa_column=Column(DateTime(timezone=True), nullable=True, index=True),
    )


class TripItinerary(SQLModel, table=True):
    __tablename__ = "trip_itinerary"
    __table_args__ = (
        UniqueConstraint(
            "trip_id",
            "day_number",
            "visit_order",
            name="uq_trip_itinerary_trip_day_visit",
        ),
        CheckConstraint("day_number > 0", name="ck_trip_itinerary_day_number"),
        CheckConstraint("visit_order > 0", name="ck_trip_itinerary_visit_order"),
        CheckConstraint(
            "distance_from_previous IS NULL OR distance_from_previous >= 0",
            name="ck_trip_itinerary_distance",
        ),
        CheckConstraint(
            "travel_time_minutes IS NULL OR travel_time_minutes >= 0",
            name="ck_trip_itinerary_travel_time",
        ),
    )

    id: UUID = Field(default_factory=uuid4, primary_key=True)
    trip_id: UUID = Field(foreign_key="trips.id", index=True)
    place_id: UUID = Field(foreign_key="places.id", index=True)
    day_number: int
    visit_order: int
    planned_arrival_time: time | None = None
    planned_departure_time: time | None = None
    distance_from_previous: float | None = None
    travel_time_minutes: int | None = None
    created_at: datetime | None = Field(
        default=None,
        sa_column=created_at_column(),
    )
