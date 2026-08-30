"""Place API endpoints."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.core.config import Settings, get_settings
from app.database import get_session
from app.models import City, Place
from app.routers.cities import (
    get_google_places_service,
    google_places_http_error,
)
from app.schemas import (
    DiscoveryCategory,
    PlaceCreate,
    PlaceRead,
    RecommendationRead,
    RecommendationRequest,
)
from app.services.google_places_service import (
    GooglePlaceNotFoundError,
    GooglePlacesConfigurationError,
    GooglePlacesInvalidRequestError,
    GooglePlacesService,
    GooglePlacesTimeoutError,
    GooglePlacesUnavailableError,
)
from app.services.place_discovery_service import PlaceDiscoveryService
from app.services.recommendation_service import RecommendationService


router = APIRouter(tags=["places"])
SessionDependency = Annotated[Session, Depends(get_session)]
SettingsDependency = Annotated[Settings, Depends(get_settings)]
GooglePlacesDependency = Annotated[
    GooglePlacesService, Depends(get_google_places_service)
]


def get_place_discovery_service(
    settings: SettingsDependency,
) -> PlaceDiscoveryService:
    return PlaceDiscoveryService(settings)


PlaceDiscoveryDependency = Annotated[
    PlaceDiscoveryService, Depends(get_place_discovery_service)
]


def get_recommendation_service(
    discovery: PlaceDiscoveryDependency,
) -> RecommendationService:
    return RecommendationService(discovery)


RecommendationDependency = Annotated[
    RecommendationService, Depends(get_recommendation_service)
]


@router.post("/places", response_model=PlaceRead, status_code=status.HTTP_201_CREATED)
def create_place(place_data: PlaceCreate, session: SessionDependency) -> Place:
    """Create a place after verifying that its parent city exists."""

    if session.get(City, place_data.city_id) is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="City not found.",
        )

    place = Place.model_validate(place_data)
    session.add(place)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="The place could not be created because it conflicts with existing data.",
        ) from exc

    session.refresh(place)
    return place


@router.get("/cities/{city_id}/places", response_model=list[PlaceRead])
def list_city_places(
    city_id: UUID,
    session: SessionDependency,
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=500)] = 100,
) -> list[Place]:
    """Return the places belonging to a city."""

    if session.get(City, city_id) is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="City not found.",
        )

    statement = (
        select(Place)
        .where(Place.city_id == city_id)
        .order_by(Place.name)
        .offset(offset)
        .limit(limit)
    )
    return list(session.exec(statement).all())


@router.get(
    "/cities/{city_id}/discover-places",
    response_model=list[PlaceRead],
)
async def discover_city_places(
    city_id: UUID,
    category: Annotated[DiscoveryCategory, Query()],
    session: SessionDependency,
    google_places: GooglePlacesDependency,
    discovery: PlaceDiscoveryDependency,
) -> list[Place]:
    """Return cached places or refresh one city/category from Google."""

    city = session.get(City, city_id)
    if city is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="City not found.",
        )

    try:
        return await discovery.discover(
            session=session,
            city=city,
            category=category,
            google_places=google_places,
        )
    except (
        GooglePlacesConfigurationError,
        GooglePlacesInvalidRequestError,
        GooglePlaceNotFoundError,
        GooglePlacesTimeoutError,
        GooglePlacesUnavailableError,
    ) as exc:
        session.rollback()
        raise google_places_http_error(exc) from exc
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Nearby places could not be saved because of conflicting data.",
        ) from exc


@router.post(
    "/cities/{city_id}/recommendations",
    response_model=list[RecommendationRead],
)
async def recommend_city_places(
    city_id: UUID,
    recommendation_request: RecommendationRequest,
    session: SessionDependency,
    google_places: GooglePlacesDependency,
    recommendation: RecommendationDependency,
) -> list[RecommendationRead]:
    """Return deduplicated, ranked places for selected categories."""

    city = session.get(City, city_id)
    if city is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="City not found.",
        )

    try:
        return await recommendation.recommend(
            session=session,
            city=city,
            request=recommendation_request,
            google_places=google_places,
        )
    except (
        GooglePlacesConfigurationError,
        GooglePlacesInvalidRequestError,
        GooglePlaceNotFoundError,
        GooglePlacesTimeoutError,
        GooglePlacesUnavailableError,
    ) as exc:
        session.rollback()
        raise google_places_http_error(exc) from exc
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Recommendations could not be prepared because of conflicting data.",
        ) from exc
