"""FastAPI application entry point."""

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.core.config import get_settings
from app.core.request_context import RequestIdMiddleware
from app.core.trip_access import require_trip_access
from app.database import create_db_and_tables
from app.routers import (
    admin,
    admin_operations,
    auth,
    cities,
    locations,
    places,
    route_geometry,
    route_optimization,
    saved_places,
    smart_replanning,
    trips,
    weather_advisories,
)

# httpx's INFO message contains the complete outbound URL, including query
# parameters. Provider credentials such as Geoapify's ``apiKey`` must never be
# emitted by application logging even when the root logger is configured at
# INFO for local diagnostics.
logging.getLogger("httpx").setLevel(logging.WARNING)
logging.getLogger("httpcore").setLevel(logging.WARNING)


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    """Initialize local development only; deployed databases use reviewed migrations."""

    if get_settings().app_env in {"development", "test"}:
        create_db_and_tables()
    yield


app = FastAPI(
    title="YatraCanvas API",
    description="Backend foundation for the YatraCanvas travel planning app.",
    version="0.1.0",
    lifespan=lifespan,
)

# Allow Flutter web (any localhost port) and the Android emulator to reach the
# API during local development.  Restrict origins before any public deployment.
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost",
        "http://127.0.0.1",
        # Flutter web dev server uses a random high port; allow all localhost
        # ports by accepting the wildcard below.  Replace with explicit origins
        # once the deployment URL is known.
        "http://localhost:*",
    ],
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
    # Flutter web needs the same refresh/pagination metadata as native clients.
    expose_headers=[
        "X-Request-ID",
        "X-Refresh-State",
        "X-Stale-Categories",
        "X-Next-Cursor",
    ],
)
app.add_middleware(RequestIdMiddleware)

app.include_router(auth.router)
app.include_router(admin.router)
app.include_router(admin_operations.router)
app.include_router(cities.router)
app.include_router(places.router)
app.include_router(saved_places.router, dependencies=[Depends(require_trip_access)])
app.include_router(
    route_optimization.router, dependencies=[Depends(require_trip_access)]
)
app.include_router(route_geometry.router, dependencies=[Depends(require_trip_access)])
app.include_router(trips.router, dependencies=[Depends(require_trip_access)])
app.include_router(locations.router)
app.include_router(
    weather_advisories.router, dependencies=[Depends(require_trip_access)]
)
app.include_router(smart_replanning.router, dependencies=[Depends(require_trip_access)])

admin_static_dir = Path(__file__).resolve().parent / "static" / "admin"
if admin_static_dir.exists():
    app.mount(
        "/admin", StaticFiles(directory=str(admin_static_dir), html=True), name="admin"
    )


@app.get("/", tags=["status"])
def backend_status() -> dict[str, str]:
    """Return a lightweight service status response."""
    return {"status": "ok", "service": "YatraCanvas API"}
