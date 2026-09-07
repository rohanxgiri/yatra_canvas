"""Trip creation and start-location endpoints."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlmodel import Session

from app.database import get_session
from app.schemas import (
    TripCreate,
    TripDayRead,
    TripDayUpdate,
    TripRead,
    TripStartLocationRead,
    TripStartLocationUpdate,
    TripUpdate,
)
from app.services.trip_day_service import (
    TripDayNotFoundError,
    TripDayService,
    TripDayValidationError,
)
from app.services.trip_service import (
    TripCityNotFoundError,
    TripService,
    TripServiceError,
    TripServiceNotFoundError,
    TripStartLocationError,
)


router = APIRouter(prefix="/trips", tags=["trips"])
SessionDependency = Annotated[Session, Depends(get_session)]


def get_trip_service() -> TripService:
    return TripService()


TripServiceDependency = Annotated[TripService, Depends(get_trip_service)]


def get_trip_day_service() -> TripDayService:
    return TripDayService()


TripDayServiceDependency = Annotated[TripDayService, Depends(get_trip_day_service)]


def _trip_error(error: Exception) -> HTTPException:
    if isinstance(error, (TripServiceNotFoundError, TripCityNotFoundError)):
        return HTTPException(status_code=404, detail=str(error))
    return HTTPException(
        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
        detail=str(error),
    )


@router.post("", response_model=TripRead, status_code=status.HTTP_201_CREATED)
def create_trip(
    request: TripCreate,
    session: SessionDependency,
    trips: TripServiceDependency,
) -> TripRead:
    try:
        return trips.create(session, request)
    except TripCityNotFoundError as exc:
        session.rollback()
        raise _trip_error(exc) from exc


@router.get("/{trip_id}", response_model=TripRead)
def get_trip(
    trip_id: UUID,
    session: SessionDependency,
    trips: TripServiceDependency,
) -> TripRead:
    try:
        return trips.get(session, trip_id)
    except (TripServiceNotFoundError, TripCityNotFoundError) as exc:
        raise _trip_error(exc) from exc


@router.patch("/{trip_id}", response_model=TripRead)
def update_trip(
    trip_id: UUID,
    request: TripUpdate,
    session: SessionDependency,
    trips: TripServiceDependency,
) -> TripRead:
    try:
        return trips.update(session, trip_id, request)
    except (
        TripServiceNotFoundError,
        TripCityNotFoundError,
        TripStartLocationError,
        TripServiceError,
    ) as exc:
        session.rollback()
        raise _trip_error(exc) from exc


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


@router.get("/{trip_id}/days", response_model=list[TripDayRead])
def get_trip_days(
    trip_id: UUID,
    session: SessionDependency,
    trip_days: TripDayServiceDependency,
) -> list[TripDayRead]:
    try:
        return trip_days.get_trip_days(session, trip_id)
    except TripServiceNotFoundError as exc:
        raise _trip_error(exc) from exc


@router.patch("/{trip_id}/days/{day_number}", response_model=TripDayRead)
def update_trip_day(
    trip_id: UUID,
    day_number: int,
    request: TripDayUpdate,
    session: SessionDependency,
    trip_days: TripDayServiceDependency,
) -> TripDayRead:
    try:
        return trip_days.update_trip_day(session, trip_id, day_number, request)
    except (
        TripServiceNotFoundError,
        TripDayNotFoundError,
        TripDayValidationError,
        TripServiceError,
    ) as exc:
        session.rollback()
        raise _trip_error(exc) from exc

