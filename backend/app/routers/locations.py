"""Normalized Google place search for trip start locations."""

from typing import Annotated, Literal

from fastapi import APIRouter, HTTPException, Query, status

from app.routers.cities import GooglePlacesDependency, google_places_http_error
from app.schemas import LocationDetails, LocationSuggestion
from app.services.google_places_service import (
    GooglePlaceNotFoundError,
    GooglePlacesConfigurationError,
    GooglePlacesInvalidRequestError,
    GooglePlacesTimeoutError,
    GooglePlacesUnavailableError,
)


router = APIRouter(prefix="/locations", tags=["locations"])


@router.get("/autocomplete", response_model=list[LocationSuggestion])
async def autocomplete_locations(
    google_places: GooglePlacesDependency,
    query: Annotated[str, Query(min_length=2, max_length=160)],
    kind: Annotated[Literal["hotel", "custom"], Query()] = "custom",
) -> list[LocationSuggestion]:
    normalized_query = query.strip()
    if len(normalized_query) < 2:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="Location query must contain at least 2 characters.",
        )
    try:
        return await google_places.autocomplete_locations(
            normalized_query,
            hotel_only=kind == "hotel",
        )
    except (
        GooglePlacesConfigurationError,
        GooglePlacesInvalidRequestError,
        GooglePlacesTimeoutError,
        GooglePlacesUnavailableError,
    ) as exc:
        raise google_places_http_error(exc) from exc


@router.get("/place-details/{google_place_id}", response_model=LocationDetails)
async def get_location_details(
    google_place_id: str,
    google_places: GooglePlacesDependency,
) -> LocationDetails:
    try:
        return await google_places.get_location_details(google_place_id)
    except (
        GooglePlacesConfigurationError,
        GooglePlacesInvalidRequestError,
        GooglePlaceNotFoundError,
        GooglePlacesTimeoutError,
        GooglePlacesUnavailableError,
    ) as exc:
        raise google_places_http_error(exc) from exc
