"""Trip route-optimization endpoint."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session

from app.core.config import get_settings
from app.database import get_session
from app.schemas import RouteOptimizationRead
from app.services.route_optimization_service import (
    RouteOptimizationService,
    RouteTripNotFoundError,
    RouteValidationError,
)
from app.services.google_routes_service import (
    GoogleRoutesConfigurationError,
    GoogleRoutesService,
    GoogleRoutesTimeoutError,
    GoogleRoutesUnavailableError,
)
from app.services.route_matrix_service import RouteMatrixService


router = APIRouter(prefix="/trips", tags=["route-optimization"])
SessionDependency = Annotated[Session, Depends(get_session)]


def get_google_routes_service() -> GoogleRoutesService:
    return GoogleRoutesService(get_settings().google_routes_api_key)


def get_route_optimization_service() -> RouteOptimizationService:
    return RouteOptimizationService()


def get_route_matrix_service() -> RouteMatrixService:
    return RouteMatrixService(get_settings().route_matrix_traffic_ttl_minutes)


GoogleRoutesDependency = Annotated[
    GoogleRoutesService, Depends(get_google_routes_service)
]
RouteOptimizationDependency = Annotated[
    RouteOptimizationService, Depends(get_route_optimization_service)
]
RouteMatrixDependency = Annotated[
    RouteMatrixService, Depends(get_route_matrix_service)
]


@router.post("/{trip_id}/optimize-route", response_model=RouteOptimizationRead)
async def optimize_trip_route(
    trip_id: UUID,
    session: SessionDependency,
    google_routes: GoogleRoutesDependency,
    optimizer: RouteOptimizationDependency,
    route_matrix: RouteMatrixDependency,
) -> RouteOptimizationRead:
    try:
        return await optimizer.optimize(
            session,
            trip_id,
            google_routes,
            route_matrix,
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
    except GoogleRoutesConfigurationError as exc:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc
    except GoogleRoutesTimeoutError as exc:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT,
            detail=str(exc),
        ) from exc
    except GoogleRoutesUnavailableError as exc:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from exc
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="The optimized itinerary conflicted with existing trip data.",
        ) from exc
