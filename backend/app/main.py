"""FastAPI application entry point."""

from contextlib import asynccontextmanager
from collections.abc import AsyncIterator

from fastapi import FastAPI

from app.database import create_db_and_tables
from app.routers import cities, places


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

app.include_router(cities.router)
app.include_router(places.router)


@app.get("/", tags=["status"])
def backend_status() -> dict[str, str]:
    """Return a lightweight service status response."""
    return {"status": "ok", "service": "YatraCanvas API"}
