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
from app.services.itinerary_timing_service import ItineraryTimingService
from app.services.route_matrix_service import (
    RouteMatrixProvider,
    RouteMatrixService,
    RouteNode,
)

MAX_SELECTED_PLACES = 24


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

        timing_service = ItineraryTimingService()
        try:
            schedule_result = timing_service.schedule_itinerary(
                start_node=start,
                place_nodes=place_nodes,
                places=places,
                saved_rows=saved_rows,
                ordered_indices=optimized_indices,
                matrix=matrix,
                trip_days=trip.days,
                start_date=trip.start_date,
            )
        except ValueError as exc:
            raise RouteValidationError(str(exc)) from exc

        session.exec(delete(TripItinerary).where(TripItinerary.trip_id == trip_id))
        for item in schedule_result.optimized_places:
            session.add(
                TripItinerary(
                    trip_id=trip_id,
                    place_id=item.place_id,
                    day_number=item.day_number,
                    visit_order=item.visit_order,
                    planned_arrival_time=item.planned_arrival_time,
                    planned_departure_time=item.planned_departure_time,
                    distance_from_previous=item.distance_from_previous,
                    travel_time_minutes=item.travel_time_minutes,
                )
            )
        session.commit()

        return RouteOptimizationRead(
            trip_id=trip_id,
            optimized_places=schedule_result.optimized_places,
            total_distance=round(schedule_result.total_distance_meters / 1000, 3),
            total_travel_time_minutes=schedule_result.total_travel_minutes,
            breaks=schedule_result.breaks,
            conflicts=schedule_result.conflicts,
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
