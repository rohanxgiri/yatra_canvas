"""Provider-neutral runtime location autocomplete endpoint."""

from functools import lru_cache
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.config import get_settings
from app.schemas import LocationAutocompleteResponse
from app.services.geoapify_service import (
    GeoapifyConfigurationError,
    GeoapifyInvalidRequestError,
    GeoapifyRateLimitError,
    GeoapifyService,
    GeoapifyTimeoutError,
    GeoapifyUnavailableError,
)
from app.services.location_autocomplete_provider import (
    LocationAutocompleteProvider,
)

router = APIRouter(prefix="/locations", tags=["locations"])


@lru_cache
def _cached_geoapify_service() -> GeoapifyService:
    settings = get_settings()
    return GeoapifyService(
        settings.geoapify_api_key_value,
        base_url=settings.geoapify_base_url,
        timeout_seconds=settings.geoapify_timeout_seconds,
        cache_ttl_seconds=settings.geoapify_autocomplete_cache_ttl_seconds,
    )


def get_location_autocomplete_provider() -> LocationAutocompleteProvider:
    return _cached_geoapify_service()


LocationProviderDependency = Annotated[
    LocationAutocompleteProvider,
    Depends(get_location_autocomplete_provider),
]


@router.get("/autocomplete", response_model=LocationAutocompleteResponse)
async def autocomplete_locations(
    provider: LocationProviderDependency,
    query: Annotated[str, Query(min_length=3, max_length=160)],
    location_type: Annotated[
        Literal[
            "country",
            "state",
            "city",
            "postcode",
            "street",
            "amenity",
            "locality",
        ]
        | None,
        Query(alias="type"),
    ] = None,
    country_code: Annotated[str, Query(min_length=2, max_length=2)] = "in",
    latitude: Annotated[float | None, Query(ge=-90, le=90)] = None,
    longitude: Annotated[float | None, Query(ge=-180, le=180)] = None,
    limit: Annotated[int, Query(ge=1, le=10)] = 5,
) -> LocationAutocompleteResponse:
    normalized_query = " ".join(query.split())
    if len(normalized_query) < 3:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="Location query must contain at least 3 characters.",
        )
    if (latitude is None) != (longitude is None):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="Latitude and longitude must be supplied together.",
        )
    try:
        results = await provider.autocomplete(
            normalized_query,
            location_type=location_type,
            country_code=country_code,
            latitude=latitude,
            longitude=longitude,
            limit=limit,
        )
        return LocationAutocompleteResponse(results=results)
    except GeoapifyInvalidRequestError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except GeoapifyConfigurationError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except GeoapifyTimeoutError as exc:
        raise HTTPException(status_code=504, detail=str(exc)) from exc
    except GeoapifyRateLimitError as exc:
        headers = {"Retry-After": exc.retry_after} if exc.retry_after else None
        raise HTTPException(status_code=429, detail=str(exc), headers=headers) from exc
    except GeoapifyUnavailableError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
