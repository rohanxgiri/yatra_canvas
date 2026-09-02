"""Trip route-geometry endpoints."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlmodel import Session

from app.core.config import get_settings
from app.database import get_session
from app.schemas import TripRouteGeometryRead
from app.services.route_geometry_service import (
    OpenRouteServiceGeometryProvider,
    OSRMGeometryProvider,
    RouteGeometryConfigurationError,
    RouteGeometryError,
    RouteGeometryProvider,
    RouteGeometryService,
    RouteGeometryTimeoutError,
    RouteGeometryTripNotFoundError,
    RouteGeometryUnavailableError,
    RouteGeometryValidationError,
)

router = APIRouter(prefix="/trips", tags=["route-geometry"])
SessionDependency = Annotated[Session, Depends(get_session)]

_service_instance: RouteGeometryService | None = None


def get_route_geometry_service() -> RouteGeometryService:
    global _service_instance
    if _service_instance is None:
        settings = get_settings()
        _service_instance = RouteGeometryService(
            cache_ttl_minutes=settings.route_geometry_cache_ttl_minutes
        )
    return _service_instance


def get_route_geometry_provider() -> RouteGeometryProvider:
    settings = get_settings()
    if settings.routing_provider == "openrouteservice":
        return OpenRouteServiceGeometryProvider(
            api_key=settings.openrouteservice_api_key_value,
            base_url=settings.openrouteservice_base_url,
            timeout_seconds=settings.openrouteservice_timeout_seconds,
        )
    return OSRMGeometryProvider(
        base_url=settings.osrm_router_url,
        timeout_seconds=settings.osrm_timeout_seconds,
    )


RouteGeometryServiceDependency = Annotated[
    RouteGeometryService, Depends(get_route_geometry_service)
]
RouteGeometryProviderDependency = Annotated[
    RouteGeometryProvider, Depends(get_route_geometry_provider)
]


@router.get("/{trip_id}/route-geometry", response_model=TripRouteGeometryRead)
async def get_trip_route_geometry(
    trip_id: UUID,
    session: SessionDependency,
    service: RouteGeometryServiceDependency,
    provider: RouteGeometryProviderDependency,
    day_number: Annotated[
        int | None,
        Query(ge=1, description="Optional day number to filter geometry"),
    ] = None,
) -> TripRouteGeometryRead:
    try:
        return await service.get_trip_geometry(
            session=session,
            trip_id=trip_id,
            provider=provider,
            day_number=day_number,
        )
    except RouteGeometryTripNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except RouteGeometryValidationError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=str(exc)
        ) from exc
    except RouteGeometryConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)
        ) from exc
    except RouteGeometryTimeoutError as exc:
        raise HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT, detail=str(exc)
        ) from exc
    except RouteGeometryUnavailableError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)
        ) from exc
    except RouteGeometryError as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(exc)
        ) from exc
