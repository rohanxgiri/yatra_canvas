"""Trip saved-place customization endpoints."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlmodel import Session

from app.database import get_session
from app.schemas import (
    SavedPlaceCreate,
    SavedPlaceUpdate,
    SavedPlaceRead,
    SavedPlaceReorder,
)
from app.services.saved_place_service import (
    DuplicateSavedPlaceError,
    InvalidSavedPlaceAssignmentError,
    InvalidSavedPlaceOrderError,
    PlaceNotFoundError,
    SavedPlaceNotFoundError,
    SavedPlaceService,
    TripNotFoundError,
)


router = APIRouter(prefix="/trips/{trip_id}/saved-places", tags=["saved-places"])
SessionDependency = Annotated[Session, Depends(get_session)]


def get_saved_place_service() -> SavedPlaceService:
    return SavedPlaceService()


SavedPlaceDependency = Annotated[
    SavedPlaceService, Depends(get_saved_place_service)
]


def saved_place_http_error(error: Exception) -> HTTPException:
    if isinstance(
        error,
        (TripNotFoundError, PlaceNotFoundError, SavedPlaceNotFoundError),
    ):
        return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(error))
    if isinstance(error, DuplicateSavedPlaceError):
        return HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(error))
    if isinstance(error, InvalidSavedPlaceAssignmentError):
        return HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=str(error)
        )
    return HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(error))


@router.get("", response_model=list[SavedPlaceRead])
def list_saved_places(
    trip_id: UUID,
    session: SessionDependency,
    saved_places: SavedPlaceDependency,
) -> list[SavedPlaceRead]:
    try:
        return saved_places.list(session, trip_id)
    except TripNotFoundError as exc:
        raise saved_place_http_error(exc) from exc


@router.post("", response_model=SavedPlaceRead, status_code=status.HTTP_201_CREATED)
def add_saved_place(
    trip_id: UUID,
    request: SavedPlaceCreate,
    session: SessionDependency,
    saved_places: SavedPlaceDependency,
) -> SavedPlaceRead:
    try:
        return saved_places.add(session, trip_id, request)
    except (
        TripNotFoundError,
        PlaceNotFoundError,
        DuplicateSavedPlaceError,
        InvalidSavedPlaceOrderError,
        InvalidSavedPlaceAssignmentError,
    ) as exc:
        session.rollback()
        raise saved_place_http_error(exc) from exc


@router.patch("/reorder", response_model=list[SavedPlaceRead])
def reorder_saved_places(
    trip_id: UUID,
    request: SavedPlaceReorder,
    session: SessionDependency,
    saved_places: SavedPlaceDependency,
) -> list[SavedPlaceRead]:
    try:
        return saved_places.reorder(session, trip_id, request)
    except (TripNotFoundError, InvalidSavedPlaceOrderError) as exc:
        session.rollback()
        raise saved_place_http_error(exc) from exc


@router.patch("/{place_id}", response_model=SavedPlaceRead)
def update_saved_place(
    trip_id: UUID,
    place_id: UUID,
    request: SavedPlaceUpdate,
    session: SessionDependency,
    saved_places: SavedPlaceDependency,
) -> SavedPlaceRead:
    try:
        return saved_places.update(session, trip_id, place_id, request)
    except (
        TripNotFoundError,
        SavedPlaceNotFoundError,
        InvalidSavedPlaceOrderError,
        InvalidSavedPlaceAssignmentError,
    ) as exc:
        session.rollback()
        raise saved_place_http_error(exc) from exc


@router.delete("/{place_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_saved_place(
    trip_id: UUID,
    place_id: UUID,
    session: SessionDependency,
    saved_places: SavedPlaceDependency,
) -> Response:
    try:
        saved_places.remove(session, trip_id, place_id)
    except (TripNotFoundError, SavedPlaceNotFoundError) as exc:
        session.rollback()
        raise saved_place_http_error(exc) from exc
    return Response(status_code=status.HTTP_204_NO_CONTENT)
