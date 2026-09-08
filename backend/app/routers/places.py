import asyncio
import logging
from functools import lru_cache
from typing import Annotated
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.engine import Engine
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
from app.services.audiala_places_provider import AudialaPlacesProvider
from app.services.canonical_place_service import CanonicalPlaceService
from app.services.city_place_prefetch_service import (
    SHALLOW_PREFETCH_CATEGORIES,
    CityPlacePrefetchService,
    PrefetchStage,
)
from app.services.geoapify_places_provider import GeoapifyPlacesProvider
from app.services.geoapify_service import GeoapifyService
from app.services.openstreetmap_discovery_service import (
    OpenStreetMapDiscoveryService,
)
from app.services.openstreetmap_places_service import (
    OpenStreetMapPlacesRateLimitError,
    OpenStreetMapPlacesService,
    OpenStreetMapPlacesTimeoutError,
    OpenStreetMapPlacesUnavailableError,
)
from app.services.place_deduplication_service import (
    haversine_distance_meters,
    normalize_name_for_dedupe,
)
from app.services.progressive_prefetch_coordinator import (
    PrefetchState,
    ProgressivePrefetchCoordinator,
)
from app.services.provider_circuit_breaker import ProviderCircuitBreaker
from app.services.recommendation_service import RecommendationService

logger = logging.getLogger(__name__)

router = APIRouter(tags=["places"])
SessionDependency = Annotated[Session, Depends(get_session)]
SettingsDependency = Annotated[Settings, Depends(get_settings)]


class _CityNotFoundError(Exception):
    pass


def _load_city_identity(engine: Engine, city_id: UUID) -> tuple[UUID, str]:
    with Session(engine) as worker_session:
        city = worker_session.get(City, city_id)
        if city is None:
            raise _CityNotFoundError
        return city.id, city.name


def _recommend_in_worker(
    engine: Engine,
    city_id: UUID,
    request: RecommendationRequest,
    recommendation: RecommendationService,
) -> list[RecommendationRead]:
    with Session(engine) as worker_session:
        city = worker_session.get(City, city_id)
        if city is None:
            raise _CityNotFoundError
        return asyncio.run(
            recommendation.recommend(
                session=worker_session,
                city=city,
                request=request,
            )
        )


def get_geoapify_service(settings: SettingsDependency) -> GeoapifyService:
    return GeoapifyService(
        settings.geoapify_api_key_value,
        base_url=settings.geoapify_base_url,
        timeout_seconds=settings.geoapify_timeout_seconds,
        cache_ttl_seconds=settings.geoapify_autocomplete_cache_ttl_seconds,
    )


GeoapifyDependency = Annotated[GeoapifyService, Depends(get_geoapify_service)]


@lru_cache(maxsize=8)
def _get_overpass_circuit_breaker(
    failure_threshold: int,
    cooldown_seconds: float,
) -> ProviderCircuitBreaker:
    """Share provider health across requests with the active settings."""

    return ProviderCircuitBreaker(
        name="overpass",
        failure_threshold=failure_threshold,
        cooldown_seconds=cooldown_seconds,
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
        circuit_breaker=_get_overpass_circuit_breaker(
            settings.overpass_circuit_breaker_threshold,
            settings.overpass_circuit_breaker_cooldown_seconds,
        ),
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


@lru_cache(maxsize=1)
def get_progressive_prefetch_coordinator() -> ProgressivePrefetchCoordinator:
    return ProgressivePrefetchCoordinator()


PrefetchCoordinatorDependency = Annotated[
    ProgressivePrefetchCoordinator, Depends(get_progressive_prefetch_coordinator)
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
    coordinator: PrefetchCoordinatorDependency,
) -> list[RecommendationRead]:
    """Return deduplicated, ranked places for selected categories."""

    try:
        categories_to_join = list(recommendation_request.categories)
        if (
            recommendation_request.category_filter is not None
            and recommendation_request.category_filter not in categories_to_join
        ):
            categories_to_join.append(recommendation_request.category_filter)
        await coordinator.join_active(city_id, categories_to_join)
        return await asyncio.to_thread(
            _recommend_in_worker,
            session.get_bind(),
            city_id,
            recommendation_request,
            recommendation,
        )
    except _CityNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="City not found.",
        ) from exc
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
    status_code=status.HTTP_202_ACCEPTED,
)
async def prefetch_city_places(
    prefetch_request: PlacePrefetchRequest,
    session: SessionDependency,
    discovery: OpenStreetMapDiscoveryDependency,
    coordinator: PrefetchCoordinatorDependency,
) -> PlacePrefetchResponse:
    """Enqueue staged prefetch and return before provider work completes."""

    background_engine = session.get_bind()
    try:
        city_id, city_name = await asyncio.to_thread(
            _load_city_identity,
            background_engine,
            prefetch_request.city_id,
        )
    except _CityNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="City not found.",
        ) from exc

    stage = PrefetchStage(prefetch_request.stage)

    cat_enums: list[DiscoveryCategory] | None = None
    if prefetch_request.categories:
        cat_enums = []
        for c_str in prefetch_request.categories:
            try:
                cat_enums.append(DiscoveryCategory(c_str))
            except ValueError:
                pass

    if (
        stage == PrefetchStage.DESTINATION_CONFIRMED
        or stage == PrefetchStage.INTERESTS_CONFIRMED
    ):
        requested_categories = cat_enums or list(SHALLOW_PREFETCH_CATEGORIES)
    else:
        requested_categories = []

    async def run_prefetch(categories: list[DiscoveryCategory]):
        with Session(background_engine) as background_session:
            background_city = background_session.get(City, city_id)
            if background_city is None:
                raise RuntimeError("City was removed before prefetch started.")
            return await CityPlacePrefetchService(discovery).prefetch(
                session=background_session,
                city=background_city,
                stage=stage,
                categories=categories,
            )

    prefetch_state, enqueued, reused = coordinator.enqueue(
        city_id=city_id,
        city_name=city_name,
        stage=stage,
        categories=requested_categories,
        runner=run_prefetch if requested_categories else None,
        offload=bool(requested_categories),
    )
    return _prefetch_response(
        prefetch_state,
        stage=stage,
        requested=[category.value for category in requested_categories],
        enqueued=enqueued,
        reused=reused,
    )


@router.get(
    "/places/prefetch/{city_id}",
    response_model=PlacePrefetchResponse,
)
def get_prefetch_state(
    city_id: UUID,
    session: SessionDependency,
    coordinator: PrefetchCoordinatorDependency,
) -> PlacePrefetchResponse:
    city = session.get(City, city_id)
    if city is None:
        raise HTTPException(status_code=404, detail="City not found.")
    prefetch_state = coordinator.get_state(city_id) or PrefetchState(
        city_id=city.id, city_name=city.name
    )
    return _prefetch_response(
        prefetch_state,
        stage=PrefetchStage.DESTINATION_CONFIRMED,
        requested=[],
        enqueued=[],
        reused=[],
    )


def _prefetch_response(
    prefetch_state: PrefetchState,
    *,
    stage: PrefetchStage,
    requested: list[str],
    enqueued: list[str],
    reused: list[str],
) -> PlacePrefetchResponse:
    return PlacePrefetchResponse(
        city_id=prefetch_state.city_id,
        city_name=prefetch_state.city_name,
        stage=stage.value,
        categories_requested=requested,
        status=prefetch_state.status.value,
        categories_enqueued=enqueued,
        categories_reused=reused,
        categories_loaded=sorted(prefetch_state.categories_loaded),
        completed_stages=sorted(prefetch_state.completed_stages),
        failed_stages=sorted(prefetch_state.failed_stages),
        poi_count=prefetch_state.poi_count,
        started_at=prefetch_state.started_at,
        last_updated=prefetch_state.last_updated,
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
        dist = haversine_distance_meters(
            city.latitude, city.longitude, p.latitude, p.longitude
        )
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
                dist = haversine_distance_meters(
                    city.latitude, city.longitude, g.latitude, g.longitude
                )
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
