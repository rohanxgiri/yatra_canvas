"""Trip route-optimization endpoint."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session

from app.core.config import get_settings
from app.database import get_session
from app.schemas import RouteOptimizationRead
from app.routers.route_geometry import (
    get_route_geometry_provider,
    get_route_geometry_service,
)
from app.services.google_routes_service import (
    GoogleRoutesConfigurationError,
    GoogleRoutesTimeoutError,
    GoogleRoutesUnavailableError,
)
from app.services.local_routes_service import LocalRoutesService
from app.services.route_geometry_service import (
    RouteGeometryProvider,
    RouteGeometryService,
)
from app.services.route_matrix_service import RouteMatrixService
from app.services.route_optimization_service import (
    RouteOptimizationService,
    RouteTripNotFoundError,
    RouteValidationError,
)

router = APIRouter(prefix="/trips", tags=["route-optimization"])
SessionDependency = Annotated[Session, Depends(get_session)]


def get_route_provider() -> LocalRoutesService:
    return LocalRoutesService()


def get_route_optimization_service() -> RouteOptimizationService:
    return RouteOptimizationService()


def get_route_matrix_service() -> RouteMatrixService:
    return RouteMatrixService(get_settings().route_matrix_traffic_ttl_minutes)


RouteProviderDependency = Annotated[LocalRoutesService, Depends(get_route_provider)]
RouteOptimizationDependency = Annotated[
    RouteOptimizationService, Depends(get_route_optimization_service)
]
RouteMatrixDependency = Annotated[RouteMatrixService, Depends(get_route_matrix_service)]
RouteGeometryServiceDependency = Annotated[
    RouteGeometryService, Depends(get_route_geometry_service)
]
RouteGeometryProviderDependency = Annotated[
    RouteGeometryProvider, Depends(get_route_geometry_provider)
]


@router.post("/{trip_id}/optimize-route", response_model=RouteOptimizationRead)
async def optimize_trip_route(
    trip_id: UUID,
    session: SessionDependency,
    route_provider: RouteProviderDependency,
    optimizer: RouteOptimizationDependency,
    route_matrix: RouteMatrixDependency,
    geometry_service: RouteGeometryServiceDependency,
    geometry_provider: RouteGeometryProviderDependency,
) -> RouteOptimizationRead:
    try:
        return await optimizer.optimize(
            session,
            trip_id,
            route_provider,
            route_matrix,
            geometry_service=geometry_service,
            geometry_provider=geometry_provider,
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
