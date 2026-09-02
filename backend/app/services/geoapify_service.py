"""Geoapify autocomplete client with normalized results and a short TTL cache."""

from dataclasses import dataclass
from time import monotonic
from typing import Any

import httpx

from app.schemas.location import LocationAutocompleteResult


SUPPORTED_LOCATION_TYPES = {
    "country",
    "state",
    "city",
    "postcode",
    "street",
    "amenity",
    "locality",
}


class GeoapifyError(Exception):
    """Base class for stable, credential-free Geoapify errors."""


class GeoapifyConfigurationError(GeoapifyError):
    pass


class GeoapifyInvalidRequestError(GeoapifyError):
    pass


class GeoapifyTimeoutError(GeoapifyError):
    pass


class GeoapifyRateLimitError(GeoapifyError):
    def __init__(self, retry_after: str | None = None) -> None:
        super().__init__("Location search is temporarily rate limited.")
        self.retry_after = retry_after


class GeoapifyUnavailableError(GeoapifyError):
    pass


@dataclass(frozen=True)
class _CacheEntry:
    expires_at: float
    results: tuple[LocationAutocompleteResult, ...]


class GeoapifyService:
    """Use Geoapify only for user-driven autocomplete/geocoding."""

    def __init__(
        self,
        api_key: str | None,
        *,
        base_url: str = "https://api.geoapify.com",
        timeout_seconds: float = 8.0,
        cache_ttl_seconds: int = 300,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        self._api_key = api_key.strip() if api_key else None
        self._base_url = base_url.rstrip("/")
        self._timeout = httpx.Timeout(
            timeout_seconds,
            connect=min(timeout_seconds, 3.0),
        )
        self._cache_ttl_seconds = cache_ttl_seconds
        self._client = client
        self._cache: dict[tuple[Any, ...], _CacheEntry] = {}

    async def autocomplete(
        self,
        query: str,
        *,
        location_type: str | None = None,
        country_code: str = "in",
        latitude: float | None = None,
        longitude: float | None = None,
        limit: int = 5,
    ) -> list[LocationAutocompleteResult]:
        normalized_query = " ".join(query.split())
        normalized_country = country_code.strip().casefold()
        if len(normalized_query) < 3:
            raise GeoapifyInvalidRequestError(
                "Location query must contain at least 3 characters."
            )
        if location_type is not None and location_type not in SUPPORTED_LOCATION_TYPES:
            raise GeoapifyInvalidRequestError("Unsupported location result type.")
        if len(normalized_country) != 2 or not normalized_country.isalpha():
            raise GeoapifyInvalidRequestError("Country code must contain two letters.")
        if not 1 <= limit <= 10:
            raise GeoapifyInvalidRequestError("Limit must be between 1 and 10.")
        if (latitude is None) != (longitude is None):
            raise GeoapifyInvalidRequestError(
                "Latitude and longitude must be supplied together."
            )
        if latitude is not None and not -90 <= latitude <= 90:
            raise GeoapifyInvalidRequestError("Latitude is outside its valid range.")
        if longitude is not None and not -180 <= longitude <= 180:
            raise GeoapifyInvalidRequestError("Longitude is outside its valid range.")
        if not self._api_key:
            raise GeoapifyConfigurationError(
                "Location autocomplete is not configured on the backend."
            )

        cache_key = (
            normalized_query.casefold(),
            location_type,
            normalized_country,
            latitude,
            longitude,
            limit,
        )
        cached = self._cache.get(cache_key)
        now = monotonic()
        if cached is not None and cached.expires_at > now:
            return list(cached.results)

        params: dict[str, str | int] = {
            "text": normalized_query,
            "format": "json",
            "filter": f"countrycode:{normalized_country}",
            "limit": limit,
            "lang": "en",
            "apiKey": self._api_key,
        }
        if location_type is not None:
            params["type"] = location_type
        if latitude is not None and longitude is not None:
            # Geoapify proximity values are ordered longitude,latitude.
            params["bias"] = f"proximity:{longitude},{latitude}"

        response = await self._request(params)
        self._raise_for_status(response)
        try:
            payload = response.json()
        except ValueError as exc:
            raise GeoapifyUnavailableError(
                "Location provider returned an invalid response."
            ) from exc
        if not isinstance(payload, dict) or not isinstance(
            payload.get("results", []), list
        ):
            raise GeoapifyUnavailableError(
                "Location provider returned an invalid response."
            )

        results: list[LocationAutocompleteResult] = []
        seen: set[str] = set()
        for raw in payload.get("results", []):
            normalized = self._normalize_result(raw)
            if normalized is None or normalized.provider_place_id in seen:
                continue
            seen.add(normalized.provider_place_id)
            results.append(normalized)

        if self._cache_ttl_seconds > 0:
            self._cache[cache_key] = _CacheEntry(
                expires_at=now + self._cache_ttl_seconds,
                results=tuple(results),
            )
        return results

    async def get_place_details(
        self, provider_place_id: str
    ) -> LocationAutocompleteResult | None:
        """Fetch details for a specific Geoapify place ID."""
        params = {
            "id": provider_place_id,
            "apiKey": self._api_key,
        }
        url = f"{self._base_url}/v2/place-details"
        try:
            if self._client is not None:
                response = await self._client.get(url, params=params)
            else:
                async with httpx.AsyncClient(timeout=self._timeout) as client:
                    response = await client.get(url, params=params)
        except httpx.TimeoutException as exc:
            raise GeoapifyTimeoutError("Location provider did not respond in time.") from exc
        except httpx.RequestError as exc:
            raise GeoapifyUnavailableError("Location provider could not be reached.") from exc

        self._raise_for_status(response)

        try:
            payload = response.json()
        except ValueError:
            raise GeoapifyUnavailableError("Location provider returned an invalid response.")

        features = payload.get("features", [])
        if not features:
            return None
        
        properties = features[0].get("properties", {})
        return self._normalize_result(properties)

    async def _request(self, params: dict[str, str | int]) -> httpx.Response:
        url = f"{self._base_url}/v1/geocode/autocomplete"
        try:
            if self._client is not None:
                return await self._client.get(url, params=params)
            async with httpx.AsyncClient(timeout=self._timeout) as client:
                return await client.get(url, params=params)
        except httpx.TimeoutException as exc:
            raise GeoapifyTimeoutError(
                "Location provider did not respond in time."
            ) from exc
        except httpx.RequestError as exc:
            raise GeoapifyUnavailableError(
                "Location provider could not be reached."
            ) from exc

    @staticmethod
    def _raise_for_status(response: httpx.Response) -> None:
        if response.is_success:
            return
        if response.status_code == 400:
            raise GeoapifyInvalidRequestError("Location request was rejected.")
        if response.status_code in {401, 403}:
            raise GeoapifyConfigurationError(
                "Location autocomplete is unavailable due to backend configuration."
            )
        if response.status_code == 429:
            raise GeoapifyRateLimitError(response.headers.get("Retry-After"))
        raise GeoapifyUnavailableError(
            "Location provider is temporarily unavailable."
        )

    @staticmethod
    def _normalize_result(raw: Any) -> LocationAutocompleteResult | None:
        if not isinstance(raw, dict):
            return None
        place_id = raw.get("place_id")
        formatted = raw.get("formatted")
        name = raw.get("name") or raw.get("address_line1") or formatted
        try:
            if not isinstance(place_id, str) or not place_id.strip():
                return None
            if not isinstance(formatted, str) or not formatted.strip():
                return None
            if not isinstance(name, str) or not name.strip():
                return None
            return LocationAutocompleteResult(
                provider="geoapify",
                provider_place_id=place_id.strip(),
                name=name.strip(),
                formatted_address=formatted.strip(),
                latitude=float(raw["lat"]),
                longitude=float(raw["lon"]),
                city=_clean_optional(raw.get("city")),
                state=_clean_optional(raw.get("state")),
                country_code=str(raw.get("country_code") or "").casefold(),
                result_type=str(raw.get("result_type") or "unknown"),
            )
        except (KeyError, TypeError, ValueError):
            return None


def _clean_optional(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    normalized = value.strip()
    return normalized or None
