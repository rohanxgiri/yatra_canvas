"""City API endpoints."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import or_
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.core.config import Settings, get_settings
from app.database import get_session
from app.models import City
from app.schemas import (
    CityCreate,
    CityRead,
    CityResolve,
    GoogleCitySuggestion,
    GooglePlaceDetails,
)
from app.services.google_places_service import (
    GooglePlaceNotFoundError,
    GooglePlacesConfigurationError,
    GooglePlacesInvalidRequestError,
    GooglePlacesService,
    GooglePlacesTimeoutError,
    GooglePlacesUnavailableError,
)

router = APIRouter(prefix="/cities", tags=["cities"])
SessionDependency = Annotated[Session, Depends(get_session)]
SettingsDependency = Annotated[Settings, Depends(get_settings)]


def get_google_places_service(settings: SettingsDependency) -> GooglePlacesService:
    """Build the Google client from backend-only environment settings."""

    return GooglePlacesService(settings.google_places_api_key_value)


GooglePlacesDependency = Annotated[
    GooglePlacesService, Depends(get_google_places_service)
]


def google_places_http_error(error: Exception) -> HTTPException:
    """Translate service failures into stable API status codes."""

    if isinstance(error, GooglePlacesInvalidRequestError):
        return HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(error),
        )
    if isinstance(error, GooglePlaceNotFoundError):
        return HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(error),
        )
    if isinstance(error, GooglePlacesTimeoutError):
        return HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT,
            detail=str(error),
        )
    if isinstance(error, GooglePlacesConfigurationError):
        return HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(error),
        )
    return HTTPException(
        status_code=status.HTTP_502_BAD_GATEWAY,
        detail=str(error),
    )


@router.post("", response_model=CityRead, status_code=status.HTTP_201_CREATED)
def create_city(city_data: CityCreate, session: SessionDependency) -> City:
    """Create and persist a city."""

    city = City.model_validate(city_data)
    session.add(city)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                "The city could not be created because it conflicts with "
                "existing data."
            ),
        ) from exc

    session.refresh(city)
    return city


@router.get("", response_model=list[CityRead])
def list_cities(
    session: SessionDependency,
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=500)] = 100,
) -> list[City]:
    """Return cities in name order with simple pagination."""

    statement = select(City).order_by(City.name).offset(offset).limit(limit)
    return list(session.exec(statement).all())


@router.get("/autocomplete", response_model=list[GoogleCitySuggestion])
async def autocomplete_cities(
    google_places: GooglePlacesDependency,
    query: Annotated[str, Query(min_length=2, max_length=120)],
) -> list[GoogleCitySuggestion]:
    """Return normalized India city predictions from Google Places."""

    normalized_query = query.strip()
    if len(normalized_query) < 2:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="Autocomplete query must contain at least 2 characters.",
        )

    try:
        return await google_places.autocomplete_cities(normalized_query)
    except (
        GooglePlacesConfigurationError,
        GooglePlacesInvalidRequestError,
        GooglePlacesTimeoutError,
        GooglePlacesUnavailableError,
    ) as exc:
        raise google_places_http_error(exc) from exc


@router.get(
    "/place-details/{google_place_id}",
    response_model=GooglePlaceDetails,
)
async def get_google_place_details(
    google_place_id: str,
    google_places: GooglePlacesDependency,
) -> GooglePlaceDetails:
    """Return city fields extracted from one Google Place Details result."""

    try:
        return await google_places.get_place_details(google_place_id)
    except (
        GooglePlacesConfigurationError,
        GooglePlacesInvalidRequestError,
        GooglePlaceNotFoundError,
        GooglePlacesTimeoutError,
        GooglePlacesUnavailableError,
    ) as exc:
        raise google_places_http_error(exc) from exc


@router.post("/resolve", response_model=CityRead)
def resolve_city(city_data: CityResolve, session: SessionDependency) -> City:
    """Return the Google city already stored, or create it once."""

    statement = select(City).where(City.google_place_id == city_data.google_place_id)
    existing_city = session.exec(statement).first()
    if existing_city is not None:
        return existing_city

    city = City.model_validate(city_data)
    session.add(city)
    try:
        session.commit()
    except IntegrityError as exc:
        # Another request may have inserted the same Google city after our
        # initial lookup. The unique constraint makes that race safe.
        session.rollback()
        existing_city = session.exec(statement).first()
        if existing_city is not None:
            return existing_city
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                "The city could not be resolved because it conflicts with "
                "existing data."
            ),
        ) from exc

    session.refresh(city)
    return city


@router.get("/search", response_model=list[CityRead])
def search_cities(
    session: SessionDependency,
    query: Annotated[str, Query(min_length=1, max_length=120)],
) -> list[City]:
    """Search stored cities by a partial, case-insensitive name or state."""

    normalized_query = query.strip()
    if not normalized_query:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="Search query must not be blank.",
        )

    escaped_query = (
        normalized_query.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    )
    pattern = f"%{escaped_query}%"
    statement = (
        select(City)
        .where(
            or_(
                City.name.ilike(pattern, escape="\\"),
                City.state.ilike(pattern, escape="\\"),
            )
        )
        .order_by(City.name, City.state, City.country)
        .limit(50)
    )
    return list(session.exec(statement).all())


@router.get("/{city_id}", response_model=CityRead)
def get_city(city_id: UUID, session: SessionDependency) -> City:
    """Return one city or a clear 404 response."""

    city = session.get(City, city_id)
    if city is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="City not found.",
        )
    return city
