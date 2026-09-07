"""TripDay persistence, generation, retrieval, and reconciliation rules."""

from datetime import date, timedelta
from uuid import UUID

from sqlalchemy import delete
from sqlmodel import Session, select

from app.core.itinerary_constants import DEFAULT_DAY_END_TIME, DEFAULT_DAY_START_TIME
from app.models.entities import Trip, TripDay, TripItinerary, UserSavedPlace
from app.schemas.trip_day import DayType, TripDayRead, TripDayUpdate
from app.services.trip_service import (
    TripServiceError,
    TripServiceNotFoundError,
)


class TripDayError(TripServiceError):
    pass


class TripDayNotFoundError(TripDayError, TripServiceNotFoundError):
    pass


class TripDayValidationError(TripDayError):
    pass


class TripDayService:
    """Service managing individual trip day configurations and date reconciliations."""

    def create_default_trip_days(
        self,
        session: Session,
        trip_id: UUID,
        start_date: date,
        total_days: int,
    ) -> list[TripDay]:
        """Generate default sequential TripDay records for a new or unconfigured trip."""
        days: list[TripDay] = []
        for day_idx in range(1, total_days + 1):
            day_date = start_date + timedelta(days=day_idx - 1)
            day = TripDay(
                trip_id=trip_id,
                day_number=day_idx,
                date=day_date,
                day_type=DayType.FULL_DAY.value,
                start_time=DEFAULT_DAY_START_TIME,
                end_time=DEFAULT_DAY_END_TIME,
            )
            session.add(day)
            days.append(day)
        session.flush()
        return days

    def get_trip_days(self, session: Session, trip_id: UUID) -> list[TripDayRead]:
        """Retrieve all days belonging to a trip ordered by day_number with backwards-compatible backfill."""
        trip = session.get(Trip, trip_id)
        if trip is None:
            raise TripServiceNotFoundError("Trip not found.")

        days = session.exec(
            select(TripDay)
            .where(TripDay.trip_id == trip_id)
            .order_by(TripDay.day_number)
        ).all()

        if not days and trip.start_date is not None and trip.days > 0:
            days = self.create_default_trip_days(
                session, trip.id, trip.start_date, trip.days
            )
            session.commit()

        return [self._to_trip_day_read(d) for d in days]

    def update_trip_day(
        self,
        session: Session,
        trip_id: UUID,
        day_number: int,
        request: TripDayUpdate,
    ) -> TripDayRead:
        """Update day configuration (day type, touring start/end times) for a single day."""
        trip = session.get(Trip, trip_id)
        if trip is None:
            raise TripServiceNotFoundError("Trip not found.")

        day = session.exec(
            select(TripDay).where(
                TripDay.trip_id == trip_id,
                TripDay.day_number == day_number,
            )
        ).first()

        if day is None:
            raise TripDayNotFoundError(
                f"Day {day_number} not found for trip."
            )

        # Check for locked places if day is becoming REST or losing usable sightseeing window
        will_be_rest = (request.day_type == DayType.REST)
        prospective_start = (
            request.start_time
            if "start_time" in request.model_fields_set
            else day.start_time
        )
        prospective_end = (
            request.end_time
            if "end_time" in request.model_fields_set
            else day.end_time
        )
        if (
            request.day_type == DayType.REST
            and "start_time" not in request.model_fields_set
            and "end_time" not in request.model_fields_set
        ):
            prospective_start = None
            prospective_end = None

        has_usable_window = (
            prospective_start is not None
            and prospective_end is not None
            and prospective_end > prospective_start
        )

        if will_be_rest or not has_usable_window:
            locked_places = session.exec(
                select(UserSavedPlace).where(
                    UserSavedPlace.trip_id == trip_id,
                    UserSavedPlace.assigned_day_id == day.id,
                    UserSavedPlace.assignment_mode == "LOCKED",
                )
            ).all()
            if locked_places:
                count = len(locked_places)
                plural = f"{count} places are" if count > 1 else "1 place is"
                if will_be_rest:
                    raise TripDayValidationError(
                        f"Day {day_number} cannot be changed to REST because {plural} locked to this day. Move or unlock those places first."
                    )
                else:
                    raise TripDayValidationError(
                        f"Day {day_number} cannot have its sightseeing window removed because {plural} locked to this day. Move or unlock those places first."
                    )

        if request.day_type is not None:
            day.day_type = request.day_type.value
            # REST days default to having no sightseeing window if times are not explicitly set
            if (
                request.day_type == DayType.REST
                and "start_time" not in request.model_fields_set
                and "end_time" not in request.model_fields_set
            ):
                day.start_time = None
                day.end_time = None

        if "start_time" in request.model_fields_set:
            day.start_time = request.start_time
        if "end_time" in request.model_fields_set:
            day.end_time = request.end_time

        if day.start_time is not None and day.end_time is not None:
            if day.end_time <= day.start_time:
                raise TripDayValidationError(
                    "End time must be after start time."
                )

        try:
            session.add(day)
            session.commit()
            session.refresh(day)
        except Exception:
            session.rollback()
            raise

        return self._to_trip_day_read(day)

    def reconcile_trip_days_on_date_change(
        self,
        session: Session,
        trip: Trip,
        new_start_date: date,
        new_days: int,
    ) -> None:
        """Safely synchronize TripDay records when trip start_date or days count changes."""
        existing_days = session.exec(
            select(TripDay)
            .where(TripDay.trip_id == trip.id)
            .order_by(TripDay.day_number)
        ).all()
        existing_by_num = {d.day_number: d for d in existing_days}

        if any(d.day_number > new_days for d in existing_days):
            # Check if any scheduled visits exist on days that would be removed
            conflicting_itineraries = session.exec(
                select(TripItinerary).where(
                    TripItinerary.trip_id == trip.id,
                    TripItinerary.day_number > new_days,
                )
            ).all()
            if conflicting_itineraries:
                conflicting_days = sorted(
                    {i.day_number for i in conflicting_itineraries}
                )
                days_str = ", ".join(f"Day {d}" for d in conflicting_days)
                raise TripServiceError(
                    f"Cannot reduce trip duration to {new_days} days because {days_str} "
                    "contains scheduled place visits. Re-plan or remove scheduled visits first."
                )

            # Check if any places are locked to days that would be removed
            removed_day_ids = [d.id for d in existing_days if d.day_number > new_days]
            conflicting_saved_places = session.exec(
                select(UserSavedPlace).where(
                    UserSavedPlace.trip_id == trip.id,
                    UserSavedPlace.assignment_mode == "LOCKED",
                    UserSavedPlace.assigned_day_id.in_(removed_day_ids),
                )
            ).all()
            if conflicting_saved_places:
                day_id_to_num = {d.id: d.day_number for d in existing_days}
                conflicting_day_nums = sorted(
                    {
                        day_id_to_num[sp.assigned_day_id]
                        for sp in conflicting_saved_places
                        if sp.assigned_day_id in day_id_to_num
                    }
                )
                days_str = ", ".join(f"Day {d}" for d in conflicting_day_nums)
                count = len(conflicting_saved_places)
                plural = f"{count} places" if count > 1 else "1 place"
                raise TripServiceError(
                    f"Cannot reduce trip duration to {new_days} days because {days_str} "
                    f"has {plural} locked to it. Move or unlock those places first."
                )

            # Safe to remove obsolete day records
            session.exec(
                delete(TripDay).where(
                    TripDay.trip_id == trip.id,
                    TripDay.day_number > new_days,
                )
            )
            existing_days = [d for d in existing_days if d.day_number <= new_days]
            existing_by_num = {d.day_number: d for d in existing_days}

        # If trip duration expanded or has no days yet, create newly required days
        if not existing_days:
            for d in range(1, new_days + 1):
                day_date = new_start_date + timedelta(days=d - 1)
                new_day = TripDay(
                    trip_id=trip.id,
                    day_number=d,
                    date=day_date,
                    day_type=DayType.FULL_DAY.value,
                    start_time=DEFAULT_DAY_START_TIME,
                    end_time=DEFAULT_DAY_END_TIME,
                )
                session.add(new_day)
        elif new_days > len(existing_by_num):
            for d in range(len(existing_by_num) + 1, new_days + 1):
                day_date = new_start_date + timedelta(days=d - 1)
                new_day = TripDay(
                    trip_id=trip.id,
                    day_number=d,
                    date=day_date,
                    day_type=DayType.FULL_DAY.value,
                    start_time=DEFAULT_DAY_START_TIME,
                    end_time=DEFAULT_DAY_END_TIME,
                )
                session.add(new_day)

        # Update dates for all remaining days while preserving day_type and touring windows
        for d, trip_day in existing_by_num.items():
            if d <= new_days:
                trip_day.date = new_start_date + timedelta(days=d - 1)
                session.add(trip_day)

        session.flush()

    @staticmethod
    def _to_trip_day_read(day: TripDay) -> TripDayRead:
        return TripDayRead(
            id=day.id,
            trip_id=day.trip_id,
            day_number=day.day_number,
            date=day.date,
            day_type=DayType(day.day_type),
            start_time=day.start_time,
            end_time=day.end_time,
            created_at=day.created_at,
        )

