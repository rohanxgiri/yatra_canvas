"""Geoapify Places API provider for resilient POI discovery."""

from __future__ import annotations

import asyncio
import logging
from typing import Any

import httpx

from app.schemas import DiscoveryCategory
from app.services.openstreetmap_places_service import OpenStreetMapNearbyPlace

logger = logging.getLogger(__name__)

GEOAPIFY_CATEGORY_MAPPING: dict[DiscoveryCategory, str] = {
    DiscoveryCategory.TOURISM: "tourism.attraction,tourism.sights,entertainment.museum",
    DiscoveryCategory.HERITAGE: "heritage,building.historic",
    DiscoveryCategory.RELIGIOUS: "religion.place_of_worship",
    DiscoveryCategory.FOOD: "catering.restaurant,catering.fast_food",
    DiscoveryCategory.CAFES: "catering.cafe",
    DiscoveryCategory.MARKETS: "commercial.marketplace",
    DiscoveryCategory.NATURE: "natural,leisure.park",
}


class GeoapifyPlacesError(Exception):
    """Base exception for Geoapify Places errors."""


class GeoapifyPlacesTimeoutError(GeoapifyPlacesError):
    pass


class GeoapifyPlacesRateLimitError(GeoapifyPlacesError):
    def __init__(self, retry_after: str | None = None) -> None:
        super().__init__("Geoapify Places API is temporarily rate limited.")
        self.retry_after = retry_after


class GeoapifyPlacesUnavailableError(GeoapifyPlacesError):
    pass


class GeoapifyPlacesProvider:
    """Discovers nearby places through the Geoapify Places API."""

    def __init__(
        self,
        api_key: str | None,
        *,
        base_url: str = "https://api.geoapify.com",
        timeout_seconds: float = 8.0,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        self._api_key = api_key.strip() if api_key else None
        self._base_url = base_url.rstrip("/")
        self._timeout = httpx.Timeout(
            timeout_seconds,
            connect=min(timeout_seconds, 3.0),
        )
        self._client = client

    @property
    def is_configured(self) -> bool:
        return bool(self._api_key)

    async def search_nearby_places(
        self,
        *,
        latitude: float,
        longitude: float,
        category: DiscoveryCategory,
        limit: int = 20,
        radius_meters: int = 8000,
    ) -> list[OpenStreetMapNearbyPlace]:
        if not self.is_configured:
            return []

        geoapify_cats = GEOAPIFY_CATEGORY_MAPPING.get(category)
        if not geoapify_cats:
            return []

        url = f"{self._base_url}/v2/places"
        # Geoapify circle filter format is circle:lon,lat,radiusMeters
        params: dict[str, str | int] = {
            "categories": geoapify_cats,
            "filter": f"circle:{longitude},{latitude},{radius_meters}",
            "bias": f"proximity:{longitude},{latitude}",
            "limit": min(max(1, limit), 100),
            "apiKey": self._api_key,  # type: ignore[dict-item]
        }

        try:
            if self._client is not None:
                response = await self._client.get(url, params=params)
            else:
                async with httpx.AsyncClient(timeout=self._timeout) as client:
                    response = await client.get(url, params=params)
        except httpx.TimeoutException as exc:
            raise GeoapifyPlacesTimeoutError(
                f"Geoapify Places timed out for category={category.value}"
            ) from exc
        except httpx.RequestError as exc:
            raise GeoapifyPlacesUnavailableError(
                f"Geoapify Places network error for category={category.value}: {exc}"
            ) from exc

        self._raise_for_status(response)

        try:
            payload = response.json()
        except ValueError as exc:
            raise GeoapifyPlacesUnavailableError(
                "Geoapify Places returned invalid JSON."
            ) from exc

        features = payload.get("features", [])
        results: list[OpenStreetMapNearbyPlace] = []
        seen: set[str] = set()

        for feat in features:
            props = feat.get("properties", {})
            name = (
                props.get("name")
                or props.get("address_line1")
                or props.get("formatted")
            )
            place_id = props.get("place_id")
            lat = props.get("lat")
            lon = props.get("lon")

            if not name or not place_id or lat is None or lon is None:
                continue

            external_id = f"geoapify-{place_id}"
            if external_id in seen:
                continue
            seen.add(external_id)

            tags: dict[str, str] = {
                "name": str(name).strip(),
                "source": "geoapify",
            }

            # Map category-specific tags
            if category == DiscoveryCategory.FOOD:
                tags["amenity"] = "restaurant"
            elif category == DiscoveryCategory.CAFES:
                tags["amenity"] = "cafe"
            elif category == DiscoveryCategory.RELIGIOUS:
                tags["amenity"] = "place_of_worship"
                cat_list = props.get("categories", [])
                if isinstance(cat_list, list):
                    for c in cat_list:
                        if "hindu" in str(c):
                            tags["religion"] = "hindu"
                        elif "muslim" in str(c) or "mosque" in str(c):
                            tags["religion"] = "muslim"
                        elif "christian" in str(c) or "church" in str(c):
                            tags["religion"] = "christian"
            elif category == DiscoveryCategory.TOURISM:
                tags["tourism"] = "attraction"
            elif category == DiscoveryCategory.HERITAGE:
                tags["historic"] = "yes"
                tags["heritage"] = "yes"
            elif category == DiscoveryCategory.MARKETS:
                tags["amenity"] = "marketplace"
            elif category == DiscoveryCategory.NATURE:
                tags["leisure"] = "park"

            # Propagate contact / website / opening_hours if present
            if props.get("website"):
                tags["website"] = str(props["website"])
            if props.get("phone"):
                tags["phone"] = str(props["phone"])
            if props.get("wiki_and_media", {}).get("wikidata"):
                tags["wikidata"] = str(props["wiki_and_media"]["wikidata"])
            opening_hours = (
                props.get("opening_hours")
                or props.get("datasource", {}).get("raw", {}).get("opening_hours")
            )
            if opening_hours and isinstance(opening_hours, str) and opening_hours.strip():
                tags["opening_hours"] = opening_hours.strip()

            results.append(
                OpenStreetMapNearbyPlace(
                    external_place_id=external_id,
                    source_url=f"https://www.geoapify.com/place/{place_id}",
                    name=str(name).strip(),
                    latitude=float(lat),
                    longitude=float(lon),
                    tags=tags,
                )
            )

        return results

    async def search_nearby_places_for_categories(
        self,
        *,
        latitude: float,
        longitude: float,
        categories: list[DiscoveryCategory],
        limit_per_category: int | None = None,
        category_limits: dict[DiscoveryCategory, int] | None = None,
        category_radii: dict[DiscoveryCategory, int] | None = None,
    ) -> dict[DiscoveryCategory, list[OpenStreetMapNearbyPlace]]:
        if not self.is_configured:
            return {}

        unique_cats = list(dict.fromkeys(categories))
        results: dict[DiscoveryCategory, list[OpenStreetMapNearbyPlace]] = {}

        async def _query_cat(cat: DiscoveryCategory) -> tuple[DiscoveryCategory, list[OpenStreetMapNearbyPlace]]:
            lim = (
                category_limits.get(cat)
                if category_limits and cat in category_limits
                else (limit_per_category or 20)
            )
            rad = (
                category_radii.get(cat)
                if category_radii and cat in category_radii
                else 8000
            )
            try:
                places = await self.search_nearby_places(
                    latitude=latitude,
                    longitude=longitude,
                    category=cat,
                    limit=lim,
                    radius_meters=rad,
                )
                return cat, places
            except Exception as exc:
                logger.warning(
                    "Geoapify Places query failed for category=%s: %s",
                    cat.value,
                    exc,
                )
                return cat, []

        query_results = await asyncio.gather(*[_query_cat(c) for c in unique_cats])
        for cat, places in query_results:
            if places:
                results[cat] = places

        return results

    @staticmethod
    def _raise_for_status(response: httpx.Response) -> None:
        if response.is_success:
            return
        if response.status_code == 429:
            raise GeoapifyPlacesRateLimitError(response.headers.get("Retry-After"))
        if response.status_code in {401, 403}:
            raise GeoapifyPlacesUnavailableError(
                "Geoapify Places API key unauthorized or quota exceeded."
            )
        raise GeoapifyPlacesUnavailableError(
            f"Geoapify Places returned HTTP {response.status_code}"
        )
