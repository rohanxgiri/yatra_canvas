"""Fail-closed guards for utilities that intentionally mutate a database."""

from app.core.config import AppEnvironment, Settings

WRITE_TEST_ENVIRONMENTS = frozenset(
    {AppEnvironment.DEVELOPMENT, AppEnvironment.TEST}
)


class UnsafeDatabaseOperationError(RuntimeError):
    """Raised when a diagnostic write is not explicitly authorized by APP_ENV."""


def require_write_test_environment(settings: Settings) -> AppEnvironment:
    """Allow diagnostic writes only in explicitly classified safe environments."""

    environment = settings.app_env
    if environment not in WRITE_TEST_ENVIRONMENTS:
        rendered = environment.value if environment is not None else "unset"
        raise UnsafeDatabaseOperationError(
            "Refusing database write test: APP_ENV must be explicitly set to "
            f"development or test (current value: {rendered})."
        )
    return environment
