"""Authentication API router for credentials verification and token issuance."""

import logging
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func
from sqlmodel import Session, select

from app.core.auth import get_current_user
from app.core.security import create_access_token, verify_password
from app.database import get_session
from app.models import User
from app.schemas.auth import TokenResponse, UserLoginRequest, UserRead

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/auth", tags=["auth"])
SessionDependency = Annotated[Session, Depends(get_session)]


@router.post("/login", response_model=TokenResponse)
def login(
    credentials: UserLoginRequest,
    session: SessionDependency,
) -> TokenResponse:
    """Authenticate user credentials and return a bearer access token."""

    normalized_email = credentials.email.strip().lower()
    statement = select(User).where(func.lower(User.email) == normalized_email)
    user = session.exec(statement).first()

    if user is None or not verify_password(
        credentials.password, user.password_hash
    ):
        logger.warning("Failed login attempt for email=%s", normalized_email)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if not user.is_active:
        logger.warning("Login attempted for deactivated user=%s", user.id)
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is deactivated. Please contact support.",
        )

    token = create_access_token(
        data={
            "sub": str(user.id),
            "email": user.email,
            "role": user.role,
        }
    )

    logger.info("Successful login for user=%s role=%s", user.id, user.role)
    return TokenResponse(
        access_token=token,
        token_type="bearer",
        user=UserRead.model_validate(user),
    )


@router.get("/me", response_model=UserRead)
def get_authenticated_user(
    current_user: Annotated[User, Depends(get_current_user)],
) -> UserRead:
    """Return the profile of the currently authenticated user."""

    return UserRead.model_validate(current_user)
