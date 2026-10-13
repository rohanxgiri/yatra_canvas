"""Explicit local showcase identity, with no database account or production access."""

import hmac
from uuid import UUID

from app.core.config import AppEnvironment, get_settings
from app.models import User, UserRole

DEMO_ADMIN_ID = UUID("3ee78a74-6f36-4cac-9ccb-e18ba2fd63fd")


def enabled() -> bool:
    settings = get_settings()
    return settings.enable_dev_admin and settings.app_env in (
        AppEnvironment.DEVELOPMENT,
        AppEnvironment.TEST,
    )


def principal() -> User:
    return User(
        id=DEMO_ADMIN_ID,
        name="Development showcase administrator",
        email="admin@yatracanvas.com",
        password_hash="",
        role=UserRole.ADMIN.value,
    )


def matches(email: str, password: str) -> bool:
    # User authorized this fixed local showcase credential on 2026-10-12.
    # It is never a production account or an email-only privilege check.
    return enabled() and email == "admin@yatracanvas.com" and hmac.compare_digest(
        password.encode("utf-8"), b"admin"
    )
