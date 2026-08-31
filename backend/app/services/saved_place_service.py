"""Persistence rules for a user's ordered, customized trip places."""

from __future__ import annotations

from uuid import UUID

from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.models import Place, Trip, UserSavedPlace
from app.schemas import (
    PlaceRead,
    SavedPlaceCreate,
    SavedPlaceUpdate,
    SavedPlaceRead,
    SavedPlaceReorder,
)


class SavedPlaceServiceError(Exception):
    """Base exception for saved-place operations."""


class TripNotFoundError(SavedPlaceServiceError):
    pass


class PlaceNotFoundError(SavedPlaceServiceError):
    pass


class SavedPlaceNotFoundError(SavedPlaceServiceError):
    pass


class DuplicateSavedPlaceError(SavedPlaceServiceError):
    pass


class InvalidSavedPlaceOrderError(SavedPlaceServiceError):
    pass


class SavedPlaceService:
    def list(self, session: Session, trip_id: UUID) -> list[SavedPlaceRead]:
        self._require_trip(session, trip_id)
        rows = self._saved_rows(session, trip_id)
        return [self._to_read(session, row) for row in rows]

    def add(
        self,
        session: Session,
        trip_id: UUID,
        request: SavedPlaceCreate,
    ) -> SavedPlaceRead:
        self._require_trip(session, trip_id)
        self._require_place(session, request.place_id)
        if self._find(session, trip_id, request.place_id) is not None:
            raise DuplicateSavedPlaceError(
                "This place is already saved to the trip."
            )

        existing = self._saved_rows(session, trip_id)
        self._normalize_orders(existing)
        requested_order = request.custom_order or len(existing) + 1
        if requested_order > len(existing) + 1:
            raise InvalidSavedPlaceOrderError(
                "custom_order cannot skip positions in the saved-place list."
            )
        for row in existing:
            if row.custom_order is not None and row.custom_order >= requested_order:
                row.custom_order += 1

        saved = UserSavedPlace(
            trip_id=trip_id,
            place_id=request.place_id,
            custom_order=requested_order,
            priority=request.priority,
            is_locked=request.is_locked,
            must_visit=request.must_visit,
            notes=request.notes,
        )
        session.add(saved)
        try:
            session.commit()
        except IntegrityError as exc:
            session.rollback()
            raise DuplicateSavedPlaceError(
                "This place is already saved to the trip."
            ) from exc
        session.refresh(saved)
        return self._to_read(session, saved)

    def remove(self, session: Session, trip_id: UUID, place_id: UUID) -> None:
        self._require_trip(session, trip_id)
        saved = self._find(session, trip_id, place_id)
        if saved is None:
            raise SavedPlaceNotFoundError("Saved place not found for this trip.")

        session.delete(saved)
        session.flush()
        self._normalize_orders(self._saved_rows(session, trip_id))
        session.commit()

    def update(
        self,
        session: Session,
        trip_id: UUID,
        place_id: UUID,
        request: SavedPlaceUpdate,
    ) -> SavedPlaceRead:
        self._require_trip(session, trip_id)
        saved = self._find(session, trip_id, place_id)
        if saved is None:
            raise SavedPlaceNotFoundError("Saved place not found for this trip.")
        fields = request.model_fields_set
        if "notes" in fields:
            saved.notes = request.notes
        if "priority" in fields and request.priority is not None:
            saved.priority = request.priority
        if "is_locked" in fields and request.is_locked is not None:
            saved.is_locked = request.is_locked
        if "must_visit" in fields and request.must_visit is not None:
            saved.must_visit = request.must_visit
        if "custom_order" in fields and request.custom_order is not None:
            rows = [
                row
                for row in self._saved_rows(session, trip_id)
                if row.place_id != place_id
            ]
            if request.custom_order > len(rows) + 1:
                raise InvalidSavedPlaceOrderError(
                    "custom_order cannot skip positions in the saved-place list."
                )
            rows.insert(request.custom_order - 1, saved)
            self._normalize_orders(rows)
        session.commit()
        session.refresh(saved)
        return self._to_read(session, saved)

    def reorder(
        self,
        session: Session,
        trip_id: UUID,
        request: SavedPlaceReorder,
    ) -> list[SavedPlaceRead]:
        self._require_trip(session, trip_id)
        existing = self._saved_rows(session, trip_id)
        by_place_id = {row.place_id: row for row in existing}
        requested_ids = {item.place_id for item in request.places}
        if requested_ids != set(by_place_id):
            raise InvalidSavedPlaceOrderError(
                "Reorder must include every saved place exactly once."
            )

        for item in request.places:
            by_place_id[item.place_id].custom_order = item.custom_order
        session.commit()
        return self.list(session, trip_id)

    @staticmethod
    def _require_trip(session: Session, trip_id: UUID) -> Trip:
        trip = session.get(Trip, trip_id)
        if trip is None:
            raise TripNotFoundError("Trip not found.")
        return trip

    @staticmethod
    def _require_place(session: Session, place_id: UUID) -> Place:
        place = session.get(Place, place_id)
        if place is None:
            raise PlaceNotFoundError("Place not found.")
        return place

    @staticmethod
    def _find(
        session: Session,
        trip_id: UUID,
        place_id: UUID,
    ) -> UserSavedPlace | None:
        return session.exec(
            select(UserSavedPlace).where(
                UserSavedPlace.trip_id == trip_id,
                UserSavedPlace.place_id == place_id,
            )
        ).first()

    @staticmethod
    def _saved_rows(session: Session, trip_id: UUID) -> list[UserSavedPlace]:
        rows = list(
            session.exec(
                select(UserSavedPlace).where(UserSavedPlace.trip_id == trip_id)
            ).all()
        )
        rows.sort(
            key=lambda row: (
                row.custom_order is None,
                row.custom_order if row.custom_order is not None else 0,
                str(row.id),
            )
        )
        return rows

    @staticmethod
    def _normalize_orders(rows: list[UserSavedPlace]) -> None:
        for index, row in enumerate(rows, start=1):
            row.custom_order = index

    @staticmethod
    def _to_read(session: Session, saved: UserSavedPlace) -> SavedPlaceRead:
        place = session.get(Place, saved.place_id)
        if place is None:
            raise PlaceNotFoundError("Place not found.")
        return SavedPlaceRead(
            id=saved.id,
            trip_id=saved.trip_id,
            place_id=saved.place_id,
            custom_order=saved.custom_order or 1,
            priority=saved.priority,
            is_locked=saved.is_locked,
            must_visit=saved.must_visit,
            notes=saved.notes,
            created_at=saved.created_at,
            place=PlaceRead.model_validate(place),
        )
