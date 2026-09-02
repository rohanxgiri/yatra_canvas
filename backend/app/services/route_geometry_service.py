"""Real road-route geometry service with openrouteservice and OSRM providers."""

from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import hashlib
from typing import Protocol
from uuid import UUID

import httpx
from sqlmodel import Session, select

from app.models import Place, Trip, TripItinerary
from app.schemas.route_geometry import (
    DayRouteGeometryRead,
    RouteLegGeometryRead,
    TripRouteGeometryRead,
)


class RouteGeometryError(Exception):
    """Base exception for route geometry operations."""
    pass


class RouteGeometryTripNotFoundError(RouteGeometryError):
    """Raised when the specified trip cannot be found."""
    pass


class RouteGeometryValidationError(RouteGeometryError):
    """Raised when coordinates or request parameters are invalid."""
    pass


class RouteGeometryConfigurationError(RouteGeometryError):
    """Raised when provider configuration or required credentials are missing."""
    pass


class RouteGeometryTimeoutError(RouteGeometryError):
    """Raised when a routing provider request times out."""
    pass


class RouteGeometryUnavailableError(RouteGeometryError):
    """Raised when a routing provider is unreachable or reports an upstream error."""
    pass


@dataclass(frozen=True)
class RoutePoint:
    latitude: float
    longitude: float


@dataclass(frozen=True)
class LegData:
    start_latitude: float
    start_longitude: float
    end_latitude: float
    end_longitude: float
    distance_meters: float | None = None
    duration_seconds: float | None = None


@dataclass(frozen=True)
class RouteGeometryData:
    coordinates: list[list[float]]  # List of [latitude, longitude]
    distance_meters: float | None = None
    duration_seconds: float | None = None
    legs: list[LegData] = None  # type: ignore[assignment]

    def __post_init__(self) -> None:
        if self.legs is None:
            object.__setattr__(self, "legs", [])


class RouteGeometryProvider(Protocol):
    """Provider-neutral abstraction for road-route geometry."""

    async def get_route_geometry(
        self,
        waypoints: list[RoutePoint],
    ) -> RouteGeometryData: ...


class OpenRouteServiceGeometryProvider:
    """openrouteservice directions v2 provider (GeoJSON)."""

    def __init__(
        self,
        api_key: str | None = None,
        base_url: str = "https://api.openrouteservice.org",
        timeout_seconds: float = 10.0,
    ) -> None:
        self._api_key = api_key
        self._base_url = base_url.rstrip("/")
        self._timeout = timeout_seconds

    async def get_route_geometry(
        self,
        waypoints: list[RoutePoint],
    ) -> RouteGeometryData:
        if not self._api_key and "api.openrouteservice.org" in self._base_url:
            raise RouteGeometryConfigurationError(
                "OPENROUTESERVICE_API_KEY is required for hosted openrouteservice directions."
            )

        # openrouteservice expects coordinates as [longitude, latitude]
        ors_coords = [[p.longitude, p.latitude] for p in waypoints]
        url = f"{self._base_url}/v2/directions/driving-car/geojson"
        headers: dict[str, str] = {
            "Content-Type": "application/json; charset=utf-8",
            "Accept": "application/json, application/geo+json",
        }
        if self._api_key:
            headers["Authorization"] = self._api_key

        payload = {"coordinates": ors_coords}

        try:
            async with httpx.AsyncClient(timeout=self._timeout) as client:
                response = await client.post(url, json=payload, headers=headers)
        except httpx.TimeoutException as exc:
            raise RouteGeometryTimeoutError(
                f"openrouteservice timed out after {self._timeout}s."
            ) from exc
        except httpx.RequestError as exc:
            raise RouteGeometryUnavailableError(
                f"Failed to connect to openrouteservice: {exc}"
            ) from exc

        if response.status_code == 401 or response.status_code == 403:
            raise RouteGeometryConfigurationError(
                "openrouteservice authentication failed. Check OPENROUTESERVICE_API_KEY."
            )
        if response.status_code >= 500:
            raise RouteGeometryUnavailableError(
                f"openrouteservice server error ({response.status_code}): {response.text[:200]}"
            )
        if response.status_code >= 400:
            raise RouteGeometryUnavailableError(
                f"openrouteservice rejected the route request ({response.status_code}): {response.text[:200]}"
            )

        data = response.json()
        features = data.get("features", [])
        if not features:
            raise RouteGeometryUnavailableError("openrouteservice returned no route features.")

        feature = features[0]
        geom = feature.get("geometry", {})
        raw_coords = geom.get("coordinates", [])
        # Convert GeoJSON [lon, lat] to YatraCanvas [lat, lon]
        coordinates = [[point[1], point[0]] for point in raw_coords]

        props = feature.get("properties", {})
        summary = props.get("summary", {})
        distance = summary.get("distance")
        duration = summary.get("duration")

        legs: list[LegData] = []
        segments = props.get("segments", [])
        for i, seg in enumerate(segments):
            if i < len(waypoints) - 1:
                legs.append(
                    LegData(
                        start_latitude=waypoints[i].latitude,
                        start_longitude=waypoints[i].longitude,
                        end_latitude=waypoints[i + 1].latitude,
                        end_longitude=waypoints[i + 1].longitude,
                        distance_meters=seg.get("distance"),
                        duration_seconds=seg.get("duration"),
                    )
                )

        return RouteGeometryData(
            coordinates=coordinates,
            distance_meters=distance,
            duration_seconds=duration,
            legs=legs,
        )


class OSRMGeometryProvider:
    """OSRM (Open Source Routing Machine) keyless open-data directions provider."""

    def __init__(
        self,
        base_url: str = "https://router.project-osrm.org",
        timeout_seconds: float = 10.0,
    ) -> None:
        self._base_url = base_url.rstrip("/")
        self._timeout = timeout_seconds

    async def get_route_geometry(
        self,
        waypoints: list[RoutePoint],
    ) -> RouteGeometryData:
        coords_str = ";".join(f"{p.longitude:.6f},{p.latitude:.6f}" for p in waypoints)
        url = f"{self._base_url}/route/v1/driving/{coords_str}?overview=full&geometries=geojson"

        try:
            async with httpx.AsyncClient(timeout=self._timeout) as client:
                response = await client.get(url)
        except httpx.TimeoutException as exc:
            raise RouteGeometryTimeoutError(
                f"OSRM routing timed out after {self._timeout}s."
            ) from exc
        except httpx.RequestError as exc:
            raise RouteGeometryUnavailableError(
                f"Failed to connect to OSRM router: {exc}"
            ) from exc

        if response.status_code >= 500:
            raise RouteGeometryUnavailableError(
                f"OSRM server error ({response.status_code}): {response.text[:200]}"
            )
        if response.status_code >= 400:
            raise RouteGeometryUnavailableError(
                f"OSRM rejected route request ({response.status_code}): {response.text[:200]}"
            )

        data = response.json()
        code = data.get("code")
        if code != "Ok":
            message = data.get("message", "Unknown OSRM error")
            raise RouteGeometryUnavailableError(f"OSRM route unavailable ({code}): {message}")

        routes = data.get("routes", [])
        if not routes:
            raise RouteGeometryUnavailableError("OSRM returned no route options.")

        route = routes[0]
        geom = route.get("geometry", {})
        raw_coords = geom.get("coordinates", [])
        coordinates = [[point[1], point[0]] for point in raw_coords]

        distance = route.get("distance")
        duration = route.get("duration")

        legs: list[LegData] = []
        raw_legs = route.get("legs", [])
        for i, leg in enumerate(raw_legs):
            if i < len(waypoints) - 1:
                legs.append(
                    LegData(
                        start_latitude=waypoints[i].latitude,
                        start_longitude=waypoints[i].longitude,
                        end_latitude=waypoints[i + 1].latitude,
                        end_longitude=waypoints[i + 1].longitude,
                        distance_meters=leg.get("distance"),
                        duration_seconds=leg.get("duration"),
                    )
                )

        return RouteGeometryData(
            coordinates=coordinates,
            distance_meters=distance,
            duration_seconds=duration,
            legs=legs,
        )


class RouteGeometryService:
    """Orchestrates itinerary extraction, validation, caching, and road geometry normalization."""

    def __init__(self, cache_ttl_minutes: int = 60) -> None:
        self._cache_ttl = timedelta(minutes=cache_ttl_minutes)
        self._cache: dict[str, tuple[datetime, RouteGeometryData]] = {}

    @staticmethod
    def _validate_coordinate(latitude: float, longitude: float) -> None:
        if not (-90.0 <= latitude <= 90.0):
            raise RouteGeometryValidationError(
                f"Invalid latitude {latitude}: must be between -90 and 90."
            )
        if not (-180.0 <= longitude <= 180.0):
            raise RouteGeometryValidationError(
                f"Invalid longitude {longitude}: must be between -180 and 180."
            )

    @staticmethod
    def _cache_key(trip_id: UUID, day_number: int, waypoints: list[RoutePoint]) -> str:
        pts_str = ",".join(f"{p.latitude:.6f}:{p.longitude:.6f}" for p in waypoints)
        fingerprint = hashlib.sha256(pts_str.encode("utf-8")).hexdigest()[:16]
        return f"{trip_id}:{day_number}:{fingerprint}"

    def _get_cached(self, key: str, now: datetime | None = None) -> RouteGeometryData | None:
        current_time = now or datetime.now(timezone.utc)
        entry = self._cache.get(key)
        if entry is None:
            return None
        cached_time, data = entry
        if current_time - cached_time > self._cache_ttl:
            self._cache.pop(key, None)
            return None
        return data

    def _set_cached(
        self,
        key: str,
        data: RouteGeometryData,
        now: datetime | None = None,
    ) -> None:
        current_time = now or datetime.now(timezone.utc)
        self._cache[key] = (current_time, data)

    def invalidate_trip_cache(self, trip_id: UUID) -> None:
        prefix = f"{trip_id}:"
        keys_to_remove = [k for k in self._cache if k.startswith(prefix)]
        for k in keys_to_remove:
            self._cache.pop(k, None)

    async def get_trip_geometry(
        self,
        session: Session,
        trip_id: UUID,
        provider: RouteGeometryProvider,
        day_number: int | None = None,
        *,
        now: datetime | None = None,
    ) -> TripRouteGeometryRead:
        trip = session.get(Trip, trip_id)
        if trip is None:
            raise RouteGeometryTripNotFoundError(f"Trip {trip_id} not found.")

        query = (
            select(TripItinerary)
            .where(TripItinerary.trip_id == trip_id)
            .order_by(TripItinerary.day_number, TripItinerary.visit_order)
        )
        if day_number is not None:
            if day_number < 1:
                raise RouteGeometryValidationError("day_number must be greater than or equal to 1.")
            query = query.where(TripItinerary.day_number == day_number)

        itinerary_rows = list(session.exec(query).all())

        if not itinerary_rows:
            return TripRouteGeometryRead(
                trip_id=trip_id,
                days=[],
                total_distance_meters=0.0,
                total_duration_seconds=0.0,
            )

        days_map: dict[int, list[TripItinerary]] = defaultdict(list)
        for row in itinerary_rows:
            days_map[row.day_number].append(row)

        day_results: list[DayRouteGeometryRead] = []
        overall_distance = 0.0
        overall_duration = 0.0

        for day, places_in_day in sorted(days_map.items()):
            waypoints: list[RoutePoint] = []

            # Prepend start location if available
            if trip.start_latitude is not None and trip.start_longitude is not None:
                self._validate_coordinate(trip.start_latitude, trip.start_longitude)
                waypoints.append(
                    RoutePoint(
                        latitude=trip.start_latitude,
                        longitude=trip.start_longitude,
                    )
                )

            for item in places_in_day:
                place = session.get(Place, item.place_id)
                if place is None:
                    continue
                self._validate_coordinate(place.latitude, place.longitude)
                waypoints.append(
                    RoutePoint(
                        latitude=place.latitude,
                        longitude=place.longitude,
                    )
                )

            # Need at least 2 points for a meaningful road route
            if len(waypoints) < 2:
                day_results.append(
                    DayRouteGeometryRead(
                        day_number=day,
                        coordinates=[],
                        distance_meters=0.0,
                        duration_seconds=0.0,
                        legs=[],
                    )
                )
                continue

            cache_key = self._cache_key(trip_id, day, waypoints)
            geom_data = self._get_cached(cache_key, now=now)
            if geom_data is None:
                geom_data = await provider.get_route_geometry(waypoints)
                self._set_cached(cache_key, geom_data, now=now)

            if geom_data.distance_meters is not None:
                overall_distance += geom_data.distance_meters
            if geom_data.duration_seconds is not None:
                overall_duration += geom_data.duration_seconds

            day_results.append(
                DayRouteGeometryRead(
                    day_number=day,
                    coordinates=geom_data.coordinates,
                    distance_meters=geom_data.distance_meters,
                    duration_seconds=geom_data.duration_seconds,
                    legs=[
                        RouteLegGeometryRead(
                            start_latitude=leg.start_latitude,
                            start_longitude=leg.start_longitude,
                            end_latitude=leg.end_latitude,
                            end_longitude=leg.end_longitude,
                            distance_meters=leg.distance_meters,
                            duration_seconds=leg.duration_seconds,
                        )
                        for leg in geom_data.legs
                    ],
                )
            )

        return TripRouteGeometryRead(
            trip_id=trip_id,
            days=day_results,
            total_distance_meters=round(overall_distance, 1) if overall_distance > 0 else 0.0,
            total_duration_seconds=round(overall_duration, 1) if overall_duration > 0 else 0.0,
        )
