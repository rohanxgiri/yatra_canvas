import logging
from typing import Annotated
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, col, select

from app.core.config import Settings, get_settings
from app.database import get_session
from app.models import City, Place
from app.schemas import (
    DiscoveryCategory,
    PlaceCreate,
    PlacePrefetchRequest,
    PlacePrefetchResponse,
    PlaceRead,
    PlaceResolveRequest,
    PlaceSearchResult,
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
from app.services.geoapify_service import GeoapifyService
from app.services.place_deduplication_service import (
    haversine_distance_meters,
    normalize_name_for_dedupe,
)
from app.services.provider_circuit_breaker import ProviderCircuitBreaker
from app.services.recommendation_service import RecommendationService

logger = logging.getLogger(__name__)

router = APIRouter(tags=["places"])
SessionDependency = Annotated[Session, Depends(get_session)]
SettingsDependency = Annotated[Settings, Depends(get_settings)]


def get_geoapify_service(settings: SettingsDependency) -> GeoapifyService:
    return GeoapifyService(
        settings.geoapify_api_key_value,
        base_url=settings.geoapify_base_url,
        timeout_seconds=settings.geoapify_timeout_seconds,
        cache_ttl_seconds=settings.geoapify_autocomplete_cache_ttl_seconds,
    )


GeoapifyDependency = Annotated[GeoapifyService, Depends(get_geoapify_service)]

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


@router.get(
    "/cities/{city_id}/places/search",
    response_model=list[PlaceSearchResult],
)
async def search_city_places(
    city_id: UUID,
    query: Annotated[str, Query(min_length=1, max_length=160)],
    session: SessionDependency,
    geoapify_service: GeoapifyDependency,
    limit: Annotated[int, Query(ge=1, le=20)] = 10,
) -> list[PlaceSearchResult]:
    """Search for places within or near a city using database and Geoapify."""
    city = session.get(City, city_id)
    if city is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="City not found.",
        )

    clean_query = " ".join(query.split())
    if not clean_query:
        return []

    results: list[PlaceSearchResult] = []
    seen_names: set[str] = set()

    # 1. Search existing stored places for this city
    db_places = session.exec(
        select(Place)
        .where(Place.city_id == city_id)
        .where(col(Place.name).ilike(f"%{clean_query}%"))
        .limit(limit)
    ).all()

    for p in db_places:
        norm = normalize_name_for_dedupe(p.name)
        seen_names.add(norm)
        dist = haversine_distance_meters(city.latitude, city.longitude, p.latitude, p.longitude)
        results.append(
            PlaceSearchResult(
                name=p.name,
                address=None,
                latitude=p.latitude,
                longitude=p.longitude,
                category=p.category,
                distance_meters=round(dist, 1),
                place_id=p.id,
                source="database",
            )
        )

    # 2. Query Geoapify autocomplete if remaining capacity
    remaining = limit - len(results)
    if remaining > 0 and len(clean_query) >= 3:
        try:
            geo_limit = max(1, min(10, remaining))
            geo_results = await geoapify_service.autocomplete(
                clean_query,
                country_code="in",
                latitude=city.latitude,
                longitude=city.longitude,
                limit=geo_limit,
            )
            for g in geo_results:
                norm = normalize_name_for_dedupe(g.name)
                if norm in seen_names:
                    continue
                dist = haversine_distance_meters(city.latitude, city.longitude, g.latitude, g.longitude)
                # Keep within destination radius (~50km)
                if dist > 50000.0:
                    continue
                seen_names.add(norm)
                results.append(
                    PlaceSearchResult(
                        name=g.name,
                        address=g.formatted_address,
                        latitude=g.latitude,
                        longitude=g.longitude,
                        category="sightseeing",
                        distance_meters=round(dist, 1),
                        place_id=None,
                        external_place_id=g.provider_place_id,
                        source="geoapify",
                    )
                )
                if len(results) >= limit:
                    break
        except Exception as exc:
            logger.warning("Geoapify place search failed gracefully: %s", exc)

    return results[:limit]


@router.post(
    "/cities/{city_id}/places/resolve",
    response_model=PlaceRead,
    status_code=status.HTTP_200_OK,
)
def resolve_manual_place(
    city_id: UUID,
    request: PlaceResolveRequest,
    session: SessionDependency,
    canonical_service: CanonicalPlaceDependency,
) -> Place:
    """Resolve or create a canonical Place entity from a search result."""
    city = session.get(City, city_id)
    if city is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="City not found.",
        )

    cat_str = request.category or "sightseeing"
    try:
        disc_cat = DiscoveryCategory(cat_str)
    except ValueError:
        disc_cat = DiscoveryCategory.TOURISM

    ext_id = request.external_place_id or f"manual:{uuid4()}"
    src_name = "geoapify" if request.external_place_id else "manual"
    licence = "Commercial" if request.external_place_id else "Proprietary"

    place, _ = canonical_service.resolve_or_create_place(
        session=session,
        city=city,
        category=disc_cat,
        name=request.name.strip(),
        latitude=request.latitude,
        longitude=request.longitude,
        external_place_id=ext_id,
        source_name=src_name,
        licence_identifier=licence,
    )
    session.commit()
    session.refresh(place)
    return place

