"""Trip start-location endpoints."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlmodel import Session

from app.database import get_session
from app.schemas import TripStartLocationRead, TripStartLocationUpdate
from app.services.trip_service import (
    TripService,
    TripServiceNotFoundError,
    TripStartLocationError,
)


router = APIRouter(prefix="/trips", tags=["trips"])
SessionDependency = Annotated[Session, Depends(get_session)]


def get_trip_service() -> TripService:
    return TripService()


TripServiceDependency = Annotated[TripService, Depends(get_trip_service)]


def _trip_error(error: Exception) -> HTTPException:
    if isinstance(error, TripServiceNotFoundError):
        return HTTPException(status_code=404, detail=str(error))
    return HTTPException(
        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
        detail=str(error),
    )


@router.get("/{trip_id}/start-location", response_model=TripStartLocationRead)
def get_trip_start_location(
    trip_id: UUID,
    session: SessionDependency,
    trips: TripServiceDependency,
) -> TripStartLocationRead:
    try:
        return trips.get_start_location(session, trip_id)
    except (TripServiceNotFoundError, TripStartLocationError) as exc:
        raise _trip_error(exc) from exc


@router.patch("/{trip_id}/start-location", response_model=TripStartLocationRead)
def update_trip_start_location(
    trip_id: UUID,
    request: TripStartLocationUpdate,
    session: SessionDependency,
    trips: TripServiceDependency,
) -> TripStartLocationRead:
    try:
        return trips.update_start_location(session, trip_id, request)
    except (TripServiceNotFoundError, TripStartLocationError) as exc:
        session.rollback()
        raise _trip_error(exc) from exc
