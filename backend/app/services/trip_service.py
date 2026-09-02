"""Trip creation, retrieval, and editing persistence rules."""

from datetime import timedelta
from uuid import UUID

from sqlalchemy import delete, or_
from sqlmodel import Session, select

from app.models import City, RouteMatrixCache, Trip, TripItinerary, TripPreference
from app.schemas import (
    CityRead,
    StartLocationType,
    TripCreate,
    TripRead,
    TripStartLocationRead,
    TripStartLocationUpdate,
    TripUpdate,
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
        return self._to_trip_read(trip, preference_values, city=city)

    def get(self, session: Session, trip_id: UUID) -> TripRead:
        trip = self._require_trip(session, trip_id)
        city = session.get(City, trip.city_id)
        preferences = session.exec(
            select(TripPreference).where(TripPreference.trip_id == trip.id)
        ).all()
        preference_values = [p.preference for p in preferences]
        return self._to_trip_read(trip, preference_values, city=city)

    def update(
        self,
        session: Session,
        trip_id: UUID,
        request: TripUpdate,
    ) -> TripRead:
        trip = self._require_trip(session, trip_id)

        city_changed = False
        if request.city_id is not None and request.city_id != trip.city_id:
            new_city = session.get(City, request.city_id)
            if new_city is None:
                raise TripCityNotFoundError("City not found.")
            trip.city_id = new_city.id
            city_changed = True

        effective_start = (
            request.start_date
            if request.start_date is not None
            else trip.start_date
        )
        if (
            request.start_date is not None
            or request.end_date is not None
            or request.days is not None
        ):
            if request.start_date is not None and request.end_date is not None:
                if request.end_date < request.start_date:
                    raise TripServiceError("End date cannot be before start date.")
                expected_days = (request.end_date - request.start_date).days + 1
                if request.days is not None and request.days != expected_days:
                    raise TripServiceError(
                        "Days must match the inclusive trip date range."
                    )
                trip.start_date = request.start_date
                trip.days = expected_days
            elif request.end_date is not None:
                if effective_start is None:
                    raise TripServiceError(
                        "Cannot compute days without a start date."
                    )
                if request.end_date < effective_start:
                    raise TripServiceError("End date cannot be before start date.")
                expected_days = (request.end_date - effective_start).days + 1
                if request.days is not None and request.days != expected_days:
                    raise TripServiceError(
                        "Days must match the inclusive trip date range."
                    )
                trip.days = expected_days
                if request.start_date is not None:
                    trip.start_date = request.start_date
            else:
                if request.start_date is not None:
                    trip.start_date = request.start_date
                if request.days is not None:
                    if request.days < 1:
                        raise TripServiceError("Days must be greater than zero.")
                    trip.days = request.days

        if request.trip_name is not None:
            trip.trip_name = request.trip_name

        if request.arrival_place is not None:
            trip.arrival_place = request.arrival_place
        if (
            request.arrival_latitude is not None
            and request.arrival_longitude is not None
        ):
            trip.arrival_latitude = request.arrival_latitude
            trip.arrival_longitude = request.arrival_longitude

        start_coords_changed = False
        if request.start_location_type is not None:
            if request.start_location_type == StartLocationType.arrival:
                start_name = trip.arrival_place
                start_lat = trip.arrival_latitude
                start_lng = trip.arrival_longitude
                start_prov = None
                start_prov_id = None
            else:
                start_name = (
                    request.start_location_name or trip.start_location_name
                )
                start_lat = (
                    request.start_latitude
                    if request.start_latitude is not None
                    else trip.start_latitude
                )
                start_lng = (
                    request.start_longitude
                    if request.start_longitude is not None
                    else trip.start_longitude
                )
                start_prov = (
                    request.start_location_provider
                    if request.start_location_provider is not None
                    else trip.start_location_provider
                )
                start_prov_id = (
                    request.start_location_provider_place_id
                    if request.start_location_provider_place_id is not None
                    else trip.start_location_provider_place_id
                )
                if not start_name:
                    raise TripStartLocationError(
                        "The selected start location requires a name."
                    )
                if start_lat is None or start_lng is None:
                    raise TripStartLocationError(
                        "The selected start location requires coordinates."
                    )

            if (
                trip.start_latitude != start_lat
                or trip.start_longitude != start_lng
                or trip.start_location_type != request.start_location_type.value
            ):
                start_coords_changed = True

            trip.start_location_type = request.start_location_type.value
            trip.start_location_name = start_name
            trip.start_latitude = start_lat
            trip.start_longitude = start_lng
            trip.start_location_provider = start_prov
            trip.start_location_provider_place_id = start_prov_id
        else:
            if request.start_location_name is not None:
                trip.start_location_name = request.start_location_name
            if (
                request.start_latitude is not None
                and request.start_longitude is not None
            ):
                if (
                    trip.start_latitude != request.start_latitude
                    or trip.start_longitude != request.start_longitude
                ):
                    start_coords_changed = True
                trip.start_latitude = request.start_latitude
                trip.start_longitude = request.start_longitude
            if request.start_location_provider is not None:
                trip.start_location_provider = request.start_location_provider
            if request.start_location_provider_place_id is not None:
                trip.start_location_provider_place_id = (
                    request.start_location_provider_place_id
                )

        try:
            # Invalidation behavior:
            # If city changed, invalidate all route matrix cache and itinerary for this trip.
            # If only start coordinates changed, invalidate only start-related directional legs.
            # UserSavedPlace rows are strictly preserved.
            if city_changed:
                session.exec(
                    delete(RouteMatrixCache).where(
                        RouteMatrixCache.trip_id == trip.id
                    )
                )
                session.exec(
                    delete(TripItinerary).where(
                        TripItinerary.trip_id == trip.id
                    )
                )
            elif start_coords_changed:
                session.exec(
                    delete(RouteMatrixCache).where(
                        RouteMatrixCache.trip_id == trip.id,
                        or_(
                            RouteMatrixCache.from_location_type == "start",
                            RouteMatrixCache.to_location_type == "start",
                        ),
                    )
                )
                session.exec(
                    delete(TripItinerary).where(
                        TripItinerary.trip_id == trip.id
                    )
                )

            # Reconcile preferences transactionally if provided
            if request.purposes is not None or request.preferences is not None:
                combined_sources = [
                    *(request.purposes if request.purposes is not None else []),
                    *(
                        request.preferences
                        if request.preferences is not None
                        else []
                    ),
                ]
                new_pref_values: list[str] = []
                seen: set[str] = set()
                for p in combined_sources:
                    key = p.casefold()
                    if key not in seen:
                        seen.add(key)
                        new_pref_values.append(p)

                session.exec(
                    delete(TripPreference).where(
                        TripPreference.trip_id == trip.id
                    )
                )
                session.add_all(
                    TripPreference(
                        trip_id=trip.id,
                        preference=pref,
                        weight=1.0,
                    )
                    for pref in new_pref_values
                )

            session.add(trip)
            session.commit()
            session.refresh(trip)
        except Exception:
            session.rollback()
            raise

        city = session.get(City, trip.city_id)
        all_prefs = session.exec(
            select(TripPreference).where(TripPreference.trip_id == trip.id)
        ).all()
        preference_values = [p.preference for p in all_prefs]
        return self._to_trip_read(trip, preference_values, city=city)

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

        start_coords_changed = (
            trip.start_latitude != latitude
            or trip.start_longitude != longitude
            or trip.start_location_type != request.start_location_type.value
        )

        trip.start_location_type = request.start_location_type.value
        trip.start_location_name = name
        trip.start_latitude = latitude
        trip.start_longitude = longitude
        trip.start_location_provider = provider
        trip.start_location_provider_place_id = provider_place_id

        try:
            if start_coords_changed:
                session.exec(
                    delete(RouteMatrixCache).where(
                        RouteMatrixCache.trip_id == trip.id
                    )
                )
                session.exec(
                    delete(TripItinerary).where(
                        TripItinerary.trip_id == trip.id
                    )
                )
            session.add(trip)
            session.commit()
            session.refresh(trip)
        except Exception:
            session.rollback()
            raise
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
    def _to_trip_read(
        trip: Trip,
        preferences: list[str],
        city: City | None = None,
    ) -> TripRead:
        if trip.start_date is None or trip.arrival_place is None:
            raise TripServiceError("Trip is missing required values.")
        end_date = trip.start_date + timedelta(days=trip.days - 1)
        city_read = (
            CityRead(
                id=city.id,
                name=city.name,
                state=city.state,
                country=city.country,
                latitude=city.latitude,
                longitude=city.longitude,
                google_place_id=city.google_place_id,
                created_at=city.created_at,
            )
            if city is not None and city.created_at is not None
            else None
        )
        return TripRead(
            trip_id=trip.id,
            city_id=trip.city_id,
            city=city_read,
            trip_name=trip.trip_name,
            days=trip.days,
            start_date=trip.start_date,
            end_date=end_date,
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
