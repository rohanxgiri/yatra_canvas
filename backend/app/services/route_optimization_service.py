"""Constraint-aware, explainable trip route optimization with OR-Tools VRPTW solver."""

from __future__ import annotations

from typing import TYPE_CHECKING
from uuid import UUID, uuid4

from sqlalchemy import delete, insert
from sqlmodel import Session, select

from app.models import Place, Trip, TripItinerary, UserSavedPlace
from app.schemas import RouteOptimizationRead
from app.services.google_routes_service import (
    GoogleRoutesUnavailableError,
    RouteMatrixLeg,
)
from app.services.itinerary_timing_service import (
    PlaceOpeningHours,
)
from app.services.planner_inputs import load_planner_inputs
from app.services.route_matrix_service import (
    RouteMatrixProvider,
    RouteMatrixService,
    RouteNode,
)
from app.services.vrptw_solver_service import VrptwSolverService

if TYPE_CHECKING:
    from app.services.route_geometry_service import (
        RouteGeometryProvider,
        RouteGeometryService,
    )

MAX_SELECTED_PLACES = 50


class RouteOptimizationError(Exception):
    pass


class RouteTripNotFoundError(RouteOptimizationError):
    pass


class RouteValidationError(RouteOptimizationError):
    pass


class RouteOptimizationService:
    """Use cached route estimates while respecting user constraints via OR-Tools VRPTW solver."""

    async def optimize(
        self,
        session: Session,
        trip_id: UUID,
        route_provider: RouteMatrixProvider,
        route_matrix: RouteMatrixService,
        *,
        geometry_service: RouteGeometryService | None = None,
        geometry_provider: RouteGeometryProvider | None = None,
        opening_hours_map: dict[UUID, PlaceOpeningHours] | None = None,
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
        if len(saved_rows) > MAX_SELECTED_PLACES:
            raise RouteValidationError(
                f"Route optimization currently supports up to {MAX_SELECTED_PLACES} selected places."
            )

        place_ids = [saved.place_id for saved in saved_rows]
        places_by_id = {
            place.id: place
            for place in session.exec(
                select(Place).where(Place.id.in_(place_ids))  # type: ignore[attr-defined]
            ).all()
        }
        places: list[Place] = []
        for saved in saved_rows:
            place = places_by_id.get(saved.place_id)
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

        # Use Google OR-Tools VRPTW solver
        day_configs, weekly_hours = load_planner_inputs(session, trip, places)
        vrptw_solver = VrptwSolverService()
        try:
            solution = vrptw_solver.solve(
                start_node=start,
                place_nodes=place_nodes,
                places=places,
                saved_rows=saved_rows,
                matrix=matrix,
                trip_days=trip.days,
                day_configs=day_configs,
                weekly_hours_map=weekly_hours,
                start_date=trip.start_date,
                opening_hours_map=opening_hours_map,
            )
            scheduled_places = solution.optimized_places
            breaks = solution.breaks
            conflicts = solution.conflicts
            total_dist_meters = solution.total_distance_meters
            total_travel_mins = solution.total_travel_minutes
        except ValueError as exc:
            # Propagate validation errors
            raise RouteValidationError(str(exc)) from exc

        session.exec(
            delete(TripItinerary).where(
                TripItinerary.trip_id == trip_id  # type: ignore[arg-type]
            )
        )
        if scheduled_places:
            itinerary_values = []
            for item in scheduled_places:
                stop_id = uuid4()
                item.id = stop_id
                item.status = "PLANNED"
                itinerary_values.append(
                    {
                        "id": stop_id,
                        "trip_id": trip_id,
                        "place_id": item.place_id,
                        "day_number": item.day_number,
                        "visit_order": item.visit_order,
                        "planned_arrival_time": item.planned_arrival_time,
                        "planned_departure_time": item.planned_departure_time,
                        "distance_from_previous": item.distance_from_previous,
                        "travel_time_minutes": item.travel_time_minutes,
                        "status": "PLANNED",
                    }
                )
            session.execute(insert(TripItinerary).values(itinerary_values))
        session.commit()


        # Fetch route geometry for final route if provider is available
        route_geometry = None
        if geometry_service is not None and geometry_provider is not None:
            try:
                route_geometry = await geometry_service.get_trip_geometry(
                    session=session,
                    trip_id=trip_id,
                    provider=geometry_provider,
                )
            except Exception:
                # Degradation: route geometry failure does not break the optimized itinerary
                route_geometry = None

        return RouteOptimizationRead(
            trip_id=trip_id,
            optimized_places=scheduled_places,
            total_distance=round(total_dist_meters / 1000, 3),
            total_travel_time_minutes=total_travel_mins,
            total_days=trip.days,
            breaks=breaks,
            conflicts=conflicts,
            unscheduled_places=solution.unscheduled_places,
            route_geometry=route_geometry,
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
