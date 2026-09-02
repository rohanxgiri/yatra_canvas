"""OpenStreetMap POI discovery through a bounded Overpass API query."""

from dataclasses import dataclass
from math import cos, radians
from typing import Any

import httpx

from app.schemas import DiscoveryCategory


class OpenStreetMapPlacesError(Exception):
    """Base class for stable OpenStreetMap discovery failures."""


class OpenStreetMapPlacesTimeoutError(OpenStreetMapPlacesError):
    pass


class OpenStreetMapPlacesRateLimitError(OpenStreetMapPlacesError):
    def __init__(self, retry_after: str | None = None) -> None:
        super().__init__("OpenStreetMap discovery is temporarily rate limited.")
        self.retry_after = retry_after


class OpenStreetMapPlacesUnavailableError(OpenStreetMapPlacesError):
    pass


@dataclass(frozen=True, slots=True)
class OpenStreetMapNearbyPlace:
    external_place_id: str
    source_url: str
    name: str
    latitude: float
    longitude: float
    tags: dict[str, str]


_FILTERS: dict[DiscoveryCategory, tuple[str, ...]] = {
    DiscoveryCategory.RELIGIOUS: ('["amenity"="place_of_worship"]',),
    DiscoveryCategory.FOOD: ('["amenity"~"^(restaurant|fast_food|food_court)$"]',),
    DiscoveryCategory.TOURISM: (
        '["tourism"~"^(attraction|museum|gallery|viewpoint|zoo|theme_park)$"]',
        '["leisure"="park"]',
    ),
    DiscoveryCategory.CAFES: ('["amenity"="cafe"]',),
    DiscoveryCategory.HERITAGE: (
        '["historic"]',
        '["heritage"]',
    ),
}

_KNOWN_RELIGIONS = {
    "bahai",
    "buddhist",
    "caodaism",
    "christian",
    "confucian",
    "hindu",
    "jain",
    "jewish",
    "multifaith",
    "muslim",
    "shinto",
    "sikh",
    "spiritualist",
    "taoist",
    "tenrikyo",
    "unitarian_universalist",
    "voodoo",
    "zoroastrian",
}


class OpenStreetMapPlacesService:
    """Fetch named POIs without a commercial provider key."""

    def __init__(
        self,
        api_url: str,
        *,
        timeout_seconds: float = 25.0,
        radius_meters: int = 8000,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        self._api_url = api_url.rstrip("/")
        self._timeout = httpx.Timeout(
            timeout_seconds,
            connect=min(timeout_seconds, 5.0),
        )
        self._query_timeout_seconds = max(5, min(int(timeout_seconds) - 2, 55))
        self._radius_meters = radius_meters
        self._client = client

    async def search_nearby_places(
        self,
        *,
        latitude: float,
        longitude: float,
        category: DiscoveryCategory,
        limit: int = 40,
    ) -> list[OpenStreetMapNearbyPlace]:
        query = self._build_query(latitude, longitude, category, limit)
        response = await self._request(query)
        self._raise_for_status(response)
        try:
            payload = response.json()
        except ValueError as exc:
            raise OpenStreetMapPlacesUnavailableError(
                "OpenStreetMap returned an invalid discovery response."
            ) from exc
        if not isinstance(payload, dict) or not isinstance(
            payload.get("elements"), list
        ):
            raise OpenStreetMapPlacesUnavailableError(
                "OpenStreetMap returned an invalid discovery response."
            )

        results: list[OpenStreetMapNearbyPlace] = []
        seen: set[str] = set()
        for raw in payload["elements"]:
            normalized = self._normalize(raw)
            if (
                normalized is None
                or not self._matches_category(normalized, category)
                or normalized.external_place_id in seen
            ):
                continue
            seen.add(normalized.external_place_id)
            results.append(normalized)
            if len(results) >= limit:
                break
        return results

    async def search_nearby_places_for_categories(
        self,
        *,
        latitude: float,
        longitude: float,
        categories: list[DiscoveryCategory],
        limit_per_category: int = 40,
    ) -> dict[DiscoveryCategory, list[OpenStreetMapNearbyPlace]]:
        """Fetch several discovery categories in one bounded Overpass request."""

        unique_categories = list(dict.fromkeys(categories))
        if not unique_categories:
            return {}
        query = self._build_multi_category_query(
            latitude,
            longitude,
            unique_categories,
            limit_per_category,
        )
        response = await self._request(query)
        self._raise_for_status(response)
        try:
            payload = response.json()
        except ValueError as exc:
            raise OpenStreetMapPlacesUnavailableError(
                "OpenStreetMap returned an invalid discovery response."
            ) from exc
        if not isinstance(payload, dict) or not isinstance(
            payload.get("elements"), list
        ):
            raise OpenStreetMapPlacesUnavailableError(
                "OpenStreetMap returned an invalid discovery response."
            )

        results = {category: [] for category in unique_categories}
        seen_by_category = {category: set() for category in unique_categories}
        for raw in payload["elements"]:
            normalized = self._normalize(raw)
            if normalized is None:
                continue
            for category in unique_categories:
                if (
                    len(results[category]) >= limit_per_category
                    or normalized.external_place_id in seen_by_category[category]
                    or not self._matches_filter(normalized, category)
                ):
                    continue
                seen_by_category[category].add(normalized.external_place_id)
                results[category].append(normalized)
        return results

    @staticmethod
    def _matches_category(
        place: OpenStreetMapNearbyPlace,
        category: DiscoveryCategory,
    ) -> bool:
        if category is not DiscoveryCategory.RELIGIOUS:
            return True
        religion = place.tags.get("religion")
        if religion is None:
            return True
        values = {
            value.strip().lower().replace(" ", "_")
            for value in religion.split(";")
            if value.strip()
        }
        return bool(values & _KNOWN_RELIGIONS)

    @staticmethod
    def _matches_filter(
        place: OpenStreetMapNearbyPlace,
        category: DiscoveryCategory,
    ) -> bool:
        tags = place.tags
        amenity = tags.get("amenity")
        if category is DiscoveryCategory.RELIGIOUS:
            return amenity == "place_of_worship" and (
                tags.get("religion") is None
                or OpenStreetMapPlacesService._matches_category(place, category)
            )
        if category is DiscoveryCategory.FOOD:
            return amenity in {"restaurant", "fast_food", "food_court"}
        if category is DiscoveryCategory.TOURISM:
            return (
                tags.get("tourism")
                in {
                    "attraction",
                    "museum",
                    "gallery",
                    "viewpoint",
                    "zoo",
                    "theme_park",
                }
                or tags.get("leisure") == "park"
            )
        if category is DiscoveryCategory.CAFES:
            return amenity == "cafe"
        return tags.get("historic") not in {None, "no"} or tags.get("heritage") not in {
            None,
            "no",
        }

    def _build_query(
        self,
        latitude: float,
        longitude: float,
        category: DiscoveryCategory,
        limit: int,
    ) -> str:
        bbox = self._bounding_box(latitude, longitude)
        statements = "\n".join(
            f'nwr({bbox})["name"]{tag_filter};' for tag_filter in _FILTERS[category]
        )
        bounded_limit = max(1, min(limit, 100))
        return (
            f"[out:json][timeout:{self._query_timeout_seconds}];\n"
            f"(\n{statements}\n);\n"
            f"out center {bounded_limit};"
        )

    def _build_multi_category_query(
        self,
        latitude: float,
        longitude: float,
        categories: list[DiscoveryCategory],
        limit_per_category: int,
    ) -> str:
        bbox = self._bounding_box(latitude, longitude)
        statements = "\n".join(
            f'nwr({bbox})["name"]{tag_filter};'
            for category in categories
            for tag_filter in _FILTERS[category]
        )
        bounded_limit = max(1, min(limit_per_category * len(categories), 100))
        return (
            f"[out:json][timeout:{self._query_timeout_seconds}];\n"
            f"(\n{statements}\n);\n"
            f"out center {bounded_limit};"
        )

    def _bounding_box(self, latitude: float, longitude: float) -> str:
        latitude_delta = self._radius_meters / 111_320
        longitude_scale = max(cos(radians(latitude)), 0.2)
        longitude_delta = self._radius_meters / (111_320 * longitude_scale)
        return (
            f"{latitude - latitude_delta:.6f},"
            f"{longitude - longitude_delta:.6f},"
            f"{latitude + latitude_delta:.6f},"
            f"{longitude + longitude_delta:.6f}"
        )

    async def _request(self, query: str) -> httpx.Response:
        headers = {"User-Agent": "YatraCanvas/0.1 (OpenStreetMap POI discovery)"}
        try:
            if self._client is not None:
                return await self._client.post(
                    self._api_url,
                    data={"data": query},
                    headers=headers,
                )
            async with httpx.AsyncClient(timeout=self._timeout) as client:
                return await client.post(
                    self._api_url,
                    data={"data": query},
                    headers=headers,
                )
        except httpx.TimeoutException as exc:
            raise OpenStreetMapPlacesTimeoutError(
                "OpenStreetMap discovery did not respond in time."
            ) from exc
        except httpx.RequestError as exc:
            raise OpenStreetMapPlacesUnavailableError(
                "OpenStreetMap discovery could not be reached."
            ) from exc

    @staticmethod
    def _raise_for_status(response: httpx.Response) -> None:
        if response.is_success:
            return
        if response.status_code == 429:
            raise OpenStreetMapPlacesRateLimitError(response.headers.get("Retry-After"))
        raise OpenStreetMapPlacesUnavailableError(
            "OpenStreetMap discovery is temporarily unavailable."
        )

    @staticmethod
    def _normalize(raw: Any) -> OpenStreetMapNearbyPlace | None:
        if not isinstance(raw, dict):
            return None
        element_type = raw.get("type")
        element_id = raw.get("id")
        tags = raw.get("tags")
        if (
            element_type not in {"node", "way", "relation"}
            or not isinstance(element_id, int)
            or not isinstance(tags, dict)
        ):
            return None
        name = tags.get("name:en") or tags.get("name")
        if not isinstance(name, str) or not name.strip():
            return None
        coordinates = raw if element_type == "node" else raw.get("center")
        if not isinstance(coordinates, dict):
            return None
        try:
            latitude = float(coordinates["lat"])
            longitude = float(coordinates["lon"])
        except (KeyError, TypeError, ValueError):
            return None
        clean_tags = {
            str(key): str(value)
            for key, value in tags.items()
            if isinstance(key, str) and isinstance(value, (str, int, float))
        }
        external_id = f"{element_type}/{element_id}"
        return OpenStreetMapNearbyPlace(
            external_place_id=external_id,
            source_url=f"https://www.openstreetmap.org/{external_id}",
            name=name.strip()[:200],
            latitude=latitude,
            longitude=longitude,
            tags=clean_tags,
        )
