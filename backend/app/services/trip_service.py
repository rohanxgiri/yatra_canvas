"""Trip creation and start-location persistence rules."""

from uuid import UUID

from sqlmodel import Session

from app.models import City, Trip, TripPreference
from app.schemas import (
    StartLocationType,
    TripCreate,
    TripRead,
    TripStartLocationRead,
    TripStartLocationUpdate,
)


# DEVELOPMENT ONLY: all unauthenticated trip creation is assigned to this
# server-owned placeholder. Replace this dependency with verified auth identity;
# never accept user_id from the request body.
DEVELOPMENT_USER_ID = UUID("00000000-0000-4000-8000-000000000001")


class TripServiceError(Exception):
    pass


class TripServiceNotFoundError(TripServiceError):
    pass


class TripStartLocationError(TripServiceError):
    pass


class TripCityNotFoundError(TripServiceError):
    pass


class TripService:
    def __init__(self, *, development_user_id: UUID = DEVELOPMENT_USER_ID) -> None:
        self._development_user_id = development_user_id

    def create(self, session: Session, request: TripCreate) -> TripRead:
        city = session.get(City, request.city_id)
        if city is None:
            raise TripCityNotFoundError("City not found.")

        preference_values = self._preference_values(request)
        start_type = request.start_location_type
        if start_type == StartLocationType.arrival:
            start_name = request.arrival_place
            start_latitude = request.arrival_latitude
            start_longitude = request.arrival_longitude
            start_provider = None
            start_provider_place_id = None
        else:
            start_name = request.start_location_name
            start_latitude = request.start_latitude
            start_longitude = request.start_longitude
            start_provider = request.start_location_provider
            start_provider_place_id = request.start_location_provider_place_id

        trip = Trip(
            user_id=self._development_user_id,
            city_id=city.id,
            trip_name=request.trip_name or f"{city.name} trip",
            days=request.days,
            arrival_place=request.arrival_place,
            arrival_latitude=request.arrival_latitude,
            arrival_longitude=request.arrival_longitude,
            start_location_type=start_type.value if start_type is not None else None,
            start_location_name=start_name,
            start_latitude=start_latitude,
            start_longitude=start_longitude,
            start_location_provider=start_provider,
            start_location_provider_place_id=start_provider_place_id,
            start_date=request.start_date,
        )
        try:
            session.add(trip)
            session.flush()
            session.add_all(
                TripPreference(
                    trip_id=trip.id,
                    preference=preference,
                    weight=1.0,
                )
                for preference in preference_values
            )
            session.commit()
            session.refresh(trip)
        except Exception:
            session.rollback()
            raise
        return self._to_trip_read(trip, preference_values)

    def get_start_location(
        self, session: Session, trip_id: UUID
    ) -> TripStartLocationRead:
        trip = self._require_trip(session, trip_id)
        return self._to_start_location(trip)

    def update_start_location(
        self,
        session: Session,
        trip_id: UUID,
        request: TripStartLocationUpdate,
    ) -> TripStartLocationRead:
        trip = self._require_trip(session, trip_id)
        if request.start_location_type == StartLocationType.arrival:
            if trip.arrival_latitude is None or trip.arrival_longitude is None:
                raise TripStartLocationError(
                    "Save arrival coordinates before using the arrival point "
                    "as the trip start."
                )
            name = trip.arrival_place or "Arrival point"
            latitude = trip.arrival_latitude
            longitude = trip.arrival_longitude
            provider = None
            provider_place_id = None
        else:
            if (
                request.start_latitude is None
                or request.start_longitude is None
                or not request.start_location_name
            ):
                raise TripStartLocationError(
                    "The selected start location requires a name and coordinates."
                )
            name = request.start_location_name
            latitude = request.start_latitude
            longitude = request.start_longitude
            provider = request.start_location_provider
            provider_place_id = request.start_location_provider_place_id

        trip.start_location_type = request.start_location_type.value
        trip.start_location_name = name
        trip.start_latitude = latitude
        trip.start_longitude = longitude
        trip.start_location_provider = provider
        trip.start_location_provider_place_id = provider_place_id
        session.commit()
        session.refresh(trip)
        return self._to_start_location(trip)

    @staticmethod
    def _require_trip(session: Session, trip_id: UUID) -> Trip:
        trip = session.get(Trip, trip_id)
        if trip is None:
            raise TripServiceNotFoundError("Trip not found.")
        return trip

    @staticmethod
    def _preference_values(request: TripCreate) -> list[str]:
        values: list[str] = []
        seen: set[str] = set()
        for value in [*request.purposes, *request.preferences]:
            key = value.casefold()
            if key not in seen:
                seen.add(key)
                values.append(value)
        return values

    @staticmethod
    def _to_trip_read(trip: Trip, preferences: list[str]) -> TripRead:
        if trip.start_date is None or trip.arrival_place is None:
            raise TripServiceError("Created trip is missing required values.")
        return TripRead(
            trip_id=trip.id,
            city_id=trip.city_id,
            trip_name=trip.trip_name,
            days=trip.days,
            start_date=trip.start_date,
            arrival_place=trip.arrival_place,
            arrival_latitude=trip.arrival_latitude,
            arrival_longitude=trip.arrival_longitude,
            start_location_type=(
                StartLocationType(trip.start_location_type)
                if trip.start_location_type is not None
                else None
            ),
            start_location_name=trip.start_location_name,
            start_latitude=trip.start_latitude,
            start_longitude=trip.start_longitude,
            start_location_provider=trip.start_location_provider,
            start_location_provider_place_id=(
                trip.start_location_provider_place_id
            ),
            preferences=preferences,
            created_at=trip.created_at,
        )

    @staticmethod
    def _to_start_location(trip: Trip) -> TripStartLocationRead:
        location_type = trip.start_location_type
        name = trip.start_location_name
        latitude = trip.start_latitude
        longitude = trip.start_longitude
        if not location_type or name is None or latitude is None or longitude is None:
            raise TripStartLocationError(
                "A start location has not been selected for this trip."
            )
        return TripStartLocationRead(
            trip_id=trip.id,
            start_location_type=StartLocationType(location_type),
            start_location_name=name,
            start_latitude=latitude,
            start_longitude=longitude,
            start_location_provider=trip.start_location_provider,
            start_location_provider_place_id=(
                trip.start_location_provider_place_id
            ),
        )
