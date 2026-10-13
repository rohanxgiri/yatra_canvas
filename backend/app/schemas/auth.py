"""Authentication schemas for user registration, login, and token responses."""

import re
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator


class UserLoginRequest(BaseModel):
    """Credentials required to authenticate."""

    model_config = ConfigDict(extra="forbid")

    email: str = Field(min_length=3, max_length=255)
    password: str = Field(min_length=1, max_length=128)

    @field_validator("email")
    @classmethod
    def validate_email(cls, value: str) -> str:
        value = value.strip().lower()
        if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", value):
            raise ValueError("Enter a valid email address.")
        return value


class UserSignupRequest(UserLoginRequest):
    name: str = Field(min_length=1, max_length=120)

    @field_validator("name")
    @classmethod
    def validate_name(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("Enter your full name.")
        return value.strip()

    @field_validator("password")
    @classmethod
    def validate_password(cls, value: str) -> str:
        if len(value) < 8 or len(value.encode("utf-8")) > 72:
            raise ValueError("Use at least 8 characters and at most 72 UTF-8 bytes.")
        return value


class PasswordResetRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: str = Field(min_length=3, max_length=255)
    validate_email = field_validator("email")(UserLoginRequest.validate_email.__func__)


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
