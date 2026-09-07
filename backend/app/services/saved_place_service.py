"""Persistence rules for a user's ordered, customized trip places."""

from __future__ import annotations

from uuid import UUID

from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.models import Place, Trip, TripDay, UserSavedPlace
from app.schemas import (
    AssignmentMode,
    DayType,
    PlaceRead,
    SavedPlaceCreate,
    SavedPlaceUpdate,
    SavedPlaceOrder,
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


class InvalidSavedPlaceAssignmentError(SavedPlaceServiceError):
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

        mode, day_id = self._validate_and_resolve_assignment(
            session=session,
            trip_id=trip_id,
            assignment_mode=request.assignment_mode,
            assigned_day_id=request.assigned_day_id,
        )

        saved = UserSavedPlace(
            trip_id=trip_id,
            place_id=request.place_id,
            custom_order=requested_order,
            priority=request.priority,
            is_locked=request.is_locked,
            must_visit=request.must_visit,
            assignment_mode=mode,
            assigned_day_id=day_id,
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
        if "assignment_mode" in fields or "assigned_day_id" in fields:
            req_mode = request.assignment_mode if "assignment_mode" in fields else None
            req_day_id = request.assigned_day_id if "assigned_day_id" in fields else None
            mode, day_id = self._validate_and_resolve_assignment(
                session=session,
                trip_id=trip_id,
                assignment_mode=req_mode,
                assigned_day_id=req_day_id,
                current_saved=saved,
            )
            saved.assignment_mode = mode
            saved.assigned_day_id = day_id
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

    def _validate_and_resolve_assignment(
        self,
        session: Session,
        trip_id: UUID,
        assignment_mode: AssignmentMode | str | None,
        assigned_day_id: UUID | None,
        current_saved: UserSavedPlace | None = None,
    ) -> tuple[str, UUID | None]:
        mode_str = (
            assignment_mode.value
            if isinstance(assignment_mode, AssignmentMode)
            else (str(assignment_mode) if assignment_mode is not None else None)
        )

        if mode_str is None and assigned_day_id is not None:
            mode_str = AssignmentMode.LOCKED.value

        if mode_str is None:
            if current_saved is not None:
                mode_str = current_saved.assignment_mode
                assigned_day_id = current_saved.assigned_day_id
            else:
                mode_str = AssignmentMode.AUTO.value
                assigned_day_id = None

        if mode_str == AssignmentMode.AUTO.value:
            if assigned_day_id is not None:
                raise InvalidSavedPlaceAssignmentError(
                    "assigned_day_id must be null when assignment_mode is AUTO."
                )
            return AssignmentMode.AUTO.value, None

        if mode_str == AssignmentMode.LOCKED.value:
            if assigned_day_id is None:
                if current_saved is not None and current_saved.assigned_day_id is not None:
                    assigned_day_id = current_saved.assigned_day_id
                else:
                    raise InvalidSavedPlaceAssignmentError(
                        "assigned_day_id is required when assignment_mode is LOCKED."
                    )

            day = session.get(TripDay, assigned_day_id)
            if day is None:
                raise InvalidSavedPlaceAssignmentError("Assigned day not found.")
            if day.trip_id != trip_id:
                raise InvalidSavedPlaceAssignmentError(
                    "Assigned day does not belong to this trip."
                )
            if day.day_type == DayType.REST.value:
                raise InvalidSavedPlaceAssignmentError(
                    f"Cannot lock place to Day {day.day_number} because it is a REST day."
                )
            if day.start_time is None or day.end_time is None or day.end_time <= day.start_time:
                raise InvalidSavedPlaceAssignmentError(
                    f"Cannot lock place to Day {day.day_number} because it has no usable sightseeing window."
                )
            return AssignmentMode.LOCKED.value, day.id

        raise InvalidSavedPlaceAssignmentError(f"Unsupported assignment_mode: {mode_str}")

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
            assignment_mode=AssignmentMode(saved.assignment_mode)
            if saved.assignment_mode
            else AssignmentMode.AUTO,
            assigned_day_id=saved.assigned_day_id,
            notes=saved.notes,
            created_at=saved.created_at,
            place=PlaceRead.model_validate(place),
        )
