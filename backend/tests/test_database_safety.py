"""Regression tests for explicit database mutation safety gates."""

import pytest

from app.core.config import AppEnvironment, Settings
from app.core.database_safety import (
    UnsafeDatabaseOperationError,
    require_write_test_environment,
)


def settings(app_env: str | None = None) -> Settings:
    values = {"DATABASE_URL": "postgresql://localhost/yatracanvas_test"}
    if app_env is not None:
        values["APP_ENV"] = app_env
    return Settings(_env_file=None, **values)  # type: ignore[arg-type]


@pytest.mark.parametrize(
    ("value", "expected"),
    [
        ("development", AppEnvironment.DEVELOPMENT),
        ("test", AppEnvironment.TEST),
    ],
)
def test_write_test_guard_allows_explicit_safe_environments(
    value: str,
    expected: AppEnvironment,
) -> None:
    assert require_write_test_environment(settings(value)) is expected


@pytest.mark.parametrize("value", [None, "staging", "production"])
def test_write_test_guard_rejects_unclassified_or_deployed_environments(
    value: str | None,
) -> None:
    with pytest.raises(UnsafeDatabaseOperationError, match="Refusing database write"):
        require_write_test_environment(settings(value))
