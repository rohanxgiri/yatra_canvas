"""Keep application startup in tests isolated from configured developer databases."""

import pytest
from sqlalchemy.pool import StaticPool
from sqlmodel import create_engine


@pytest.fixture(autouse=True)
def isolated_startup_database(monkeypatch):
    # Endpoint fixtures override request sessions, but FastAPI lifespan separately
    # calls create_db_and_tables(). Never let that touch a configured remote DB.
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    monkeypatch.setattr("app.database.get_engine", lambda: engine)
    yield
    engine.dispose()
