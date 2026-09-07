"""Endpoints for smart trip re-planning, preview diffs, and atomic updates."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlmodel import Session

from app.core.config import get_settings
from app.database import get_session
from app.schemas.route_optimization import (
    OptimizedPlaceRead,
    RouteOptimizationRead,
)
from app.schemas.smart_replanning import (
    ItineraryStopStatusUpdate,
    MoveItineraryPlaceRequest,
    MoveItineraryPlaceResponse,
    TripReplanImpactRead,
    TripReplanPreviewRead,
)
from app.services.google_routes_service import (
    GoogleRoutesConfigurationError,
    GoogleRoutesTimeoutError,
    GoogleRoutesUnavailableError,
)
from app.services.local_routes_service import LocalRoutesService
from app.services.route_matrix_service import RouteMatrixService
from app.services.route_optimization_service import (
    RouteTripNotFoundError,
    RouteValidationError,
)
from app.services.smart_replanning_service import (
    ItineraryStopNotFoundError,
    SmartReplanningService,
)

router = APIRouter(prefix="/trips/{trip_id}", tags=["smart-replanning"])

SessionDependency = Annotated[Session, Depends(get_session)]


def get_route_provider() -> LocalRoutesService:
    return LocalRoutesService()


def get_route_matrix_service() -> RouteMatrixService:
    return RouteMatrixService(get_settings().route_matrix_traffic_ttl_minutes)


def get_replanning_service() -> SmartReplanningService:
    return SmartReplanningService()


RouteProviderDependency = Annotated[LocalRoutesService, Depends(get_route_provider)]
RouteMatrixDependency = Annotated[RouteMatrixService, Depends(get_route_matrix_service)]
ReplanningDependency = Annotated[
    SmartReplanningService, Depends(get_replanning_service)
]


@router.get("/replan-impact", response_model=TripReplanImpactRead)
def get_replan_impact(
    trip_id: UUID,
    session: SessionDependency,
    replanning: ReplanningDependency,
) -> TripReplanImpactRead:
    try:
        return replanning.check_itinerary_stale(session, trip_id)
    except RouteTripNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.post("/replan-preview", response_model=TripReplanPreviewRead)
async def preview_replan(
    trip_id: UUID,
    session: SessionDependency,
    route_provider: RouteProviderDependency,
    route_matrix: RouteMatrixDependency,
    replanning: ReplanningDependency,
) -> TripReplanPreviewRead:
    try:
        return await replanning.get_replan_preview(
            session=session,
            trip_id=trip_id,
            route_provider=route_provider,
            route_matrix=route_matrix,
        )
    except RouteTripNotFoundError as exc:
        session.rollback()
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except RouteValidationError as exc:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
        ) from exc
    except (
        GoogleRoutesConfigurationError,
        GoogleRoutesTimeoutError,
        GoogleRoutesUnavailableError,
    ) as exc:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc


@router.post("/replan-apply", response_model=RouteOptimizationRead)
async def apply_replan(
    trip_id: UUID,
    session: SessionDependency,
    route_provider: RouteProviderDependency,
    route_matrix: RouteMatrixDependency,
    replanning: ReplanningDependency,
) -> RouteOptimizationRead:
    try:
        return await replanning.apply_replan(
            session=session,
            trip_id=trip_id,
            route_provider=route_provider,
            route_matrix=route_matrix,
        )
    except RouteTripNotFoundError as exc:
        session.rollback()
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except RouteValidationError as exc:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
        ) from exc
    except (
        GoogleRoutesConfigurationError,
        GoogleRoutesTimeoutError,
        GoogleRoutesUnavailableError,
    ) as exc:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc


@router.get("/itinerary", response_model=RouteOptimizationRead)
def get_trip_itinerary(
    trip_id: UUID,
    session: SessionDependency,
    replanning: ReplanningDependency,
) -> RouteOptimizationRead:
    try:
        return replanning.get_trip_itinerary(session, trip_id)
    except RouteTripNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.patch("/itinerary/stops/{stop_id}", response_model=OptimizedPlaceRead)
def update_itinerary_stop_status(
    trip_id: UUID,
    stop_id: UUID,
    request: ItineraryStopStatusUpdate,
    session: SessionDependency,
    replanning: ReplanningDependency,
) -> OptimizedPlaceRead:
    try:
        return replanning.update_stop_status(
            session=session,
            trip_id=trip_id,
            stop_or_place_id=stop_id,
            new_status=request.status,
        )
    except RouteTripNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ItineraryStopNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except RouteValidationError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
        ) from exc


@router.patch("/itinerary/places/{place_id}", response_model=OptimizedPlaceRead)
def update_itinerary_place_status(
    trip_id: UUID,
    place_id: UUID,
    request: ItineraryStopStatusUpdate,
    session: SessionDependency,
    replanning: ReplanningDependency,
) -> OptimizedPlaceRead:
    try:
        return replanning.update_stop_status(
            session=session,
            trip_id=trip_id,
            stop_or_place_id=place_id,
            new_status=request.status,
        )
    except RouteTripNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ItineraryStopNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except RouteValidationError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
        ) from exc


@router.post("/itinerary/move-place", response_model=MoveItineraryPlaceResponse)
async def move_itinerary_place(
    trip_id: UUID,
    request: MoveItineraryPlaceRequest,
    session: SessionDependency,
    route_provider: RouteProviderDependency,
    route_matrix: RouteMatrixDependency,
    replanning: ReplanningDependency,
) -> MoveItineraryPlaceResponse:
    try:
        return await replanning.move_itinerary_place(
            session=session,
            trip_id=trip_id,
            request=request,
            route_provider=route_provider,
            route_matrix=route_matrix,
        )
    except RouteTripNotFoundError as exc:
        session.rollback()
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except RouteValidationError as exc:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
        ) from exc
    except (
        GoogleRoutesConfigurationError,
        GoogleRoutesTimeoutError,
        GoogleRoutesUnavailableError,
    ) as exc:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc
