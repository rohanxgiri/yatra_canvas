"""Google Places API (New) client and response normalization."""

from typing import Any
from urllib.parse import quote

import httpx

from app.schemas import (
    GoogleCitySuggestion,
    GoogleNearbyPlace,
    GooglePlaceDetails,
    LocationDetails,
    LocationSuggestion,
)


AUTOCOMPLETE_URL = "https://places.googleapis.com/v1/places:autocomplete"
PLACE_DETAILS_URL = "https://places.googleapis.com/v1/places/{place_id}"
NEARBY_SEARCH_URL = "https://places.googleapis.com/v1/places:searchNearby"


class GooglePlacesServiceError(Exception):
    """Base exception for normalized Google Places failures."""


class GooglePlacesConfigurationError(GooglePlacesServiceError):
    """Raised when the backend has no Google Places API key."""


class GooglePlacesInvalidRequestError(GooglePlacesServiceError):
    """Raised when Google rejects an invalid request."""


class GooglePlaceNotFoundError(GooglePlacesServiceError):
    """Raised when a Google Place ID is invalid or no longer available."""


class GooglePlacesTimeoutError(GooglePlacesServiceError):
    """Raised when Google does not respond before the configured timeout."""


class GooglePlacesUnavailableError(GooglePlacesServiceError):
    """Raised for credentials, quota, network, or upstream service failures."""


class GooglePlacesService:
    """Call Places API (New) without exposing credentials or raw responses."""

    def __init__(
        self,
        api_key: str | None,
        *,
        client: httpx.AsyncClient | None = None,
        timeout_seconds: float = 8.0,
    ) -> None:
        self._api_key = api_key.strip() if api_key else None
        self._client = client
        self._timeout = httpx.Timeout(timeout_seconds)

    async def autocomplete_cities(
        self, query: str
    ) -> list[GoogleCitySuggestion]:
        """Return India-restricted city predictions in an app-owned schema."""

        normalized_query = query.strip()
        if len(normalized_query) < 2:
            raise GooglePlacesInvalidRequestError(
                "City autocomplete query must contain at least 2 characters."
            )

        response = await self._request(
            "POST",
            AUTOCOMPLETE_URL,
            headers={
                **self._auth_headers(),
                "Content-Type": "application/json",
                "X-Goog-FieldMask": (
                    "suggestions.placePrediction.placeId,"
                    "suggestions.placePrediction.text.text,"
                    "suggestions.placePrediction.structuredFormat.mainText.text"
                ),
            },
            json={
                "input": normalized_query,
                "includedPrimaryTypes": ["(cities)"],
                "includedRegionCodes": ["in"],
                "languageCode": "en",
                "regionCode": "in",
            },
        )
        self._raise_for_status(response)

        try:
            payload = response.json()
        except ValueError as exc:
            raise GooglePlacesUnavailableError(
                "Google Places returned an invalid autocomplete response."
            ) from exc
        if not isinstance(payload, dict):
            raise GooglePlacesUnavailableError(
                "Google Places returned an invalid autocomplete response."
            )

        suggestions: list[GoogleCitySuggestion] = []
        seen_place_ids: set[str] = set()
        raw_suggestions = payload.get("suggestions", [])
        if not isinstance(raw_suggestions, list):
            raise GooglePlacesUnavailableError(
                "Google Places returned an invalid autocomplete response."
            )
        for item in raw_suggestions:
            if not isinstance(item, dict):
                continue
            prediction = item.get("placePrediction")
            if not isinstance(prediction, dict):
                continue

            place_id = prediction.get("placeId")
            text = prediction.get("text") or {}
            structured = prediction.get("structuredFormat") or {}
            main_text = structured.get("mainText") or {}
            description = text.get("text")
            name = main_text.get("text")

            if not isinstance(place_id, str) or not place_id.strip():
                continue
            if not isinstance(description, str) or not description.strip():
                continue
            if not isinstance(name, str) or not name.strip():
                name = description.split(",", 1)[0].strip()
            if not name or place_id in seen_place_ids:
                continue

            seen_place_ids.add(place_id)
            suggestions.append(
                GoogleCitySuggestion(
                    google_place_id=place_id,
                    name=name.strip(),
                    description=description.strip(),
                )
            )

        return suggestions

    async def autocomplete_locations(
        self,
        query: str,
        *,
        hotel_only: bool = False,
    ) -> list[LocationSuggestion]:
        """Return normalized India place predictions for trip start selection."""

        normalized_query = query.strip()
        if len(normalized_query) < 2:
            raise GooglePlacesInvalidRequestError(
                "Location query must contain at least 2 characters."
            )
        request_body: dict[str, Any] = {
            "input": normalized_query,
            "includedRegionCodes": ["in"],
            "languageCode": "en",
            "regionCode": "in",
        }
        if hotel_only:
            request_body["includedPrimaryTypes"] = [
                "hotel",
                "lodging",
                "hostel",
                "guest_house",
                "resort_hotel",
            ]
        response = await self._request(
            "POST",
            AUTOCOMPLETE_URL,
            headers={
                **self._auth_headers(),
                "Content-Type": "application/json",
                "X-Goog-FieldMask": (
                    "suggestions.placePrediction.placeId,"
                    "suggestions.placePrediction.text.text,"
                    "suggestions.placePrediction.structuredFormat.mainText.text"
                ),
            },
            json=request_body,
        )
        self._raise_for_status(response)
        try:
            payload = response.json()
        except ValueError as exc:
            raise GooglePlacesUnavailableError(
                "Google Places returned an invalid location response."
            ) from exc
        if not isinstance(payload, dict):
            raise GooglePlacesUnavailableError(
                "Google Places returned an invalid location response."
            )

        results: list[LocationSuggestion] = []
        seen: set[str] = set()
        raw_suggestions = payload.get("suggestions", [])
        if not isinstance(raw_suggestions, list):
            raise GooglePlacesUnavailableError(
                "Google Places returned an invalid location response."
            )
        for item in raw_suggestions:
            prediction = item.get("placePrediction") if isinstance(item, dict) else None
            if not isinstance(prediction, dict):
                continue
            place_id = prediction.get("placeId")
            description = (prediction.get("text") or {}).get("text")
            name = (
                (prediction.get("structuredFormat") or {}).get("mainText") or {}
            ).get("text")
            if not isinstance(place_id, str) or not place_id.strip():
                continue
            if not isinstance(description, str) or not description.strip():
                continue
            if not isinstance(name, str) or not name.strip():
                name = description.split(",", 1)[0]
            if place_id in seen:
                continue
            seen.add(place_id)
            results.append(
                LocationSuggestion(
                    google_place_id=place_id.strip(),
                    name=name.strip(),
                    description=description.strip(),
                )
            )
        return results

    async def get_location_details(self, place_id: str) -> LocationDetails:
        """Resolve a Google place to the coordinates needed for a trip start."""

        normalized_place_id = place_id.strip()
        if not normalized_place_id:
            raise GooglePlacesInvalidRequestError(
                "Google Place ID must not be blank."
            )
        response = await self._request(
            "GET",
            PLACE_DETAILS_URL.format(
                place_id=quote(normalized_place_id, safe="")
            ),
            headers={
                **self._auth_headers(),
                "X-Goog-FieldMask": "id,displayName,location",
            },
        )
        self._raise_for_status(response, place_details=True)
        try:
            payload = response.json()
            return LocationDetails(
                google_place_id=str(payload.get("id") or normalized_place_id),
                name=str(payload["displayName"]["text"]),
                latitude=float(payload["location"]["latitude"]),
                longitude=float(payload["location"]["longitude"]),
            )
        except (KeyError, TypeError, ValueError) as exc:
            raise GooglePlacesUnavailableError(
                "Google Places returned incomplete location details."
            ) from exc

    async def get_place_details(self, place_id: str) -> GooglePlaceDetails:
        """Fetch and normalize the city fields required by `/cities/resolve`."""

        normalized_place_id = place_id.strip()
        if not normalized_place_id:
            raise GooglePlacesInvalidRequestError(
                "Google Place ID must not be blank."
            )

        response = await self._request(
            "GET",
            PLACE_DETAILS_URL.format(
                place_id=quote(normalized_place_id, safe="")
            ),
            headers={
                **self._auth_headers(),
                "X-Goog-FieldMask": "id,displayName,addressComponents,location",
            },
        )
        self._raise_for_status(response, place_details=True)

        try:
            payload: dict[str, Any] = response.json()
            display_name = payload["displayName"]["text"]
            latitude = payload["location"]["latitude"]
            longitude = payload["location"]["longitude"]
        except (KeyError, TypeError, ValueError) as exc:
            raise GooglePlacesUnavailableError(
                "Google Places returned incomplete city details."
            ) from exc

        components = payload.get("addressComponents", [])
        if not isinstance(components, list):
            raise GooglePlacesUnavailableError(
                "Google Places returned invalid address components."
            )
        state = self._address_component(
            components, "administrative_area_level_1"
        )
        country = self._address_component(components, "country")
        if not country:
            raise GooglePlacesUnavailableError(
                "Google Places returned city details without a country."
            )

        google_place_id = payload.get("id") or normalized_place_id
        try:
            return GooglePlaceDetails(
                name=str(display_name),
                state=state,
                country=country,
                latitude=float(latitude),
                longitude=float(longitude),
                google_place_id=str(google_place_id),
            )
        except (TypeError, ValueError) as exc:
            raise GooglePlacesUnavailableError(
                "Google Places returned invalid city details."
            ) from exc

    async def search_nearby_places(
        self,
        *,
        latitude: float,
        longitude: float,
        included_types: tuple[str, ...],
        radius_meters: float,
        max_results: int = 20,
    ) -> list[GoogleNearbyPlace]:
        """Search around a city and return only fields owned by our API."""

        if not included_types:
            raise GooglePlacesInvalidRequestError(
                "At least one supported Google place type is required."
            )
        if not -90 <= latitude <= 90 or not -180 <= longitude <= 180:
            raise GooglePlacesInvalidRequestError(
                "Nearby search coordinates are invalid."
            )
        if not 0 < radius_meters <= 50000:
            raise GooglePlacesInvalidRequestError(
                "Nearby search radius must be between 0 and 50000 meters."
            )
        if not 1 <= max_results <= 20:
            raise GooglePlacesInvalidRequestError(
                "Nearby search can return between 1 and 20 places."
            )

        response = await self._request(
            "POST",
            NEARBY_SEARCH_URL,
            headers={
                **self._auth_headers(),
                "Content-Type": "application/json",
                "X-Goog-FieldMask": (
                    "places.id,places.displayName,places.location,"
                    "places.rating,places.userRatingCount,"
                    "places.primaryType,places.types"
                ),
            },
            json={
                "includedTypes": list(included_types),
                "maxResultCount": max_results,
                "rankPreference": "POPULARITY",
                "locationRestriction": {
                    "circle": {
                        "center": {
                            "latitude": latitude,
                            "longitude": longitude,
                        },
                        "radius": radius_meters,
                    }
                },
                "languageCode": "en",
                "regionCode": "in",
            },
        )
        self._raise_for_status(response)

        try:
            payload = response.json()
        except ValueError as exc:
            raise GooglePlacesUnavailableError(
                "Google Places returned an invalid nearby search response."
            ) from exc
        if not isinstance(payload, dict):
            raise GooglePlacesUnavailableError(
                "Google Places returned an invalid nearby search response."
            )

        raw_places = payload.get("places", [])
        if not isinstance(raw_places, list):
            raise GooglePlacesUnavailableError(
                "Google Places returned an invalid nearby search response."
            )

        places: list[GoogleNearbyPlace] = []
        seen_place_ids: set[str] = set()
        for item in raw_places:
            if not isinstance(item, dict):
                continue
            try:
                place_id = item["id"]
                name = item["displayName"]["text"]
                location = item["location"]
                place_latitude = location["latitude"]
                place_longitude = location["longitude"]
            except (KeyError, TypeError):
                continue
            if not isinstance(place_id, str) or not place_id.strip():
                continue
            if not isinstance(name, str) or not name.strip():
                continue
            if place_id in seen_place_ids:
                continue

            raw_types = item.get("types", [])
            types = (
                [value for value in raw_types if isinstance(value, str)]
                if isinstance(raw_types, list)
                else []
            )
            primary_type = item.get("primaryType")
            if not isinstance(primary_type, str):
                primary_type = None

            try:
                place = GoogleNearbyPlace(
                    google_place_id=place_id.strip(),
                    name=name.strip(),
                    latitude=float(place_latitude),
                    longitude=float(place_longitude),
                    rating=(
                        float(item["rating"])
                        if item.get("rating") is not None
                        else None
                    ),
                    review_count=int(item.get("userRatingCount", 0)),
                    primary_type=primary_type,
                    types=types,
                )
            except (TypeError, ValueError):
                continue

            seen_place_ids.add(place_id)
            places.append(place)

        return places

    def _auth_headers(self) -> dict[str, str]:
        if not self._api_key:
            raise GooglePlacesConfigurationError(
                "Google Places is not configured on the backend."
            )
        return {"X-Goog-Api-Key": self._api_key}

    async def _request(self, method: str, url: str, **kwargs: Any) -> httpx.Response:
        try:
            if self._client is not None:
                return await self._client.request(method, url, **kwargs)
            async with httpx.AsyncClient(timeout=self._timeout) as client:
                return await client.request(method, url, **kwargs)
        except httpx.TimeoutException as exc:
            raise GooglePlacesTimeoutError(
                "Google Places did not respond in time."
            ) from exc
        except httpx.RequestError as exc:
            raise GooglePlacesUnavailableError(
                "Google Places could not be reached."
            ) from exc

    @staticmethod
    def _address_component(
        components: list[dict[str, Any]], component_type: str
    ) -> str | None:
        for component in components:
            if not isinstance(component, dict):
                continue
            if component_type in component.get("types", []):
                value = component.get("longText")
                if isinstance(value, str) and value.strip():
                    return value.strip()
        return None

    @staticmethod
    def _raise_for_status(
        response: httpx.Response, *, place_details: bool = False
    ) -> None:
        if response.is_success:
            return
        if place_details and response.status_code in {400, 404}:
            raise GooglePlaceNotFoundError("Google Place ID was not found.")
        if response.status_code == 400:
            raise GooglePlacesInvalidRequestError(
                "Google Places rejected the request."
            )
        raise GooglePlacesUnavailableError(
            "Google Places is temporarily unavailable."
        )
