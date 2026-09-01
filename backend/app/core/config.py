"""Application settings loaded from environment variables."""

from functools import lru_cache
from pathlib import Path

from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND_DIR = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    """Runtime settings.

    Secrets are intentionally loaded from the environment (or backend/.env) and
    must never be committed to source control.
    """

    database_url: SecretStr = Field(min_length=1, validation_alias="DATABASE_URL")
    google_places_api_key: SecretStr | None = Field(
        default=None,
        validation_alias="GOOGLE_PLACES_API_KEY",
    )
    google_routes_api_key: SecretStr | None = Field(
        default=None,
        validation_alias="GOOGLE_ROUTES_API_KEY",
    )
    geoapify_api_key: SecretStr | None = Field(
        default=None,
        validation_alias="GEOAPIFY_API_KEY",
    )
    geoapify_base_url: str = Field(
        default="https://api.geoapify.com",
        validation_alias="GEOAPIFY_BASE_URL",
    )
    geoapify_timeout_seconds: float = Field(
        default=8.0,
        gt=0,
        le=60,
        validation_alias="GEOAPIFY_TIMEOUT_SECONDS",
    )
    geoapify_autocomplete_cache_ttl_seconds: int = Field(
        default=300,
        ge=0,
        le=3600,
        validation_alias="GEOAPIFY_AUTOCOMPLETE_CACHE_TTL_SECONDS",
    )
    overpass_api_url: str = Field(
        default="https://overpass-api.de/api/interpreter",
        validation_alias="OVERPASS_API_URL",
    )
    overpass_timeout_seconds: float = Field(
        default=25.0,
        gt=5,
        le=60,
        validation_alias="OVERPASS_TIMEOUT_SECONDS",
    )
    overpass_radius_meters: int = Field(
        default=8000,
        ge=1000,
        le=50000,
        validation_alias="OVERPASS_RADIUS_METERS",
    )
    fsq_os_places_path: str | None = Field(
        default=None,
        validation_alias="FSQ_OS_PLACES_PATH",
    )
    fsq_dedupe_distance_meters: float = Field(
        default=75.0,
        gt=0,
        le=1000,
        validation_alias="FSQ_DEDUPE_DISTANCE_METERS",
    )
    fsq_import_batch_size: int = Field(
        default=250,
        ge=1,
        le=5000,
        validation_alias="FSQ_IMPORT_BATCH_SIZE",
    )
    route_matrix_traffic_ttl_minutes: int = Field(
        default=30,
        ge=1,
        le=1440,
        validation_alias="ROUTE_MATRIX_TRAFFIC_TTL_MINUTES",
    )
    place_discovery_cache_ttl_hours: int = Field(
        default=24,
        ge=1,
        le=720,
        validation_alias="PLACE_DISCOVERY_CACHE_TTL_HOURS",
    )
    google_nearby_radius_meters: float = Field(
        default=10000,
        gt=0,
        le=50000,
        validation_alias="GOOGLE_NEARBY_RADIUS_METERS",
    )
    place_popular_min_rating: float = Field(
        default=4.2,
        ge=0,
        le=5,
        validation_alias="PLACE_POPULAR_MIN_RATING",
    )
    place_popular_min_review_count: int = Field(
        default=100,
        ge=0,
        validation_alias="PLACE_POPULAR_MIN_REVIEW_COUNT",
    )

    model_config = SettingsConfigDict(
        env_file=BACKEND_DIR / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    @field_validator("database_url")
    @classmethod
    def validate_database_url(cls, value: SecretStr) -> SecretStr:
        normalized = value.get_secret_value().strip()
        supported_schemes = (
            "postgres://",
            "postgresql://",
            "postgresql+psycopg://",
        )
        if not normalized.startswith(supported_schemes):
            raise ValueError("DATABASE_URL must be a PostgreSQL connection URL")
        return SecretStr(normalized)

    @field_validator(
        "google_places_api_key",
        "google_routes_api_key",
        "geoapify_api_key",
    )
    @classmethod
    def normalize_optional_secret(cls, value: SecretStr | None) -> SecretStr | None:
        if value is None:
            return None
        normalized = value.get_secret_value().strip()
        return SecretStr(normalized) if normalized else None

    @field_validator("fsq_os_places_path")
    @classmethod
    def normalize_optional_path(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip()
        return normalized or None

    @field_validator("geoapify_base_url")
    @classmethod
    def normalize_geoapify_base_url(cls, value: str) -> str:
        normalized = value.strip().rstrip("/")
        if not normalized.startswith(("https://", "http://")):
            raise ValueError("GEOAPIFY_BASE_URL must be an HTTP(S) URL")
        return normalized

    @field_validator("overpass_api_url")
    @classmethod
    def normalize_overpass_api_url(cls, value: str) -> str:
        normalized = value.strip().rstrip("/")
        if not normalized.startswith(("https://", "http://")):
            raise ValueError("OVERPASS_API_URL must be an HTTP(S) URL")
        return normalized

    @property
    def sqlalchemy_database_url(self) -> str:
        """Select psycopg 3 even when Supabase returns a generic PG URL."""

        database_url = self.database_url.get_secret_value()
        if database_url.startswith("postgres://"):
            return database_url.replace("postgres://", "postgresql+psycopg://", 1)
        if database_url.startswith("postgresql://"):
            return database_url.replace("postgresql://", "postgresql+psycopg://", 1)
        return database_url

    @staticmethod
    def _optional_secret_value(value: SecretStr | None) -> str | None:
        return value.get_secret_value() if value is not None else None

    @property
    def google_places_api_key_value(self) -> str | None:
        """Return the Google Places key only at the backend provider boundary."""

        return self._optional_secret_value(self.google_places_api_key)

    @property
    def google_routes_api_key_value(self) -> str | None:
        """Return the Google Routes key only at the backend provider boundary."""

        return self._optional_secret_value(self.google_routes_api_key)

    @property
    def geoapify_api_key_value(self) -> str | None:
        """Return the Geoapify key only at the backend provider boundary."""

        return self._optional_secret_value(self.geoapify_api_key)


@lru_cache
def get_settings() -> Settings:
    """Return a cached settings instance for the process."""

    return Settings()  # type: ignore[call-arg]
