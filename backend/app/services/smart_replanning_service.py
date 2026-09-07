"""Centralized smart trip re-planning service and invalidation engine.

Determines stale planning data, reuses valid directional RouteMatrixCache legs,
generates non-persisted re-plan previews, and transactionally updates itineraries
upon user confirmation.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Literal
from uuid import UUID, uuid4

from sqlalchemy import delete, or_
from sqlmodel import Session, select

from app.core.itinerary_constants import estimate_visit_duration
from app.models.entities import (
    Place,
    RouteMatrixCache,
    Trip,
    TripDay,
    TripItinerary,
    UserSavedPlace,
)
from app.schemas.route_optimization import (
    OptimizedPlaceRead,
    RouteOptimizationRead,
)
from app.schemas.smart_replanning import (
    ItineraryStopStatus,
    ItineraryStopStatusUpdate,
    MoveItineraryPlaceRequest,
    MoveItineraryPlaceResponse,
    MovedPlaceRead,
    TripReplanImpactRead,
    TripReplanPreviewRead,
)
from app.services.planner_inputs import load_planner_inputs
from app.services.route_matrix_service import (
    RouteMatrixProvider,
    RouteMatrixService,
    RouteNode,
)
from app.services.route_optimization_service import (
    MAX_SELECTED_PLACES,
    RouteOptimizationError,
    RouteOptimizationService,
    RouteTripNotFoundError,
    RouteValidationError,
)
from app.services.vrptw_solver_service import VrptwSolverService


class ItineraryStopNotFoundError(RouteOptimizationError):
    pass


class TripChangeType(str, Enum):
    ADD_PLACE = "add_place"
    REMOVE_PLACE = "remove_place"
    REORDER_PLACES = "reorder_places"
    UPDATE_PRIORITY = "update_priority"
    UPDATE_MUST_VISIT = "update_must_visit"
    UPDATE_LOCKED = "update_locked"
    UPDATE_NOTES = "update_notes"
    UPDATE_START_LOCATION = "update_start_location"
    UPDATE_DATES = "update_dates"
    UPDATE_DAYS = "update_days"
    UPDATE_PREFERENCES = "update_preferences"
    UPDATE_CITY = "update_city"


@dataclass(frozen=True, slots=True)
class TripChangeImpact:
    change_type: TripChangeType
    itinerary_stale: bool
    route_matrix_stale: bool
    matrix_purge_scope: Literal["none", "start_only", "all"]
    route_geometry_stale: bool
    weather_advisory_stale: bool
    recommendations_stale: bool
    requires_replan_preview: bool
    summary: str


def evaluate_change_impact(change_type: TripChangeType) -> TripChangeImpact:
    """Return deterministic invalidation impact for a specific trip change."""
    if change_type == TripChangeType.UPDATE_NOTES:
        return TripChangeImpact(

            change_type=change_type,
            itinerary_stale=False,
            route_matrix_stale=False,
            matrix_purge_scope="none",
            route_geometry_stale=False,
            weather_advisory_stale=False,
            recommendations_stale=False,
            requires_replan_preview=False,
            summary="Place notes updated. No itinerary re-planning required.",
        )

    if change_type == TripChangeType.ADD_PLACE:
        return TripChangeImpact(
            change_type=change_type,
            itinerary_stale=True,
            route_matrix_stale=True,
            matrix_purge_scope="none",
            route_geometry_stale=True,
            weather_advisory_stale=True,
            recommendations_stale=False,
            requires_replan_preview=True,
            summary="Place added. Itinerary needs optimization to schedule arrival time.",
        )

    if change_type == TripChangeType.REMOVE_PLACE:
        return TripChangeImpact(
            change_type=change_type,
            itinerary_stale=True,
            route_matrix_stale=False,
            matrix_purge_scope="none",
            route_geometry_stale=True,
            weather_advisory_stale=True,
            recommendations_stale=False,
            requires_replan_preview=True,
            summary="Place removed. Itinerary needs update to close travel gaps.",
        )

    if change_type == TripChangeType.REORDER_PLACES:
        return TripChangeImpact(
            change_type=change_type,
            itinerary_stale=True,
            route_matrix_stale=False,
            matrix_purge_scope="none",
            route_geometry_stale=True,
            weather_advisory_stale=False,
            recommendations_stale=False,
            requires_replan_preview=True,
            summary="Custom place order changed. Itinerary recalculation required.",
        )

    if change_type in (TripChangeType.UPDATE_PRIORITY, TripChangeType.UPDATE_MUST_VISIT):
        return TripChangeImpact(
            change_type=change_type,
            itinerary_stale=True,
            route_matrix_stale=False,
            matrix_purge_scope="none",
            route_geometry_stale=True,
            weather_advisory_stale=False,
            recommendations_stale=False,
            requires_replan_preview=True,
            summary="Place priority or must-visit constraint modified.",
        )

    if change_type == TripChangeType.UPDATE_LOCKED:
        return TripChangeImpact(
            change_type=change_type,
            itinerary_stale=True,
            route_matrix_stale=False,
            matrix_purge_scope="none",
            route_geometry_stale=True,
            weather_advisory_stale=False,
            recommendations_stale=False,
            requires_replan_preview=True,
            summary="Place lock status updated.",
        )

    if change_type == TripChangeType.UPDATE_START_LOCATION:
        return TripChangeImpact(
            change_type=change_type,
            itinerary_stale=True,
            route_matrix_stale=True,
            matrix_purge_scope="start_only",
            route_geometry_stale=True,
            weather_advisory_stale=False,
            recommendations_stale=False,
            requires_replan_preview=True,
            summary="Start location changed. Recalculating initial route legs.",
        )

    if change_type == TripChangeType.UPDATE_DATES:
        return TripChangeImpact(
            change_type=change_type,
            itinerary_stale=True,
            route_matrix_stale=False,
            matrix_purge_scope="none",
            route_geometry_stale=False,
            weather_advisory_stale=True,
            recommendations_stale=False,
            requires_replan_preview=False,
            summary="Trip dates updated. Weather forecasts flagged for re-check.",
        )

    if change_type == TripChangeType.UPDATE_DAYS:
        return TripChangeImpact(
            change_type=change_type,
            itinerary_stale=True,
            route_matrix_stale=False,
            matrix_purge_scope="none",
            route_geometry_stale=True,
            weather_advisory_stale=True,
            recommendations_stale=False,
            requires_replan_preview=True,
            summary="Trip duration changed. Places can be re-balanced across days.",
        )

    if change_type == TripChangeType.UPDATE_PREFERENCES:
        return TripChangeImpact(
            change_type=change_type,
            itinerary_stale=False,
            route_matrix_stale=False,
            matrix_purge_scope="none",
            route_geometry_stale=False,
            weather_advisory_stale=False,
            recommendations_stale=True,
            requires_replan_preview=False,
            summary="Travel preferences updated. New recommendations available.",
        )

    # TripChangeType.UPDATE_CITY
    return TripChangeImpact(
        change_type=change_type,
        itinerary_stale=True,
        route_matrix_stale=True,
        matrix_purge_scope="all",
        route_geometry_stale=True,
        weather_advisory_stale=True,
        recommendations_stale=True,
        requires_replan_preview=True,
        summary="Destination city changed. All route and itinerary data purged.",
    )


def purge_stale_matrix_cache(
    session: Session,
    trip_id: UUID,
    scope: Literal["none", "start_only", "all"],
) -> int:
    """Selectively purge stale legs from RouteMatrixCache preserving valid place-to-place pairs."""
    if scope == "none":
        return 0

    if scope == "all":
        result = session.exec(
            delete(RouteMatrixCache).where(RouteMatrixCache.trip_id == trip_id)
        )
        session.flush()
        return result.rowcount  # type: ignore[no-any-return]

    # scope == "start_only": purge ONLY legs to/from the trip start location
    result = session.exec(
        delete(RouteMatrixCache).where(
            RouteMatrixCache.trip_id == trip_id,
            or_(
                RouteMatrixCache.from_location_type == "start",
                RouteMatrixCache.to_location_type == "start",
            ),
        )
    )
    session.flush()
    return result.rowcount  # type: ignore[no-any-return]


class SmartReplanningService:
    """Orchestrates smart re-planning, preview diff generation, and atomic updates."""

    def check_itinerary_stale(
        self,
        session: Session,
        trip_id: UUID,
    ) -> TripReplanImpactRead:
        trip = session.get(Trip, trip_id)
        if trip is None:
            raise RouteTripNotFoundError("Trip not found.")

        saved_rows = list(
            session.exec(
                select(UserSavedPlace)
                .where(UserSavedPlace.trip_id == trip_id)
                .order_by(UserSavedPlace.custom_order)
            ).all()
        )
        itinerary_rows = list(
            session.exec(
                select(TripItinerary)
                .where(TripItinerary.trip_id == trip_id)
                .order_by(TripItinerary.day_number, TripItinerary.visit_order)
            ).all()
        )

        saved_ids = {s.place_id for s in saved_rows}
        itin_ids = {i.place_id for i in itinerary_rows}

        reasons: list[str] = []

        # 1. Unscheduled saved places
        missing_in_itin = saved_ids - itin_ids
        if missing_in_itin:
            reasons.append(
                f"{len(missing_in_itin)} saved place(s) are not yet scheduled in the itinerary."
            )

        # 2. Deleted places still in itinerary
        removed_from_saved = itin_ids - saved_ids
        if removed_from_saved:
            reasons.append(
                f"{len(removed_from_saved)} place(s) were removed from saved places but remain in the itinerary."
            )

        # 3. Exceeds trip days
        max_day = max((i.day_number for i in itinerary_rows), default=1)
        if max_day > trip.days:
            reasons.append(
                f"Itinerary spans {max_day} days, but trip is set to {trip.days} day(s)."
            )

        # 4. Locked places out of position
        itin_order_map = {i.place_id: i.visit_order for i in itinerary_rows if i.day_number == 1}
        for s in saved_rows:
            if s.is_locked and s.custom_order is not None and s.place_id in itin_order_map:
                if itin_order_map[s.place_id] != s.custom_order:
                    reasons.append(
                        "Locked place order is out of sync with scheduled visit order."
                    )
                    break

        is_stale = len(reasons) > 0
        summary = (
            "Itinerary is up to date."
            if not is_stale
            else "Itinerary is out of sync with your saved places or trip settings."
        )

        return TripReplanImpactRead(
            trip_id=trip_id,
            is_stale=is_stale,
            requires_replan_preview=is_stale,
            reasons=reasons,
            summary=summary,
        )

    async def get_replan_preview(
        self,
        session: Session,
        trip_id: UUID,
        route_provider: RouteMatrixProvider,
        route_matrix: RouteMatrixService,
    ) -> TripReplanPreviewRead:
        trip = session.get(Trip, trip_id)
        if trip is None:
            raise RouteTripNotFoundError("Trip not found.")

        saved_rows = list(
            session.exec(
                select(UserSavedPlace)
                .where(UserSavedPlace.trip_id == trip_id)
                .order_by(UserSavedPlace.custom_order)
            ).all()
        )
        current_itinerary = list(
            session.exec(
                select(TripItinerary)
                .where(TripItinerary.trip_id == trip_id)
                .order_by(TripItinerary.day_number, TripItinerary.visit_order)
            ).all()
        )

        all_place_ids = list(
            {s.place_id for s in saved_rows} | {i.place_id for i in current_itinerary}
        )
        places_list = list(
            session.exec(select(Place).where(Place.id.in_(all_place_ids))).all()  # type: ignore[union-attr]
        )
        places_by_id = {p.id: p for p in places_list}
        places = [places_by_id[s.place_id] for s in saved_rows if s.place_id in places_by_id]
        if len(places) != len(saved_rows):
            raise RouteValidationError("A selected place no longer exists. Remove it and try again.")
        if len(saved_rows) > MAX_SELECTED_PLACES:
            raise RouteValidationError(
                f"Route optimization currently supports up to {MAX_SELECTED_PLACES} selected places."
            )

        # Compute proposed schedule without persisting
        try:
            start, place_nodes, matrix = await route_matrix.get_complete_matrix(
                session,
                trip,
                places,
                route_provider,
            )
        except ValueError as exc:
            raise RouteValidationError(str(exc)) from exc

        day_configs, weekly_hours = load_planner_inputs(session, trip, places)
        solver = VrptwSolverService()
        try:
            schedule_result = solver.solve(
                start_node=start,
                place_nodes=place_nodes,
                places=places,
                saved_rows=saved_rows,
                matrix=matrix,
                trip_days=trip.days,
                day_configs=day_configs,
                weekly_hours_map=weekly_hours,
                start_date=trip.start_date,
            )
        except ValueError as exc:
            raise RouteValidationError(str(exc)) from exc

        # Calculate Diff
        current_by_pid = {i.place_id: i for i in current_itinerary}
        proposed_by_pid = {p.place_id: p for p in schedule_result.optimized_places}

        added_places = [
            places_by_id[pid].name
            for pid in proposed_by_pid
            if pid not in current_by_pid and pid in places_by_id
        ]
        removed_places = [
            places_by_id[pid].name
            for pid in current_by_pid
            if pid not in proposed_by_pid and pid in places_by_id
        ]

        moved_places: list[MovedPlaceRead] = []
        for pid, prop in proposed_by_pid.items():
            if pid in current_by_pid:
                curr = current_by_pid[pid]
                if (
                    curr.day_number != prop.day_number
                    or curr.planned_arrival_time != prop.planned_arrival_time
                ):
                    moved_places.append(
                        MovedPlaceRead(
                            place_id=pid,
                            name=places_by_id[pid].name,
                            from_day=curr.day_number,
                            from_time=curr.planned_arrival_time,
                            to_day=prop.day_number,
                            to_time=prop.planned_arrival_time,
                        )
                    )

        current_travel_time = sum(
            (i.travel_time_minutes or 0) for i in current_itinerary
        )
        travel_time_delta = (
            schedule_result.total_travel_minutes - current_travel_time
            if current_itinerary
            else schedule_result.total_travel_minutes
        )

        summary_parts = []
        if added_places:
            summary_parts.append(f"{len(added_places)} place(s) added")
        if removed_places:
            summary_parts.append(f"{len(removed_places)} place(s) removed")
        if moved_places:
            summary_parts.append(f"{len(moved_places)} stop(s) rescheduled")
        summary = (
            ", ".join(summary_parts) + "."
            if summary_parts
            else "Proposed itinerary re-balances your schedule."
        )

        return TripReplanPreviewRead(
            trip_id=trip_id,
            is_stale=True,
            summary=summary,
            added_places=added_places,
            removed_places=removed_places,
            travel_time_delta_minutes=travel_time_delta,
            proposed_itinerary=schedule_result.optimized_places,
            breaks=schedule_result.breaks,
            conflicts=schedule_result.conflicts,
            unscheduled_places=schedule_result.unscheduled_places,
        )

    async def apply_replan(

        self,
        session: Session,
        trip_id: UUID,
        route_provider: RouteMatrixProvider,
        route_matrix: RouteMatrixService,
    ) -> RouteOptimizationRead:
        """Atomically optimize and persist the proposed re-plan."""
        optimizer = RouteOptimizationService()
        return await optimizer.optimize(
            session=session,
            trip_id=trip_id,
            route_provider=route_provider,
            route_matrix=route_matrix,
        )

    def update_stop_status(
        self,
        session: Session,
        trip_id: UUID,
        stop_or_place_id: UUID,
        new_status: ItineraryStopStatus | str,
    ) -> OptimizedPlaceRead:
        trip = session.get(Trip, trip_id)
        if trip is None:
            raise RouteTripNotFoundError("Trip not found.")

        stop = session.exec(
            select(TripItinerary).where(
                TripItinerary.trip_id == trip_id,
                or_(
                    TripItinerary.id == stop_or_place_id,
                    TripItinerary.place_id == stop_or_place_id,
                ),
            )
        ).first()
        if stop is None:
            raise ItineraryStopNotFoundError("Itinerary stop not found.")

        status_str = new_status.value if hasattr(new_status, "value") else str(new_status)
        status_str = status_str.upper().strip()
        if status_str not in ("PLANNED", "COMPLETED", "MISSED", "SKIPPED"):
            raise RouteValidationError(f"Invalid itinerary stop status: {status_str}")

        stop.status = status_str
        session.add(stop)
        session.commit()
        session.refresh(stop)

        place = session.get(Place, stop.place_id)
        place_name = place.name if place else "Unknown Place"

        return OptimizedPlaceRead(
            id=stop.id,
            place_id=stop.place_id,
            name=place_name,
            day_number=stop.day_number,
            visit_order=stop.visit_order,
            distance_from_previous=stop.distance_from_previous or 0.0,
            travel_time_minutes=stop.travel_time_minutes or 0,
            planned_arrival_time=stop.planned_arrival_time,
            planned_departure_time=stop.planned_departure_time,
            visit_duration_minutes=estimate_visit_duration(place.category) if place else 60,
            is_opening_hours_known=place.opening_hours_status == "KNOWN" if place else False,
            status=stop.status,
        )

    def get_trip_itinerary(
        self,
        session: Session,
        trip_id: UUID,
    ) -> RouteOptimizationRead:
        trip = session.get(Trip, trip_id)
        if trip is None:
            raise RouteTripNotFoundError("Trip not found.")

        stops = list(
            session.exec(
                select(TripItinerary)
                .where(TripItinerary.trip_id == trip_id)
                .order_by(TripItinerary.day_number, TripItinerary.visit_order)
            ).all()
        )
        place_ids = [s.place_id for s in stops]
        places = (
            {
                p.id: p
                for p in session.exec(select(Place).where(Place.id.in_(place_ids))).all()
            }
            if place_ids
            else {}
        )

        optimized_places: list[OptimizedPlaceRead] = []
        total_distance = 0.0
        total_travel_minutes = 0

        for s in stops:
            p = places.get(s.place_id)
            p_name = p.name if p else "Unknown"
            p_cat = p.category if p else "tourism"
            dist = s.distance_from_previous or 0.0
            trav = s.travel_time_minutes or 0
            total_distance += dist
            total_travel_minutes += trav
            optimized_places.append(
                OptimizedPlaceRead(
                    id=s.id,
                    place_id=s.place_id,
                    name=p_name,
                    day_number=s.day_number,
                    visit_order=s.visit_order,
                    distance_from_previous=dist,
                    travel_time_minutes=trav,
                    planned_arrival_time=s.planned_arrival_time,
                    planned_departure_time=s.planned_departure_time,
                    visit_duration_minutes=estimate_visit_duration(p_cat),
                    is_opening_hours_known=p.opening_hours_status == "KNOWN" if p else False,
                    status=s.status,
                )
            )

        return RouteOptimizationRead(
            trip_id=trip_id,
            optimized_places=optimized_places,
            total_distance=round(total_distance, 3),
            total_travel_time_minutes=total_travel_minutes,
            total_days=trip.days,
            breaks=[],
            conflicts=[],
            unscheduled_places=[],
        )

    async def move_itinerary_place(
        self,
        session: Session,
        trip_id: UUID,
        request: MoveItineraryPlaceRequest,
        route_provider: RouteMatrixProvider,
        route_matrix: RouteMatrixService,
    ) -> MoveItineraryPlaceResponse:
        trip = session.get(Trip, trip_id)
        if trip is None:
            raise RouteTripNotFoundError("Trip not found.")

        # 1. Validate target TripDay
        target_day: TripDay | None = None
        if request.target_day_id is not None:
            target_day = session.get(TripDay, request.target_day_id)
        elif request.target_day_number is not None:
            target_day = session.exec(
                select(TripDay).where(
                    TripDay.trip_id == trip_id,
                    TripDay.day_number == request.target_day_number,
                )
            ).first()
        else:
            raise RouteValidationError("Either target_day_number or target_day_id is required.")

        if target_day is None or target_day.trip_id != trip_id:
            raise RouteValidationError("Target trip day does not exist or does not belong to this trip.")

        if target_day.day_type == "REST":
            return MoveItineraryPlaceResponse(
                success=False,
                reason="TARGET_DAY_REST",
                trip_id=trip_id,
                place_id=request.place_id,
                target_day_number=target_day.day_number,
            )

        if not target_day.start_time or not target_day.end_time or target_day.end_time <= target_day.start_time:
            return MoveItineraryPlaceResponse(
                success=False,
                reason="TARGET_DAY_NO_SIGHTSEEING_WINDOW",
                trip_id=trip_id,
                place_id=request.place_id,
                target_day_number=target_day.day_number,
            )

        # 2. Inspect moved place
        current_stop = session.exec(
            select(TripItinerary).where(
                TripItinerary.trip_id == trip_id,
                TripItinerary.place_id == request.place_id,
            )
        ).first()
        saved_place = session.exec(
            select(UserSavedPlace).where(
                UserSavedPlace.trip_id == trip_id,
                UserSavedPlace.place_id == request.place_id,
            )
        ).first()

        if current_stop is None and saved_place is None:
            raise RouteValidationError("Place is not saved for this trip.")

        source_day_number = current_stop.day_number if current_stop else None
        if current_stop is not None:
            if current_stop.status == "COMPLETED":
                return MoveItineraryPlaceResponse(
                    success=False,
                    reason="CANNOT_MOVE_COMPLETED_PLACE",
                    trip_id=trip_id,
                    place_id=request.place_id,
                    source_day_number=source_day_number,
                    target_day_number=target_day.day_number,
                )
            if current_stop.status == "SKIPPED":
                return MoveItineraryPlaceResponse(
                    success=False,
                    reason="CANNOT_MOVE_SKIPPED_PLACE",
                    trip_id=trip_id,
                    place_id=request.place_id,
                    source_day_number=source_day_number,
                    target_day_number=target_day.day_number,
                )

        if source_day_number == target_day.day_number:
            return MoveItineraryPlaceResponse(
                success=False,
                reason="ALREADY_ON_TARGET_DAY",
                trip_id=trip_id,
                place_id=request.place_id,
                source_day_number=source_day_number,
                target_day_number=target_day.day_number,
            )

        # 3. Target Day Feasibility Evaluation
        target_stops = list(
            session.exec(
                select(TripItinerary)
                .where(
                    TripItinerary.trip_id == trip_id,
                    TripItinerary.day_number == target_day.day_number,
                )
                .order_by(TripItinerary.visit_order)
            ).all()
        )
        completed_target = [s for s in target_stops if s.status == "COMPLETED"]
        planned_target = [s for s in target_stops if s.status == "PLANNED"]

        candidate_place_ids = [s.place_id for s in planned_target if s.place_id != request.place_id]
        if request.place_id not in candidate_place_ids:
            candidate_place_ids.append(request.place_id)

        all_target_place_ids = candidate_place_ids + [s.place_id for s in completed_target]
        places_by_id = {
            p.id: p
            for p in session.exec(select(Place).where(Place.id.in_(all_target_place_ids))).all()
        }
        candidate_places = [places_by_id[pid] for pid in candidate_place_ids if pid in places_by_id]
        if len(candidate_places) != len(candidate_place_ids):
            raise RouteValidationError("A place selected for the route no longer exists.")

        # Determine start node and effective start time for remaining route on target day
        if completed_target:
            last_completed = completed_target[-1]
            last_completed_place = places_by_id[last_completed.place_id]
            target_start_node = RouteNode.for_place(last_completed_place)
            effective_start_time = max(
                target_day.start_time,
                last_completed.planned_departure_time or target_day.start_time,
            )
        else:
            target_start_node = RouteNode.for_start(trip)
            effective_start_time = target_day.start_time

        if effective_start_time >= target_day.end_time:
            return MoveItineraryPlaceResponse(
                success=False,
                reason="TARGET_DAY_INFEASIBLE",
                trip_id=trip_id,
                place_id=request.place_id,
                source_day_number=source_day_number,
                target_day_number=target_day.day_number,
            )

        try:
            target_start_node, place_nodes, matrix = await route_matrix.get_complete_matrix(
                session,
                trip,
                candidate_places,
                route_provider,
                start_node=target_start_node,
            )
        except ValueError as exc:
            raise RouteValidationError(str(exc)) from exc

        _, weekly_hours = load_planner_inputs(session, trip, candidate_places)

        candidate_saved_rows: list[UserSavedPlace] = []
        for place in candidate_places:
            sp = session.exec(
                select(UserSavedPlace).where(
                    UserSavedPlace.trip_id == trip_id,
                    UserSavedPlace.place_id == place.id,
                )
            ).first()
            if place.id == request.place_id:
                candidate_saved_rows.append(
                    UserSavedPlace(
                        trip_id=trip_id,
                        place_id=place.id,
                        assignment_mode="LOCKED",
                        assigned_day_id=target_day.id,
                        priority=sp.priority if sp else 0,
                        must_visit=sp.must_visit if sp else False,
                    )
                )
            else:
                candidate_saved_rows.append(
                    UserSavedPlace(
                        trip_id=trip_id,
                        place_id=place.id,
                        assignment_mode="LOCKED",
                        assigned_day_id=target_day.id,
                        priority=sp.priority if sp else 0,
                        must_visit=sp.must_visit if sp else False,
                    )
                )

        target_day_eval = TripDay(
            id=target_day.id,
            trip_id=trip_id,
            day_number=target_day.day_number,
            date=target_day.date,
            day_type=target_day.day_type,
            start_time=effective_start_time,
            end_time=target_day.end_time,
        )
        solver = VrptwSolverService(time_limit_seconds=1.5)
        solution = solver.solve(
            start_node=target_start_node,
            place_nodes=place_nodes,
            places=candidate_places,
            saved_rows=candidate_saved_rows,
            matrix=matrix,
            trip_days=1,
            start_date=target_day.date,
            day_configs=[target_day_eval],
            weekly_hours_map=weekly_hours,
        )

        # Infeasible if not every candidate place could fit on target day
        if len(solution.optimized_places) != len(candidate_places):
            return MoveItineraryPlaceResponse(
                success=False,
                reason="TARGET_DAY_INFEASIBLE",
                trip_id=trip_id,
                place_id=request.place_id,
                source_day_number=source_day_number,
                target_day_number=target_day.day_number,
            )

        # 4. Commit Target Day
        session.exec(
            delete(TripItinerary).where(
                TripItinerary.trip_id == trip_id,
                TripItinerary.day_number == target_day.day_number,
                TripItinerary.status != "COMPLETED",
            )
        )
        session.flush()

        k_target = len(completed_target)
        for item in solution.optimized_places:
            k_target += 1
            session.add(
                TripItinerary(
                    id=uuid4(),
                    trip_id=trip_id,
                    place_id=item.place_id,
                    day_number=target_day.day_number,
                    visit_order=k_target,
                    planned_arrival_time=item.planned_arrival_time,
                    planned_departure_time=item.planned_departure_time,
                    distance_from_previous=item.distance_from_previous,
                    travel_time_minutes=item.travel_time_minutes,
                    status="PLANNED",
                )
            )

        # Update UserSavedPlace lock for moved place
        if saved_place is None:
            saved_place = UserSavedPlace(
                trip_id=trip_id,
                place_id=request.place_id,
                assignment_mode="LOCKED",
                assigned_day_id=target_day.id,
            )
        else:
            saved_place.assignment_mode = "LOCKED"
            saved_place.assigned_day_id = target_day.id
        session.add(saved_place)

        # 5. Commit Source Day
        if source_day_number is not None:
            session.exec(
                delete(TripItinerary).where(
                    TripItinerary.trip_id == trip_id,
                    TripItinerary.place_id == request.place_id,
                    TripItinerary.day_number == source_day_number,
                )
            )
            session.flush()

            source_stops = list(
                session.exec(
                    select(TripItinerary)
                    .where(
                        TripItinerary.trip_id == trip_id,
                        TripItinerary.day_number == source_day_number,
                    )
                    .order_by(TripItinerary.visit_order)
                ).all()
            )
            completed_source = [s for s in source_stops if s.status == "COMPLETED"]
            planned_source = [s for s in source_stops if s.status == "PLANNED"]

            if planned_source:
                source_day = session.exec(
                    select(TripDay).where(
                        TripDay.trip_id == trip_id,
                        TripDay.day_number == source_day_number,
                    )
                ).first()

                if (
                    source_day
                    and source_day.start_time
                    and source_day.end_time
                    and source_day.end_time > source_day.start_time
                ):
                    src_places = [
                        session.get(Place, s.place_id) for s in planned_source
                    ]
                    src_places = [p for p in src_places if p is not None]

                    if completed_source:
                        last_src_comp = completed_source[-1]
                        last_src_place = session.get(Place, last_src_comp.place_id)
                        src_start_node = RouteNode.for_place(last_src_place)
                        src_eff_start = max(
                            source_day.start_time,
                            last_src_comp.planned_departure_time or source_day.start_time,
                        )
                    else:
                        src_start_node = RouteNode.for_start(trip)
                        src_eff_start = source_day.start_time

                    if src_eff_start < source_day.end_time and src_places:
                        src_start_node, src_place_nodes, src_matrix = await route_matrix.get_complete_matrix(
                            session,
                            trip,
                            src_places,
                            route_provider,
                            start_node=src_start_node,
                        )
                        _, src_weekly = load_planner_inputs(session, trip, src_places)
                        src_saved_rows = [
                            UserSavedPlace(
                                trip_id=trip_id,
                                place_id=p.id,
                                assignment_mode="LOCKED",
                                assigned_day_id=source_day.id,
                            )
                            for p in src_places
                        ]
                        src_day_eval = TripDay(
                            id=source_day.id,
                            trip_id=trip_id,
                            day_number=source_day.day_number,
                            date=source_day.date,
                            day_type=source_day.day_type,
                            start_time=src_eff_start,
                            end_time=source_day.end_time,
                        )
                        src_solution = solver.solve(
                            start_node=src_start_node,
                            place_nodes=src_place_nodes,
                            places=src_places,
                            saved_rows=src_saved_rows,
                            matrix=src_matrix,
                            trip_days=1,
                            start_date=source_day.date,
                            day_configs=[src_day_eval],
                            weekly_hours_map=src_weekly,
                        )

                        session.exec(
                            delete(TripItinerary).where(
                                TripItinerary.trip_id == trip_id,
                                TripItinerary.day_number == source_day_number,
                                TripItinerary.status == "PLANNED",
                            )
                        )
                        session.flush()

                        k_src = len(completed_source)
                        for item in src_solution.optimized_places:
                            k_src += 1
                            session.add(
                                TripItinerary(
                                    id=uuid4(),
                                    trip_id=trip_id,
                                    place_id=item.place_id,
                                    day_number=source_day_number,
                                    visit_order=k_src,
                                    planned_arrival_time=item.planned_arrival_time,
                                    planned_departure_time=item.planned_departure_time,
                                    distance_from_previous=item.distance_from_previous,
                                    travel_time_minutes=item.travel_time_minutes,
                                    status="PLANNED",
                                )
                            )

        session.commit()

        # Build response with updated day itineraries
        full_itinerary = self.get_trip_itinerary(session, trip_id)
        source_itin = [
            p for p in full_itinerary.optimized_places if p.day_number == source_day_number
        ] if source_day_number is not None else []
        target_itin = [
            p for p in full_itinerary.optimized_places if p.day_number == target_day.day_number
        ]

        return MoveItineraryPlaceResponse(
            success=True,
            reason=None,
            trip_id=trip_id,
            place_id=request.place_id,
            source_day_number=source_day_number,
            target_day_number=target_day.day_number,
            source_itinerary=source_itin,
            target_itinerary=target_itin,
            updated_itinerary=full_itinerary,
        )
