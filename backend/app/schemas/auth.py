"""Authentication schemas for user registration, login, and token responses."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class UserLoginRequest(BaseModel):
    """Credentials required to authenticate."""

    model_config = ConfigDict(extra="forbid")

    email: str = Field(min_length=3, max_length=255)
    password: str = Field(min_length=1, max_length=128)


class UserRead(BaseModel):
    """Safe public representation of a user account."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    email: str
    role: str
    is_active: bool
    created_at: datetime | None = None


class TokenResponse(BaseModel):
    """Bearer access token payload returned upon successful login."""

    access_token: str
    token_type: str = "bearer"
    user: UserRead
