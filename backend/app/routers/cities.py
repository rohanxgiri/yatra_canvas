"""City API endpoints."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import and_, func, or_
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.core.config import Settings, get_settings
from app.database import get_session
from app.models import City
from app.schemas import (
    CityCreate,
    CityDetails,
    CityRead,
    CityResolve,
    CitySuggestion,
)
from app.services.geoapify_service import (
    GeoapifyConfigurationError,
    GeoapifyInvalidRequestError,
    GeoapifyService,
    GeoapifyTimeoutError,
    GeoapifyUnavailableError,
)

router = APIRouter(prefix="/cities", tags=["cities"])
SessionDependency = Annotated[Session, Depends(get_session)]
SettingsDependency = Annotated[Settings, Depends(get_settings)]


def get_geoapify_service(settings: SettingsDependency) -> GeoapifyService:
    """Build the Geoapify client from backend-only environment settings."""

    return GeoapifyService(settings.geoapify_api_key_value)


GeoapifyDependency = Annotated[
    GeoapifyService, Depends(get_geoapify_service)
]


def geoapify_http_error(error: Exception) -> HTTPException:
    """Translate service failures into stable API status codes."""

    if isinstance(error, GeoapifyInvalidRequestError):
        return HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(error),
        )
    if isinstance(error, GeoapifyTimeoutError):
        return HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT,
            detail=str(error),
        )
    if isinstance(error, GeoapifyConfigurationError):
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


@router.get("/autocomplete", response_model=list[CitySuggestion])
async def autocomplete_cities(
    geoapify: GeoapifyDependency,
    query: Annotated[str, Query(min_length=2, max_length=120)],
) -> list[CitySuggestion]:
    """Return normalized India city predictions from Geoapify."""

    normalized_query = query.strip()
    if len(normalized_query) < 2:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="Autocomplete query must contain at least 2 characters.",
        )

    try:
        results = await geoapify.autocomplete(
            query=normalized_query,
            location_type="city",
            country_code="in",
        )
        suggestions = []
        for res in results:
            if not res.city:
                continue
            description = res.formatted_address
            suggestions.append(
                CitySuggestion(
                    provider_place_id=res.provider_place_id,
                    name=res.city,
                    description=description,
                )
            )
        return suggestions
    except (
        GeoapifyConfigurationError,
        GeoapifyInvalidRequestError,
        GeoapifyTimeoutError,
        GeoapifyUnavailableError,
    ) as exc:
        raise geoapify_http_error(exc) from exc


@router.get(
    "/place-details/{provider_place_id}",
    response_model=CityDetails,
)
async def get_provider_place_details(
    provider_place_id: str,
    geoapify: GeoapifyDependency,
) -> CityDetails:
    """Return city fields extracted from one Geoapify Place Details result."""

    try:
        res = await geoapify.get_place_details(provider_place_id)
        if not res or not res.city:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Provider place could not be found.",
            )
        return CityDetails(
            name=res.city,
            state=res.state,
            country="India",  # Assuming India from autocomplete filter
            latitude=res.latitude,
            longitude=res.longitude,
            provider_place_id=res.provider_place_id,
        )
    except (
        GeoapifyConfigurationError,
        GeoapifyInvalidRequestError,
        GeoapifyTimeoutError,
        GeoapifyUnavailableError,
    ) as exc:
        raise geoapify_http_error(exc) from exc


@router.post("/resolve", response_model=CityRead)
def resolve_city(city_data: CityResolve, session: SessionDependency) -> City:
    """Return a matching normalized city, or persist it once."""

    identity_filters = [
        func.lower(City.name) == city_data.name.casefold(),
        func.lower(City.country) == city_data.country.casefold(),
        (
            City.state.is_(None)
            if city_data.state is None
            else func.lower(City.state) == city_data.state.casefold()
        ),
    ]
    if city_data.provider_place_id is not None:
        statement = select(City).where(
            or_(
                City.google_place_id == city_data.provider_place_id,
                and_(*identity_filters),
            )
        )
    else:
        statement = select(City).where(*identity_filters)
    existing_city = session.exec(statement).first()
    if existing_city is not None:
        return existing_city

    city = City.model_validate(city_data)
    if city_data.provider_place_id and not city.google_place_id:
        city.google_place_id = city_data.provider_place_id
    session.add(city)
    try:
        session.commit()
    except IntegrityError as exc:
        # Another request may have inserted the same provider city after the
        # initial lookup. Re-read before returning a safe conflict.
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
