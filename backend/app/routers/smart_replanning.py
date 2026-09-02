"""Endpoints for smart trip re-planning, preview diffs, and atomic updates."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlmodel import Session

from app.core.config import get_settings
from app.database import get_session
from app.schemas.route_optimization import RouteOptimizationRead
from app.schemas.smart_replanning import TripReplanImpactRead, TripReplanPreviewRead
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
from app.services.smart_replanning_service import SmartReplanningService

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
ReplanningDependency = Annotated[SmartReplanningService, Depends(get_replanning_service)]


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
