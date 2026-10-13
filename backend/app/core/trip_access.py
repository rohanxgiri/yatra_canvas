"""Guest-compatible access scoped to traveller trips, separate from admin auth."""

from typing import Annotated
from uuid import UUID

from fastapi import Depends, HTTPException, Request
from sqlmodel import Session

from app.core.auth import TokenDependency, get_current_user
from app.database import get_session
from app.models import Trip, User, UserRole
from app.services.trip_service import DEVELOPMENT_USER_ID


def trip_actor(
    token_auth: TokenDependency, session: Annotated[Session, Depends(get_session)]
) -> User:
    if token_auth is not None:
        user = get_current_user(token_auth, session)
        if user.role != UserRole.USER.value:
            raise HTTPException(403, "Use the read only admin trip inspector.")
        return user
    # Preserve the original shared guest namespace and existing guest trip IDs.
    # This principal is never persisted as an account or used by require_admin.
    return User(
        id=DEVELOPMENT_USER_ID,
        name="Guest traveller",
        email="guest@example.invalid",
        password_hash="",
    )


def require_trip_access(
    request: Request,
    session: Annotated[Session, Depends(get_session)],
    actor: Annotated[User, Depends(trip_actor)],
):
    value = request.path_params.get("trip_id")
    if value is None:
        return
    try:
        trip_id = UUID(str(value))
    except ValueError:
        raise HTTPException(422, "Invalid trip identity.") from None
    trip = session.get(Trip, trip_id)
    if trip is None or trip.user_id != actor.id:
        raise HTTPException(404, "Trip not found.")
