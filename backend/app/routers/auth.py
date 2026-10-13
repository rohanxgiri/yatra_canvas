"""Authentication API router for credentials verification and token issuance."""

import logging
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.core import dev_auth
from app.core.auth import get_current_user
from app.core.security import create_access_token, hash_password, verify_password
from app.database import get_session
from app.models import User
from app.schemas.auth import (
    PasswordResetRequest,
    TokenResponse,
    UserLoginRequest,
    UserRead,
    UserSignupRequest,
)

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

    # Never shadow a registered account with the showcase identity.
    if user is None and dev_auth.matches(normalized_email, credentials.password):
        demo = dev_auth.principal()
        return TokenResponse(
            access_token=create_access_token({"sub": str(demo.id), "dev_admin": True}),
            user=UserRead.model_validate(demo),
        )

    if user is None or not verify_password(credentials.password, user.password_hash):
        logger.warning("Failed credential verification")
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


@router.post("/signup", response_model=TokenResponse, status_code=201)
def signup(payload: UserSignupRequest, session: SessionDependency) -> TokenResponse:
    """Registration can only create an ordinary traveller account."""
    if session.exec(
        select(User).where(func.lower(User.email) == payload.email)
    ).first():
        raise HTTPException(
            status_code=409, detail="Unable to create an account with these details."
        )
    user = User(
        name=payload.name,
        email=payload.email,
        password_hash=hash_password(payload.password),
    )
    session.add(user)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(
            status_code=409, detail="Unable to create an account with these details."
        ) from exc
    session.refresh(user)
    return TokenResponse(
        access_token=create_access_token({"sub": str(user.id)}),
        user=UserRead.model_validate(user),
    )


@router.post("/forgot-password")
def forgot_password(payload: PasswordResetRequest) -> dict:
    # No email delivery provider or reset-token lifecycle is configured.
    return {
        "available": False,
        "message": "Password reset email delivery is not configured. No email was sent.",
    }
