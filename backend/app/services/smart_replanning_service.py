"""Centralized smart trip re-planning service and invalidation engine.

Determines stale planning data, reuses valid directional RouteMatrixCache legs,
generates non-persisted re-plan previews, and transactionally updates itineraries
upon user confirmation.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Final, Literal
from uuid import UUID

from sqlalchemy import delete, or_
from sqlmodel import Session, select

from app.models.entities import Place, RouteMatrixCache, Trip, TripItinerary, UserSavedPlace
from app.schemas.smart_replanning import (
    MovedPlaceRead,
    TripReplanImpactRead,
    TripReplanPreviewRead,
)
from app.schemas.route_optimization import RouteOptimizationRead
from app.services.itinerary_timing_service import ItineraryTimingService
from app.services.route_matrix_service import RouteMatrixProvider, RouteMatrixService
from app.services.route_optimization_service import (
    RouteOptimizationService,
    RouteTripNotFoundError,
    RouteValidationError,
)
from app.services.vrptw_solver_service import VrptwSolverService


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
                        f"Locked place order is out of sync with scheduled visit order."
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
        if len(saved_rows) < 2:
            raise RouteValidationError(
                "At least two saved places are required to generate an optimized itinerary."
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

        solver = VrptwSolverService()
        try:
            schedule_result = solver.solve(
                start_node=start,
                place_nodes=place_nodes,
                places=places,
                saved_rows=saved_rows,
                matrix=matrix,
                trip_days=trip.days,
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
            moved_places=moved_places,
            travel_time_delta_minutes=travel_time_delta,
            proposed_itinerary=schedule_result.optimized_places,
            breaks=schedule_result.breaks,
            conflicts=schedule_result.conflicts,
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
