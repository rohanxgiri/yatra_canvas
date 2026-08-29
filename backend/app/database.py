"""Database engine setup and FastAPI session dependency."""

from collections.abc import Generator
from functools import lru_cache

from sqlalchemy.engine import Engine
from sqlmodel import Session, SQLModel, create_engine

from app.core.config import get_settings


@lru_cache
def get_engine() -> Engine:
    """Create one connection-pool-backed engine per application process."""

    settings = get_settings()
    return create_engine(
        settings.sqlalchemy_database_url,
        pool_pre_ping=True,
    )


def create_db_and_tables() -> None:
    """Create missing tables for the migration-free foundation phase."""

    # Importing the package registers every table with SQLModel.metadata.
    import app.models  # noqa: F401

    SQLModel.metadata.create_all(get_engine())


def get_session() -> Generator[Session, None, None]:
    """Yield a short-lived database session for one API request."""

    with Session(get_engine()) as session:
        yield session
