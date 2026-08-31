"""Trip start-location persistence rules."""

from uuid import UUID

from sqlmodel import Session

from app.models import Trip
from app.schemas import (
    StartLocationType,
    TripStartLocationRead,
    TripStartLocationUpdate,
)


class TripServiceError(Exception):
    pass


class TripServiceNotFoundError(TripServiceError):
    pass


class TripStartLocationError(TripServiceError):
    pass


class TripService:
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
