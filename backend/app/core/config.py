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
        default="https://lz4.overpass-api.de/api/interpreter",
        validation_alias="OVERPASS_API_URL",
    )
    overpass_timeout_seconds: float = Field(
        default=25.0,
        gt=5,
        le=60,
        validation_alias="OVERPASS_TIMEOUT_SECONDS",
    )
    overpass_circuit_breaker_threshold: int = Field(
        default=3,
        ge=1,
        le=20,
        validation_alias="OVERPASS_CIRCUIT_BREAKER_THRESHOLD",
    )
    overpass_circuit_breaker_cooldown_seconds: float = Field(
        default=60.0,
        ge=5.0,
        le=600.0,
        validation_alias="OVERPASS_CIRCUIT_BREAKER_COOLDOWN_SECONDS",
    )
    overpass_radius_meters: int = Field(
        default=8000,
        ge=1000,
        le=50000,
        validation_alias="OVERPASS_RADIUS_METERS",
    )
    overpass_tourism_radius_meters: int = Field(
        default=15000,
        ge=1000,
        le=50000,
        validation_alias="OVERPASS_TOURISM_RADIUS_METERS",
    )
    overpass_heritage_radius_meters: int = Field(
        default=15000,
        ge=1000,
        le=50000,
        validation_alias="OVERPASS_HERITAGE_RADIUS_METERS",
    )
    overpass_religious_radius_meters: int = Field(
        default=10000,
        ge=1000,
        le=50000,
        validation_alias="OVERPASS_RELIGIOUS_RADIUS_METERS",
    )
    overpass_food_radius_meters: int = Field(
        default=8000,
        ge=1000,
        le=50000,
        validation_alias="OVERPASS_FOOD_RADIUS_METERS",
    )
    overpass_cafe_radius_meters: int = Field(
        default=8000,
        ge=1000,
        le=50000,
        validation_alias="OVERPASS_CAFE_RADIUS_METERS",
    )
    overpass_markets_radius_meters: int = Field(
        default=10000,
        ge=1000,
        le=50000,
        validation_alias="OVERPASS_MARKETS_RADIUS_METERS",
    )
    overpass_nature_radius_meters: int = Field(
        default=25000,
        ge=1000,
        le=50000,
        validation_alias="OVERPASS_NATURE_RADIUS_METERS",
    )
    overpass_tourism_limit: int = Field(
        default=60,
        ge=1,
        le=200,
        validation_alias="OVERPASS_TOURISM_LIMIT",
    )
    overpass_heritage_limit: int = Field(
        default=60,
        ge=1,
        le=200,
        validation_alias="OVERPASS_HERITAGE_LIMIT",
    )
    overpass_religious_limit: int = Field(
        default=40,
        ge=1,
        le=200,
        validation_alias="OVERPASS_RELIGIOUS_LIMIT",
    )
    overpass_food_limit: int = Field(
        default=50,
        ge=1,
        le=200,
        validation_alias="OVERPASS_FOOD_LIMIT",
    )
    overpass_cafe_limit: int = Field(
        default=40,
        ge=1,
        le=200,
        validation_alias="OVERPASS_CAFE_LIMIT",
    )
    overpass_markets_limit: int = Field(
        default=40,
        ge=1,
        le=200,
        validation_alias="OVERPASS_MARKETS_LIMIT",
    )
    overpass_nature_limit: int = Field(
        default=40,
        ge=1,
        le=200,
        validation_alias="OVERPASS_NATURE_LIMIT",
    )
    fsq_os_places_path: str | None = Field(
        default=None,
        validation_alias="FSQ_OS_PLACES_PATH",
    )
    audiala_dataset_path: str | None = Field(
        default="backend/app/data/audiala_places.json",
        validation_alias="AUDIALA_DATASET_PATH",
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
    place_discovery_cache_version: int = Field(
        default=1,
        ge=1,
        le=999,
        validation_alias="PLACE_DISCOVERY_CACHE_VERSION",
    )
    discovery_interactive_timeout_seconds: float = Field(
        default=12.0,
        ge=3.0,
        le=60.0,
        validation_alias="DISCOVERY_INTERACTIVE_TIMEOUT_SECONDS",
    )
    discovery_shallow_limit: int = Field(
        default=15,
        ge=5,
        le=50,
        validation_alias="DISCOVERY_SHALLOW_LIMIT",
    )
    discovery_stale_usable_hours: int = Field(
        default=168,
        ge=1,
        le=720,
        validation_alias="DISCOVERY_STALE_USABLE_HOURS",
    )
    discovery_min_usable_candidates_per_category: int = Field(
        default=6,
        ge=1,
        le=30,
        validation_alias="DISCOVERY_MIN_USABLE_CANDIDATES_PER_CATEGORY",
    )
    routing_provider: str = Field(
        default="osrm",
        validation_alias="ROUTING_PROVIDER",
    )
    openrouteservice_api_key: SecretStr | None = Field(
        default=None,
        validation_alias="OPENROUTESERVICE_API_KEY",
    )
    openrouteservice_base_url: str = Field(
        default="https://api.openrouteservice.org",
        validation_alias="OPENROUTESERVICE_BASE_URL",
    )
    openrouteservice_timeout_seconds: float = Field(
        default=10.0,
        gt=0,
        le=60,
        validation_alias="OPENROUTESERVICE_TIMEOUT_SECONDS",
    )
    osrm_router_url: str = Field(
        default="https://router.project-osrm.org",
        validation_alias="OSRM_ROUTER_URL",
    )
    osrm_timeout_seconds: float = Field(
        default=10.0,
        gt=0,
        le=60,
        validation_alias="OSRM_TIMEOUT_SECONDS",
    )
    route_geometry_cache_ttl_minutes: int = Field(
        default=60,
        ge=1,
        le=1440,
        validation_alias="ROUTE_GEOMETRY_CACHE_TTL_MINUTES",
    )
    weather_provider: str = Field(
        default="openmeteo",
        validation_alias="WEATHER_PROVIDER",
    )
    open_meteo_base_url: str = Field(
        default="https://api.open-meteo.com",
        validation_alias="OPEN_METEO_BASE_URL",
    )
    open_meteo_timeout_seconds: float = Field(
        default=10.0,
        gt=0,
        le=60,
        validation_alias="OPEN_METEO_TIMEOUT_SECONDS",
    )
    weather_cache_ttl_minutes: int = Field(
        default=60,
        ge=1,
        le=1440,
        validation_alias="WEATHER_CACHE_TTL_MINUTES",
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
        "google_routes_api_key",
        "geoapify_api_key",
        "openrouteservice_api_key",
    )
    @classmethod
    def normalize_optional_secret(cls, value: SecretStr | None) -> SecretStr | None:
        if value is None:
            return None
        normalized = value.get_secret_value().strip()
        return SecretStr(normalized) if normalized else None

    @field_validator("fsq_os_places_path", "audiala_dataset_path")
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

    @field_validator("openrouteservice_base_url")
    @classmethod
    def normalize_openrouteservice_base_url(cls, value: str) -> str:
        normalized = value.strip().rstrip("/")
        if not normalized.startswith(("https://", "http://")):
            raise ValueError("OPENROUTESERVICE_BASE_URL must be an HTTP(S) URL")
        return normalized

    @field_validator("osrm_router_url")
    @classmethod
    def normalize_osrm_router_url(cls, value: str) -> str:
        normalized = value.strip().rstrip("/")
        if not normalized.startswith(("https://", "http://")):
            raise ValueError("OSRM_ROUTER_URL must be an HTTP(S) URL")
        return normalized

    @field_validator("routing_provider")
    @classmethod
    def normalize_routing_provider(cls, value: str) -> str:
        normalized = value.strip().lower()
        if normalized not in ("osrm", "openrouteservice"):
            raise ValueError("ROUTING_PROVIDER must be 'osrm' or 'openrouteservice'")
        return normalized

    @field_validator("open_meteo_base_url")
    @classmethod
    def normalize_open_meteo_base_url(cls, value: str) -> str:
        normalized = value.strip().rstrip("/")
        if not normalized.startswith(("https://", "http://")):
            raise ValueError("OPEN_METEO_BASE_URL must be an HTTP(S) URL")
        return normalized

    @field_validator("weather_provider")
    @classmethod
    def normalize_weather_provider(cls, value: str) -> str:
        normalized = value.strip().lower()
        if normalized not in ("openmeteo",):
            raise ValueError("WEATHER_PROVIDER must be 'openmeteo'")
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
    def google_routes_api_key_value(self) -> str | None:
        """Return the Google Routes key only at the backend provider boundary."""

        return self._optional_secret_value(self.google_routes_api_key)

    @property
    def geoapify_api_key_value(self) -> str | None:
        """Return the Geoapify key only at the backend provider boundary."""

        return self._optional_secret_value(self.geoapify_api_key)

    @property
    def openrouteservice_api_key_value(self) -> str | None:
        """Return the openrouteservice key only at the backend provider boundary."""

        return self._optional_secret_value(self.openrouteservice_api_key)

    def overpass_radius_for_category(self, category: object) -> int:
        """Return the configured search radius in meters for a category."""

        key = getattr(category, "value", str(category)).lower()
        mapping = {
            "tourism": self.overpass_tourism_radius_meters,
            "heritage": self.overpass_heritage_radius_meters,
            "religious": self.overpass_religious_radius_meters,
            "food": self.overpass_food_radius_meters,
            "cafes": self.overpass_cafe_radius_meters,
            "cafe": self.overpass_cafe_radius_meters,
            "markets": self.overpass_markets_radius_meters,
            "nature": self.overpass_nature_radius_meters,
        }
        return mapping.get(key, self.overpass_radius_meters)

    def overpass_limit_for_category(self, category: object) -> int:
        """Return the configured discovery candidate limit for a category."""

        key = getattr(category, "value", str(category)).lower()
        mapping = {
            "tourism": self.overpass_tourism_limit,
            "heritage": self.overpass_heritage_limit,
            "religious": self.overpass_religious_limit,
            "food": self.overpass_food_limit,
            "cafes": self.overpass_cafe_limit,
            "cafe": self.overpass_cafe_limit,
            "markets": self.overpass_markets_limit,
            "nature": self.overpass_nature_limit,
        }
        return mapping.get(key, 40)


@lru_cache
def get_settings() -> Settings:
    """Return a cached settings instance for the process."""

    return Settings()  # type: ignore[call-arg]
