"""Read persisted planner constraints without enrichment or writes (also for previews)."""

from datetime import date, timedelta
from uuid import UUID

from sqlmodel import Session, select

from app.core.itinerary_constants import DEFAULT_DAY_END_TIME, DEFAULT_DAY_START_TIME
from app.models.entities import Place, PlaceOpeningHours, Trip, TripDay


def load_planner_inputs(
    session: Session, trip: Trip, places: list[Place]
) -> tuple[list[TripDay], dict[UUID, dict[int, PlaceOpeningHours]]]:
    base_date = trip.start_date or date.today()  # noqa: DTZ011 - legacy local date
    days = list(
        session.exec(
            select(TripDay)
            .where(TripDay.trip_id == trip.id)
            .order_by(TripDay.day_number)
        ).all()
    )
    # Legacy trips without ANY TripDays use the previous defaults. Never fill in
    # missing days of a partially configured trip or override explicit null windows.
    if not days:
        days = [
            TripDay(
                trip_id=trip.id,
                day_number=n + 1,
                date=base_date + timedelta(days=n),
                start_time=DEFAULT_DAY_START_TIME,
                end_time=DEFAULT_DAY_END_TIME,
            )
            for n in range(trip.days)
        ]
    rows = session.exec(
        select(PlaceOpeningHours).where(
            PlaceOpeningHours.place_id.in_([p.id for p in places])
        )
    ).all()
    weekly: dict[UUID, dict[int, PlaceOpeningHours]] = {}
    for row in rows:
        weekly.setdefault(row.place_id, {})[row.day_of_week] = row
    return days, weekly
