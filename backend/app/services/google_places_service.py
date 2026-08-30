"""Google Places API (New) client and response normalization."""

from typing import Any
from urllib.parse import quote

import httpx

from app.schemas import GoogleCitySuggestion, GooglePlaceDetails


AUTOCOMPLETE_URL = "https://places.googleapis.com/v1/places:autocomplete"
PLACE_DETAILS_URL = "https://places.googleapis.com/v1/places/{place_id}"


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
