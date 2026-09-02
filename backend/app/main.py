"""FastAPI application entry point."""

from contextlib import asynccontextmanager
from collections.abc import AsyncIterator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.database import create_db_and_tables
from app.routers import (
    cities,
    locations,
    places,
    route_geometry,
    route_optimization,
    saved_places,
    trips,
    weather_advisories,
)


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    """Initialize the current migration-free database schema at startup."""

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
)

app.include_router(cities.router)
app.include_router(places.router)
app.include_router(saved_places.router)
app.include_router(route_optimization.router)
app.include_router(route_geometry.router)
app.include_router(trips.router)
app.include_router(locations.router)
app.include_router(weather_advisories.router)


@app.get("/", tags=["status"])
def backend_status() -> dict[str, str]:
    """Return a lightweight service status response."""
    return {"status": "ok", "service": "YatraCanvas API"}
