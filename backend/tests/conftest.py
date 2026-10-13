"""Keep application startup in tests isolated from configured developer databases."""

import pytest
from sqlalchemy.pool import StaticPool
from sqlmodel import create_engine


@pytest.fixture(autouse=True)
def isolated_startup_database(monkeypatch, request):
    from app.core.config import get_settings

    if request.node.path.name not in {"test_config.py", "test_database_safety.py"}:
        monkeypatch.setenv("APP_ENV", "test")
        monkeypatch.setenv("ALLOW_DEV_GUEST", "false")
    get_settings.cache_clear()
    # Endpoint fixtures override request sessions, but FastAPI lifespan separately
    # calls create_db_and_tables(). Never let that touch a configured remote DB.
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    monkeypatch.setattr("app.database.get_engine", lambda: engine)
    # External image enrichment is covered with mocked providers in focused
    # tests; API tests must remain offline and deterministic.
    monkeypatch.setattr(
        "app.routers.places.schedule_place_image_enrichment",
        lambda *args, **kwargs: None,
    )
    yield
    get_settings.cache_clear()
    engine.dispose()
