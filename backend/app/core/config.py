"""Application settings loaded from environment variables."""

from functools import lru_cache
from pathlib import Path

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


BACKEND_DIR = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    """Runtime settings.

    Secrets are intentionally loaded from the environment (or backend/.env) and
    must never be committed to source control.
    """

    database_url: str = Field(min_length=1, validation_alias="DATABASE_URL")
    google_places_api_key: str | None = Field(
        default=None,
        validation_alias="GOOGLE_PLACES_API_KEY",
    )

    model_config = SettingsConfigDict(
        env_file=BACKEND_DIR / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    @field_validator("database_url")
    @classmethod
    def validate_database_url(cls, value: str) -> str:
        value = value.strip()
        supported_schemes = (
            "postgres://",
            "postgresql://",
            "postgresql+psycopg://",
        )
        if not value.startswith(supported_schemes):
            raise ValueError("DATABASE_URL must be a PostgreSQL connection URL")
        return value

    @field_validator("google_places_api_key")
    @classmethod
    def normalize_google_places_api_key(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        return value or None

    @property
    def sqlalchemy_database_url(self) -> str:
        """Select psycopg 3 even when Supabase returns a generic PG URL."""

        if self.database_url.startswith("postgres://"):
            return self.database_url.replace(
                "postgres://", "postgresql+psycopg://", 1
            )
        if self.database_url.startswith("postgresql://"):
            return self.database_url.replace(
                "postgresql://", "postgresql+psycopg://", 1
            )
        return self.database_url


@lru_cache
def get_settings() -> Settings:
    """Return a cached settings instance for the process."""

    return Settings()  # type: ignore[call-arg]
