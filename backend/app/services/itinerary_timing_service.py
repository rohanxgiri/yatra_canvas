"""Time-aware scheduling engine with opening-hours awareness and midday breaks.

Calculates realistic, sequential touring timetables respecting travel times,
deterministic category visit durations, daily time budgets, and opening hours
when available.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from math import ceil
from typing import Final
from uuid import UUID

from app.core.itinerary_constants import (
    DEFAULT_DAY_END_TIME,
    DEFAULT_DAY_START_TIME,
    DEFAULT_LUNCH_BREAK_MINUTES,
    LUNCH_BREAK_EARLIEST_START,
    LUNCH_BREAK_LATEST_START,
    MIN_TRAVEL_BUFFER_MINUTES,
    estimate_visit_duration,
)
from app.models.entities import Place, UserSavedPlace
from app.schemas.route_optimization import ItineraryBreakRead, OptimizedPlaceRead
from app.services.route_matrix_service import RouteMatrixLeg, RouteNode


@dataclass(frozen=True, slots=True)
class PlaceOpeningHours:
    """Normalized opening hours model for a place."""
    open_time: time
    close_time: time
    closed_days: tuple[int, ...] = ()  # 0=Monday, 6=Sunday


@dataclass(frozen=True, slots=True)
class ScheduledItineraryResult:
    optimized_places: list[OptimizedPlaceRead]
    breaks: list[ItineraryBreakRead]
    conflicts: list[str]
    total_distance_meters: int
    total_travel_minutes: int


class ItineraryTimingService:
    """Computes realistic itinerary schedules with time windows and conflict checks."""

    def __init__(
        self,
        day_start_time: time = DEFAULT_DAY_START_TIME,
        day_end_time: time = DEFAULT_DAY_END_TIME,
    ) -> None:
        self.day_start_time = day_start_time
        self.day_end_time = day_end_time

    def schedule_itinerary(
        self,
        start_node: RouteNode,
        place_nodes: list[RouteNode],
        places: list[Place],
        saved_rows: list[UserSavedPlace],
        ordered_indices: list[int],
        matrix: dict[tuple[str, str], RouteMatrixLeg],
        trip_days: int,
        start_date: date | None = None,
        opening_hours_map: dict[UUID, PlaceOpeningHours] | None = None,
    ) -> ScheduledItineraryResult:
        base_date = start_date or date.today()
        opening_hours = opening_hours_map or {}

        scheduled_places: list[OptimizedPlaceRead] = []
        breaks: list[ItineraryBreakRead] = []
        conflicts: list[str] = []
        total_distance_meters = 0
        total_travel_minutes = 0

        day_number = 1
        current_date = base_date
        current_node = start_node
        current_time = datetime.combine(current_date, self.day_start_time)
        day_end_datetime = datetime.combine(current_date, self.day_end_time)
        visit_order_on_day = 0
        lunch_taken = False

        for place_index in ordered_indices:
            destination = place_nodes[place_index]
            place = places[place_index]
            saved = saved_rows[place_index]
            visit_duration = estimate_visit_duration(place.category)

            # Look up routing leg from current_node to destination
            leg = matrix.get((current_node.key, destination.key))
            if leg is None:
                leg = matrix.get((start_node.key, destination.key))
            if leg is None:
                raise ValueError(f"Place '{place.name}' is unreachable.")

            travel_minutes = ceil(leg.preferred_duration_seconds / 60)
            if travel_minutes < MIN_TRAVEL_BUFFER_MINUTES and visit_order_on_day > 0:
                travel_minutes = MIN_TRAVEL_BUFFER_MINUTES

            estimated_arrival = current_time + timedelta(minutes=travel_minutes)
            hours = opening_hours.get(place.id)

            # Check if arrival occurs during lunch window (12:30 - 14:00)
            if not lunch_taken and visit_order_on_day > 0:
                lunch_start_dt = datetime.combine(current_date, LUNCH_BREAK_EARLIEST_START)
                if current_time >= lunch_start_dt or estimated_arrival >= lunch_start_dt:
                    # Insert a midday break before this next stop
                    break_start_time = max(current_time.time(), LUNCH_BREAK_EARLIEST_START)
                    break_start_dt = datetime.combine(current_date, break_start_time)
                    break_end_dt = break_start_dt + timedelta(minutes=DEFAULT_LUNCH_BREAK_MINUTES)

                    breaks.append(
                        ItineraryBreakRead(
                            day_number=day_number,
                            start_time=break_start_dt.time(),
                            end_time=break_end_dt.time(),
                            duration_minutes=DEFAULT_LUNCH_BREAK_MINUTES,
                            label="Midday Break / Lunch",
                        )
                    )
                    current_time = break_end_dt
                    estimated_arrival = current_time + timedelta(minutes=travel_minutes)
                    lunch_taken = True

            # Check opening hours adjustments
            if hours is not None:
                # 1. Closed day check
                if current_date.weekday() in hours.closed_days:
                    conflicts.append(
                        f"'{place.name}' is closed on {current_date.strftime('%A')}."
                    )
                # 2. Opens later: delay arrival to opening time
                open_dt = datetime.combine(current_date, hours.open_time)
                if estimated_arrival < open_dt:
                    estimated_arrival = open_dt

            estimated_departure = estimated_arrival + timedelta(minutes=visit_duration)

            # Check closing hour
            if hours is not None:
                close_dt = datetime.combine(current_date, hours.close_time)
                if estimated_departure > close_dt:
                    conflicts.append(
                        f"'{place.name}' closes at {hours.close_time.strftime('%I:%M %p')} before visit can finish."
                    )

            # Check if this stop exceeds the daily touring end time
            if visit_order_on_day > 0 and estimated_departure > day_end_datetime:
                # Overflow to next day if available
                day_number += 1
                if day_number > trip_days:
                    if saved.must_visit:
                        raise ValueError(
                            "Cannot fit all must-visit places within the trip duration."
                        )
                    conflicts.append(
                        f"'{place.name}' cannot fit within Day {day_number - 1} touring hours."
                    )
                    continue

                # Reset state for the new day
                current_date = base_date + timedelta(days=day_number - 1)
                current_node = start_node
                current_time = datetime.combine(current_date, self.day_start_time)
                day_end_datetime = datetime.combine(current_date, self.day_end_time)
                visit_order_on_day = 0
                lunch_taken = False

                # Recalculate leg from start_node for day start
                leg = matrix.get((start_node.key, destination.key))
                if leg is None:
                    raise ValueError(f"Place '{place.name}' is unreachable from start.")
                travel_minutes = ceil(leg.preferred_duration_seconds / 60)
                estimated_arrival = current_time + timedelta(minutes=travel_minutes)

                if hours is not None:
                    open_dt = datetime.combine(current_date, hours.open_time)
                    if estimated_arrival < open_dt:
                        estimated_arrival = open_dt

                estimated_departure = estimated_arrival + timedelta(minutes=visit_duration)

            # If day_number already exceeded trip days
            if day_number > trip_days:
                if saved.must_visit:
                    raise ValueError(
                        "Cannot fit all must-visit places within the trip duration."
                    )
                conflicts.append(
                    f"'{place.name}' cannot fit within available trip days."
                )
                continue

            visit_order_on_day += 1
            distance_km = round(leg.distance_meters / 1000, 3)

            scheduled_places.append(
                OptimizedPlaceRead(
                    place_id=place.id,
                    name=place.name,
                    day_number=day_number,
                    visit_order=visit_order_on_day,
                    distance_from_previous=distance_km,
                    travel_time_minutes=travel_minutes,
                    planned_arrival_time=estimated_arrival.time(),
                    planned_departure_time=estimated_departure.time(),
                    visit_duration_minutes=visit_duration,
                    is_opening_hours_known=hours is not None,
                )
            )

            total_distance_meters += leg.distance_meters
            total_travel_minutes += travel_minutes

            current_time = estimated_departure
            current_node = destination

            # Check if stop finished during lunch window and lunch was not yet taken
            if (
                not lunch_taken
                and LUNCH_BREAK_EARLIEST_START <= current_time.time() <= LUNCH_BREAK_LATEST_START
            ):
                break_start_time = current_time.time()
                break_start_dt = datetime.combine(current_date, break_start_time)
                break_end_dt = break_start_dt + timedelta(minutes=DEFAULT_LUNCH_BREAK_MINUTES)
                breaks.append(
                    ItineraryBreakRead(
                        day_number=day_number,
                        start_time=break_start_time,
                        end_time=break_end_dt.time(),
                        duration_minutes=DEFAULT_LUNCH_BREAK_MINUTES,
                        label="Midday Break / Lunch",
                    )
                )
                current_time = break_end_dt
                lunch_taken = True

        return ScheduledItineraryResult(
            optimized_places=scheduled_places,
            breaks=breaks,
            conflicts=conflicts,
            total_distance_meters=total_distance_meters,
            total_travel_minutes=total_travel_minutes,
        )
