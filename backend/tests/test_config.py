"""Configuration inventory and secret-safety regression tests."""

from pathlib import Path

import pytest
from pydantic import ValidationError

from app.core.config import Settings

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
BACKEND_ONLY_VARIABLES = {
    "DATABASE_URL",
    "GEOAPIFY_API_KEY",
    "GOOGLE_PLACES_API_KEY",
    "GOOGLE_ROUTES_API_KEY",
}


def _settings(**values: object) -> Settings:
    return Settings(
        _env_file=None,
        DATABASE_URL="postgresql://localhost/yatracanvas_test",
        **values,
    )  # type: ignore[call-arg]


def test_database_url_is_required(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("DATABASE_URL", raising=False)

    with pytest.raises(ValidationError) as captured:
        Settings(_env_file=None)  # type: ignore[call-arg]

    assert "DATABASE_URL" in str(captured.value)


def test_optional_provider_keys_normalize_to_none() -> None:
    settings = _settings(
        GOOGLE_ROUTES_API_KEY="",
        GEOAPIFY_API_KEY="   ",
    )

    assert settings.google_routes_api_key_value is None
    assert settings.geoapify_api_key_value is None


def test_secret_values_have_redacted_representations() -> None:
    database_password = "database-password-that-must-not-render"
    places_key = "places-key-that-must-not-render"
    routes_key = "routes-key-that-must-not-render"
    geoapify_key = "geoapify-key-that-must-not-render"
    settings = Settings(
        _env_file=None,
        DATABASE_URL=(
            "postgresql://test_user:" f"{database_password}@localhost/yatracanvas_test"
        ),
        GOOGLE_PLACES_API_KEY=places_key,
        GOOGLE_ROUTES_API_KEY=routes_key,
        GEOAPIFY_API_KEY=geoapify_key,
    )  # type: ignore[call-arg]

    rendered = f"{settings!r}\n{settings}"
    for secret in (
        database_password,
        places_key,
        routes_key,
        geoapify_key,
    ):
        assert secret not in rendered
    assert "**********" in rendered


def test_env_example_exactly_matches_settings_model() -> None:
    example_path = REPOSITORY_ROOT / "backend" / ".env.example"
    example_names = {
        line.split("=", 1)[0].strip()
        for line in example_path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    }
    settings_names = {
        field.validation_alias
        for field in Settings.model_fields.values()
        if isinstance(field.validation_alias, str)
    }

    assert example_names == settings_names


def test_backend_only_variables_are_not_in_flutter_source() -> None:
    flutter_source = "\n".join(
        path.read_text(encoding="utf-8")
        for path in (REPOSITORY_ROOT / "lib").rglob("*.dart")
    )

    for variable in BACKEND_ONLY_VARIABLES:
        assert variable not in flutter_source
