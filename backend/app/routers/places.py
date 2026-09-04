"""Place API endpoints."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.core.config import Settings, get_settings
from app.database import get_session
from app.models import City, Place
from app.schemas import (
    DiscoveryCategory,
    PlaceCreate,
    PlacePrefetchRequest,
    PlacePrefetchResponse,
    PlaceRead,
    RecommendationRead,
    RecommendationRequest,
)
from app.services.openstreetmap_discovery_service import (
    OpenStreetMapDiscoveryService,
)
from app.services.openstreetmap_places_service import (
    OpenStreetMapPlacesRateLimitError,
    OpenStreetMapPlacesService,
    OpenStreetMapPlacesTimeoutError,
    OpenStreetMapPlacesUnavailableError,
)
from app.services.audiala_places_provider import AudialaPlacesProvider
from app.services.canonical_place_service import CanonicalPlaceService
from app.services.city_place_prefetch_service import (
    CityPlacePrefetchService,
    PrefetchStage,
)
from app.services.geoapify_places_provider import GeoapifyPlacesProvider
from app.services.provider_circuit_breaker import ProviderCircuitBreaker
from app.services.recommendation_service import RecommendationService

router = APIRouter(tags=["places"])
SessionDependency = Annotated[Session, Depends(get_session)]
SettingsDependency = Annotated[Settings, Depends(get_settings)]

_overpass_circuit_breaker = ProviderCircuitBreaker(
    name="overpass",
    failure_threshold=3,
    cooldown_seconds=60.0,
)


def get_openstreetmap_places_service(
    settings: SettingsDependency,
) -> OpenStreetMapPlacesService:
    category_radii = {
        DiscoveryCategory.TOURISM: settings.overpass_tourism_radius_meters,
        DiscoveryCategory.HERITAGE: settings.overpass_heritage_radius_meters,
        DiscoveryCategory.RELIGIOUS: settings.overpass_religious_radius_meters,
        DiscoveryCategory.FOOD: settings.overpass_food_radius_meters,
        DiscoveryCategory.CAFES: settings.overpass_cafe_radius_meters,
    }
    category_limits = {
        DiscoveryCategory.TOURISM: settings.overpass_tourism_limit,
        DiscoveryCategory.HERITAGE: settings.overpass_heritage_limit,
        DiscoveryCategory.RELIGIOUS: settings.overpass_religious_limit,
        DiscoveryCategory.FOOD: settings.overpass_food_limit,
        DiscoveryCategory.CAFES: settings.overpass_cafe_limit,
    }
    return OpenStreetMapPlacesService(
        settings.overpass_api_url,
        timeout_seconds=settings.overpass_timeout_seconds,
        radius_meters=settings.overpass_radius_meters,
        category_radii=category_radii,
        category_limits=category_limits,
        circuit_breaker=_overpass_circuit_breaker,
    )


OpenStreetMapPlacesDependency = Annotated[
    OpenStreetMapPlacesService, Depends(get_openstreetmap_places_service)
]


def get_audiala_places_provider(
    settings: SettingsDependency,
) -> AudialaPlacesProvider:
    return AudialaPlacesProvider(settings.audiala_dataset_path)


AudialaPlacesDependency = Annotated[
    AudialaPlacesProvider, Depends(get_audiala_places_provider)
]


def get_geoapify_places_provider(
    settings: SettingsDependency,
) -> GeoapifyPlacesProvider:
    return GeoapifyPlacesProvider(
        settings.geoapify_api_key_value,
        base_url=settings.geoapify_base_url,
        timeout_seconds=settings.geoapify_timeout_seconds,
    )


GeoapifyPlacesDependency = Annotated[
    GeoapifyPlacesProvider, Depends(get_geoapify_places_provider)
]


def get_canonical_place_service() -> CanonicalPlaceService:
    return CanonicalPlaceService()


CanonicalPlaceDependency = Annotated[
    CanonicalPlaceService, Depends(get_canonical_place_service)
]


def get_openstreetmap_discovery_service(
    settings: SettingsDependency,
    provider: OpenStreetMapPlacesDependency,
    audiala_provider: AudialaPlacesDependency,
    canonical_service: CanonicalPlaceDependency,
    geoapify_provider: GeoapifyPlacesDependency,
) -> OpenStreetMapDiscoveryService:
    return OpenStreetMapDiscoveryService(
        settings,
        provider,
        audiala_provider,
        canonical_service=canonical_service,
        geoapify_provider=geoapify_provider,
    )


OpenStreetMapDiscoveryDependency = Annotated[
    OpenStreetMapDiscoveryService,
    Depends(get_openstreetmap_discovery_service),
]


def get_city_place_prefetch_service(
    discovery: OpenStreetMapDiscoveryDependency,
) -> CityPlacePrefetchService:
    return CityPlacePrefetchService(discovery)


PrefetchDependency = Annotated[
    CityPlacePrefetchService, Depends(get_city_place_prefetch_service)
]


def get_recommendation_service(
    discovery: OpenStreetMapDiscoveryDependency,
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
    discovery: OpenStreetMapDiscoveryDependency,
) -> list[Place]:
    """Return cached places or refresh one city/category from OpenStreetMap."""

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
        )
    except OpenStreetMapPlacesRateLimitError as exc:
        session.rollback()
        headers = {"Retry-After": exc.retry_after} if exc.retry_after else None
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=str(exc),
            headers=headers,
        ) from exc
    except OpenStreetMapPlacesTimeoutError as exc:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT,
            detail=str(exc),
        ) from exc
    except OpenStreetMapPlacesUnavailableError as exc:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc
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
        )
    except OpenStreetMapPlacesRateLimitError as exc:
        session.rollback()
        headers = {"Retry-After": exc.retry_after} if exc.retry_after else None
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=str(exc),
            headers=headers,
        ) from exc
    except OpenStreetMapPlacesTimeoutError as exc:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT,
            detail=str(exc),
        ) from exc
    except OpenStreetMapPlacesUnavailableError as exc:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Recommendations could not be prepared because of conflicting data.",
        ) from exc


@router.post(
    "/places/prefetch",
    response_model=PlacePrefetchResponse,
    status_code=status.HTTP_200_OK,
)
async def prefetch_city_places(
    prefetch_request: PlacePrefetchRequest,
    session: SessionDependency,
    prefetch_service: PrefetchDependency,
) -> PlacePrefetchResponse:
    """Pre-warm candidate POIs in background when destination or interests are confirmed."""

    city = session.get(City, prefetch_request.city_id)
    if city is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="City not found.",
        )

    stage = (
        PrefetchStage.DESTINATION_CONFIRMED
        if prefetch_request.stage == "destination_confirmed"
        else PrefetchStage.INTERESTS_CONFIRMED
    )

    cat_enums: list[DiscoveryCategory] | None = None
    if prefetch_request.categories:
        cat_enums = []
        for c_str in prefetch_request.categories:
            try:
                cat_enums.append(DiscoveryCategory(c_str))
            except ValueError:
                pass

    summary = await prefetch_service.prefetch(
        session=session,
        city=city,
        stage=stage,
        categories=cat_enums,
    )

    return PlacePrefetchResponse(
        city_id=summary.city_id,
        city_name=summary.city_name,
        stage=summary.stage.value,
        categories_requested=summary.categories_requested,
        categories_skipped_sufficient=summary.categories_skipped_sufficient,
        categories_enriched=summary.categories_enriched,
        duplicate_refreshes_prevented=summary.duplicate_refreshes_prevented,
    )
