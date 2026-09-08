"""OpenStreetMap POI discovery through a bounded Overpass API query."""

import asyncio
import logging
import time
from dataclasses import dataclass
from math import cos, radians
from typing import Any

import httpx

from app.schemas import DiscoveryCategory
from app.services.provider_circuit_breaker import ProviderCircuitBreaker

logger = logging.getLogger(__name__)


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
        '["tourism"~"^(attraction|museum|gallery|viewpoint|zoo|theme_park|aquarium)$"]',
        '["leisure"="park"]',
    ),
    DiscoveryCategory.CAFES: ('["amenity"="cafe"]',),
    DiscoveryCategory.HERITAGE: (
        '["historic"]',
        '["heritage"]',
        '["landuse"="cemetery"]',
    ),
    DiscoveryCategory.MARKETS: (
        '["amenity"="marketplace"]',
        '["landuse"="retail"]',
    ),
    DiscoveryCategory.NATURE: (
        '["natural"~"^(beach|water|wood)$"]',
        '["leisure"~"^(garden|nature_reserve)$"]',
        '["water"="lake"]',
    ),
}

_DEFAULT_CATEGORY_RADII: dict[DiscoveryCategory, int] = {
    DiscoveryCategory.TOURISM: 15_000,
    DiscoveryCategory.HERITAGE: 15_000,
    DiscoveryCategory.RELIGIOUS: 10_000,
    DiscoveryCategory.FOOD: 8_000,
    DiscoveryCategory.CAFES: 8_000,
    DiscoveryCategory.MARKETS: 10_000,
    DiscoveryCategory.NATURE: 25_000,
}

_DEFAULT_CATEGORY_LIMITS: dict[DiscoveryCategory, int] = {
    DiscoveryCategory.TOURISM: 60,
    DiscoveryCategory.HERITAGE: 60,
    DiscoveryCategory.RELIGIOUS: 40,
    DiscoveryCategory.FOOD: 50,
    DiscoveryCategory.CAFES: 40,
    DiscoveryCategory.MARKETS: 40,
    DiscoveryCategory.NATURE: 40,
}

# Keep one failing multi-category request from sending every category to the
# public Overpass instance before the three-failure circuit breaker can open.
_MAX_CONCURRENT_CATEGORY_REQUESTS = 3

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
        category_radii: dict[DiscoveryCategory, int] | None = None,
        category_limits: dict[DiscoveryCategory, int] | None = None,
        client: httpx.AsyncClient | None = None,
        circuit_breaker: ProviderCircuitBreaker | None = None,
    ) -> None:
        self._api_url = api_url.rstrip("/")
        self._timeout = httpx.Timeout(
            timeout_seconds,
            connect=min(timeout_seconds, 5.0),
        )
        self._query_timeout_seconds = max(5, min(int(timeout_seconds) - 2, 55))
        self._radius_meters = radius_meters
        self._category_radii = (
            dict(category_radii)
            if category_radii is not None
            else _DEFAULT_CATEGORY_RADII.copy()
        )
        self._category_limits = (
            dict(category_limits)
            if category_limits is not None
            else _DEFAULT_CATEGORY_LIMITS.copy()
        )
        self._client = client
        self._circuit_breaker = circuit_breaker

    def get_radius_for_category(self, category: DiscoveryCategory) -> int:
        return self._category_radii.get(category, self._radius_meters)

    def get_limit_for_category(self, category: DiscoveryCategory) -> int:
        return self._category_limits.get(category, 40)

    async def search_nearby_places(
        self,
        *,
        latitude: float,
        longitude: float,
        category: DiscoveryCategory,
        limit: int | None = None,
        radius_meters: int | None = None,
    ) -> list[OpenStreetMapNearbyPlace]:
        if self._circuit_breaker and not self._circuit_breaker.allow_request():
            logger.info(
                "Skipping OpenStreetMap query for category=%s because circuit breaker %s is OPEN",
                category.value,
                self._circuit_breaker.name,
            )
            raise OpenStreetMapPlacesUnavailableError(
                f"OpenStreetMap circuit breaker {self._circuit_breaker.name} is open."
            )

        effective_limit = (
            limit if limit is not None else self.get_limit_for_category(category)
        )
        effective_radius = (
            radius_meters
            if radius_meters is not None
            else self.get_radius_for_category(category)
        )
        query = self._build_query(
            latitude,
            longitude,
            category,
            effective_limit,
            radius_meters=effective_radius,
        )
        start_time = time.monotonic()
        try:
            response = await self._request(query)
            self._raise_for_status(response)
            payload = response.json()
        except (ValueError, KeyError) as exc:
            duration = time.monotonic() - start_time
            logger.warning(
                "OpenStreetMap returned invalid JSON for category=%s duration=%.2fs: %s",
                category.value,
                duration,
                exc,
            )
            if self._circuit_breaker:
                self._circuit_breaker.record_failure(exc)
            raise OpenStreetMapPlacesUnavailableError(
                "OpenStreetMap returned an invalid discovery response."
            ) from exc
        except OpenStreetMapPlacesError as exc:
            duration = time.monotonic() - start_time
            logger.warning(
                "OpenStreetMap discovery failed for category=%s radius=%dm duration=%.2fs: %s",
                category.value,
                effective_radius,
                duration,
                exc,
            )
            if self._circuit_breaker:
                self._circuit_breaker.record_failure(exc)
            raise

        if self._circuit_breaker:
            self._circuit_breaker.record_success()

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
            if len(results) >= effective_limit:
                break

        duration = time.monotonic() - start_time
        logger.info(
            "OpenStreetMap discovered category=%s radius=%dm count=%d limit=%d duration=%.2fs",
            category.value,
            effective_radius,
            len(results),
            effective_limit,
            duration,
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
        """Fetch independent category queries in bounded waves with failure isolation."""

        unique_categories = list(dict.fromkeys(categories))
        if not unique_categories:
            return {}

        results: dict[DiscoveryCategory, list[OpenStreetMapNearbyPlace]] = {}
        errors: list[tuple[DiscoveryCategory, Exception]] = []

        async def _fetch_category(category: DiscoveryCategory):
            limit = (
                category_limits.get(category)
                if category_limits and category in category_limits
                else (
                    limit_per_category
                    if limit_per_category is not None
                    else self.get_limit_for_category(category)
                )
            )
            radius = (
                category_radii.get(category)
                if category_radii and category in category_radii
                else self.get_radius_for_category(category)
            )
            try:
                places = await self.search_nearby_places(
                    latitude=latitude,
                    longitude=longitude,
                    category=category,
                    limit=limit,
                    radius_meters=radius,
                )
                return category, places, None
            except OpenStreetMapPlacesError as exc:
                return category, [], exc

        wave_size = _MAX_CONCURRENT_CATEGORY_REQUESTS
        if self._circuit_breaker is not None:
            wave_size = min(wave_size, self._circuit_breaker.failure_threshold)

        for start in range(0, len(unique_categories), wave_size):
            wave = unique_categories[start : start + wave_size]
            completed = await asyncio.gather(*(_fetch_category(c) for c in wave))

            for cat, places, exc in completed:
                if exc is None:
                    results[cat] = places
                else:
                    logger.warning(
                        "Isolated failure for category %s: %s",
                        cat.value,
                        exc,
                    )
                    errors.append((cat, exc))

            if self._circuit_breaker and not self._circuit_breaker.allow_request():
                skipped = unique_categories[start + len(wave) :]
                if skipped:
                    logger.info(
                        "Skipping remaining OpenStreetMap categories because circuit "
                        "breaker %s is OPEN: %s",
                        self._circuit_breaker.name,
                        [category.value for category in skipped],
                    )
                break

        if not results and errors:
            raise errors[0][1]

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
                    "aquarium",
                }
                or tags.get("leisure") == "park"
            )
        if category is DiscoveryCategory.CAFES:
            return amenity == "cafe"
        if category is DiscoveryCategory.MARKETS:
            return amenity == "marketplace" or tags.get("landuse") == "retail"
        if category is DiscoveryCategory.NATURE:
            natural = tags.get("natural")
            leisure = tags.get("leisure")
            return (
                natural in {"beach", "water", "wood"}
                or leisure in {"garden", "nature_reserve"}
                or tags.get("water") == "lake"
            )
            
        return (
            tags.get("historic") not in {None, "no"}
            or tags.get("heritage") not in {None, "no"}
            or tags.get("landuse") == "cemetery"
        )

    def _build_query(
        self,
        latitude: float,
        longitude: float,
        category: DiscoveryCategory,
        limit: int,
        radius_meters: int | None = None,
    ) -> str:
        bbox = self._bounding_box(latitude, longitude, radius_meters=radius_meters)
        bounded_limit = max(1, min(limit, 200))

        # For attractions, heritage, nature and religious sites: separate polygons (relations/ways)
        # from point nodes to prevent dense nodes from starving major monuments.
        if category in (
            DiscoveryCategory.TOURISM, 
            DiscoveryCategory.HERITAGE, 
            DiscoveryCategory.RELIGIOUS, 
            DiscoveryCategory.NATURE
        ):
            geom_limit = max(10, int(bounded_limit * 0.70))
            node_limit = max(5, int(bounded_limit * 0.35))
            geom_stmts = "\n".join(
                f'relation({bbox})["name"]{tag_filter};\nway({bbox})["name"]{tag_filter};'
                for tag_filter in _FILTERS[category]
            )
            node_stmts = "\n".join(
                f'node({bbox})["name"]{tag_filter};' for tag_filter in _FILTERS[category]
            )
            return (
                f"[out:json][timeout:{self._query_timeout_seconds}];\n"
                f"(\n{geom_stmts}\n);\n"
                f"out center {geom_limit};\n"
                f"(\n{node_stmts}\n);\n"
                f"out center {node_limit};"
            )

        # For food and cafes: fast node + way query in a single block
        stmts = "\n".join(
            f'node({bbox})["name"]{tag_filter};\nway({bbox})["name"]{tag_filter};'
            for tag_filter in _FILTERS[category]
        )
        return (
            f"[out:json][timeout:{self._query_timeout_seconds}];\n"
            f"(\n{stmts}\n);\n"
            f"out center {bounded_limit};"
        )

    def _build_multi_category_query(
        self,
        latitude: float,
        longitude: float,
        categories: list[DiscoveryCategory],
        limit_per_category: int,
        radius_meters: int | None = None,
    ) -> str:
        bbox = self._bounding_box(latitude, longitude, radius_meters=radius_meters)
        statements = "\n".join(
            f'nwr({bbox})["name"]{tag_filter};'
            for category in categories
            for tag_filter in _FILTERS[category]
        )
        bounded_limit = max(1, min(limit_per_category * len(categories), 200))
        return (
            f"[out:json][timeout:{self._query_timeout_seconds}];\n"
            f"(\n{statements}\n);\n"
            f"out center {bounded_limit};"
        )

    def _bounding_box(
        self,
        latitude: float,
        longitude: float,
        radius_meters: int | None = None,
    ) -> str:
        radius = radius_meters if radius_meters is not None else self._radius_meters
        latitude_delta = radius / 111_320
        longitude_scale = max(cos(radians(latitude)), 0.2)
        longitude_delta = radius / (111_320 * longitude_scale)
        return (
            f"{latitude - latitude_delta:.6f},"
            f"{longitude - longitude_delta:.6f},"
            f"{latitude + latitude_delta:.6f},"
            f"{longitude + longitude_delta:.6f}"
        )

    async def _request(self, query: str) -> httpx.Response:
        headers = {
            "User-Agent": "YatraCanvas/0.1 (https://yatracanvas.org; OpenStreetMap POI discovery)",
            "Accept": "application/json, */*",
        }
        max_attempts = 2
        for attempt in range(max_attempts):
            try:
                if self._client is not None:
                    response = await self._client.post(
                        self._api_url,
                        data={"data": query},
                        headers=headers,
                    )
                else:
                    async with httpx.AsyncClient(timeout=self._timeout) as client:
                        response = await client.post(
                            self._api_url,
                            data={"data": query},
                            headers=headers,
                        )
                if response.status_code in {429, 502, 503, 504} and attempt < max_attempts - 1:
                    retry_after_str = response.headers.get("Retry-After")
                    try:
                        wait_time = min(max(float(retry_after_str), 1.0), 10.0) if retry_after_str else (3.0 * (attempt + 1))
                    except (TypeError, ValueError):
                        wait_time = 3.0 * (attempt + 1)
                    logger.info(
                        "Overpass server returned HTTP %d, backing off for %.1fs (attempt %d/%d)",
                        response.status_code,
                        wait_time,
                        attempt + 1,
                        max_attempts,
                    )
                    await asyncio.sleep(wait_time)
                    continue
                return response
            except httpx.TimeoutException as exc:
                raise OpenStreetMapPlacesTimeoutError(
                    "OpenStreetMap discovery did not respond in time."
                ) from exc
            except httpx.RequestError as exc:
                if attempt < max_attempts - 1:
                    await asyncio.sleep(1.0)
                    continue
                raise OpenStreetMapPlacesUnavailableError(
                    "OpenStreetMap discovery could not be reached."
                ) from exc
        return response

    @staticmethod
    def _raise_for_status(response: httpx.Response) -> None:
        if response.is_success:
            return
        if response.status_code == 429:
            raise OpenStreetMapPlacesRateLimitError(response.headers.get("Retry-After"))
        if response.status_code in (504, 408):
            raise OpenStreetMapPlacesTimeoutError(
                f"OpenStreetMap discovery timed out on server (HTTP {response.status_code})."
            )
        raise OpenStreetMapPlacesUnavailableError(
            f"OpenStreetMap discovery is temporarily unavailable (HTTP {response.status_code})."
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
