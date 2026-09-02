"""Constraint-aware, explainable V1 trip route optimization."""

from math import ceil
from uuid import UUID

from sqlalchemy import delete
from sqlmodel import Session, select

from app.models import Place, Trip, TripItinerary, UserSavedPlace
from app.schemas import OptimizedPlaceRead, RouteOptimizationRead
from app.services.google_routes_service import (
    GoogleRoutesUnavailableError,
    RouteMatrixLeg,
)
from app.services.route_matrix_service import (
    RouteMatrixProvider,
    RouteMatrixService,
    RouteNode,
)

MAX_SELECTED_PLACES = 24
DEFAULT_VISIT_DURATION_MINUTES = 120
DEFAULT_DAILY_BUDGET_MINUTES = 600


class RouteOptimizationError(Exception):
    pass


class RouteTripNotFoundError(RouteOptimizationError):
    pass


class RouteValidationError(RouteOptimizationError):
    pass


class RouteOptimizationService:
    """Use cached route estimates while respecting user constraints."""

    async def optimize(
        self,
        session: Session,
        trip_id: UUID,
        route_provider: RouteMatrixProvider,
        route_matrix: RouteMatrixService,
    ) -> RouteOptimizationRead:
        trip = session.get(Trip, trip_id)
        if trip is None:
            raise RouteTripNotFoundError("Trip not found.")
        if (
            not trip.start_location_type
            or not trip.start_location_name
            or trip.start_latitude is None
            or trip.start_longitude is None
        ):
            raise RouteValidationError(
                "Select a trip start location before route optimization."
            )

        saved_rows = list(
            session.exec(
                select(UserSavedPlace).where(UserSavedPlace.trip_id == trip_id)
            ).all()
        )
        saved_rows.sort(
            key=lambda row: (
                row.custom_order is None,
                row.custom_order if row.custom_order is not None else 0,
                str(row.id),
            )
        )
        if len(saved_rows) < trip.days:
            raise RouteValidationError(
                f"Select at least {trip.days} places (one per day) before optimizing the route."
            )
        if len(saved_rows) > MAX_SELECTED_PLACES:
            raise RouteValidationError(
                f"Route optimization currently supports up to {MAX_SELECTED_PLACES} selected places."
            )

        places: list[Place] = []
        for saved in saved_rows:
            place = session.get(Place, saved.place_id)
            if place is None:
                raise RouteValidationError(
                    "A selected place no longer exists. Remove it and try again."
                )
            places.append(place)

        try:
            start, place_nodes, matrix = await route_matrix.get_complete_matrix(
                session,
                trip,
                places,
                route_provider,
            )
        except ValueError as exc:
            raise RouteValidationError(str(exc)) from exc
        optimized_indices = self._constraint_aware_order(
            start,
            place_nodes,
            matrix,
            saved_rows,
        )

        optimized_places: list[OptimizedPlaceRead] = []
        current_node = start
        total_distance_meters = 0
        total_minutes = 0

        day_number = 1
        visit_order_on_day = 0
        daily_minutes_used = 0
        dropped_place_indices: list[int] = []

        for place_index in optimized_indices:
            destination = place_nodes[place_index]
            leg = matrix.get((current_node.key, destination.key))
            if leg is None:
                leg = matrix[(start.key, destination.key)]
            
            travel_minutes = ceil(leg.preferred_duration_seconds / 60)
            expected_addition = travel_minutes + DEFAULT_VISIT_DURATION_MINUTES

            # Check if we should move to the next day
            if (
                visit_order_on_day > 0
                and daily_minutes_used + expected_addition > DEFAULT_DAILY_BUDGET_MINUTES
            ):
                day_number += 1
                if day_number > trip.days:
                    # We ran out of days, the rest of the places are dropped
                    dropped_place_indices.append(place_index)
                    continue
                
                daily_minutes_used = 0
                current_node = start
                visit_order_on_day = 0
                
                leg = matrix.get((start.key, destination.key))
                if leg is None:
                    raise RouteValidationError("A place is unreachable from the start location.")
                travel_minutes = ceil(leg.preferred_duration_seconds / 60)
                expected_addition = travel_minutes + DEFAULT_VISIT_DURATION_MINUTES

            # If we are dropping because we already ran out of days
            if day_number > trip.days:
                dropped_place_indices.append(place_index)
                continue

            visit_order_on_day += 1
            daily_minutes_used += expected_addition

            distance_km = round(leg.distance_meters / 1000, 3)
            place = places[place_index]
            optimized_places.append(
                OptimizedPlaceRead(
                    place_id=place.id,
                    name=place.name,
                    day_number=day_number,
                    visit_order=visit_order_on_day,
                    distance_from_previous=distance_km,
                    travel_time_minutes=travel_minutes,
                )
            )
            total_distance_meters += leg.distance_meters
            total_minutes += travel_minutes
            current_node = destination

        for dropped_idx in dropped_place_indices:
            if saved_rows[dropped_idx].must_visit:
                raise RouteValidationError("Cannot fit all must-visit places within the trip duration.")

        session.exec(delete(TripItinerary).where(TripItinerary.trip_id == trip_id))
        for item in optimized_places:
            session.add(
                TripItinerary(
                    trip_id=trip_id,
                    place_id=item.place_id,
                    day_number=item.day_number,
                    visit_order=item.visit_order,
                    planned_arrival_time=None,
                    planned_departure_time=None,
                    distance_from_previous=item.distance_from_previous,
                    travel_time_minutes=item.travel_time_minutes,
                )
            )
        session.commit()

        return RouteOptimizationRead(
            trip_id=trip_id,
            optimized_places=optimized_places,
            total_distance=round(total_distance_meters / 1000, 3),
            total_travel_time_minutes=total_minutes,
        )

    @staticmethod
    def _constraint_aware_order(
        start: RouteNode,
        place_nodes: list[RouteNode],
        matrix: dict[tuple[str, str], RouteMatrixLeg],
        saved_rows: list[UserSavedPlace],
    ) -> list[int]:
        locked_slots: dict[int, int] = {}
        for index, saved in enumerate(saved_rows):
            if not saved.is_locked:
                continue
            if saved.custom_order is None:
                raise RouteValidationError(
                    "Locked places require a custom_order position."
                )
            slot = saved.custom_order - 1
            if slot < 0 or slot >= len(saved_rows):
                raise RouteValidationError(
                    "A locked place has an invalid custom_order position."
                )
            if slot in locked_slots:
                raise RouteValidationError(
                    "Two locked places cannot use the same custom_order position."
                )
            locked_slots[slot] = index

        locked_indices = set(locked_slots.values())
        unvisited = set(range(len(saved_rows)))
        result: list[int] = []
        current = start
        for slot in range(len(saved_rows)):
            if slot in locked_slots:
                place_index = locked_slots[slot]
            else:
                candidates: list[tuple[bool, int, int, int, int, str, int]] = []
                for candidate_index in unvisited - locked_indices:
                    destination = place_nodes[candidate_index]
                    leg = matrix.get((current.key, destination.key))
                    if leg is None:
                        continue
                    saved = saved_rows[candidate_index]
                    candidates.append(
                        (
                            not saved.must_visit,
                            -saved.priority,
                            leg.preferred_duration_seconds,
                            leg.distance_meters,
                            saved.custom_order or len(saved_rows) + 1,
                            str(saved.place_id),
                            candidate_index,
                        )
                    )
                if not candidates:
                    raise GoogleRoutesUnavailableError(
                        "The route constraints could not connect every selected place."
                    )
                place_index = min(candidates)[-1]

            if place_index not in unvisited:
                raise RouteValidationError("Locked place positions conflict.")
            result.append(place_index)
            unvisited.remove(place_index)
            current = place_nodes[place_index]
        return result
