"""Google Routes matrix client and normalized route-leg values."""

from dataclasses import dataclass
from math import ceil
import re
from typing import Any

import httpx


ROUTE_MATRIX_URL = (
    "https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix"
)
ROUTE_MATRIX_FIELD_MASK = (
    "originIndex,destinationIndex,status,condition,distanceMeters,"
    "duration,staticDuration"
)
_DURATION_PATTERN = re.compile(r"^(\d+(?:\.\d+)?)s$")


class GoogleRoutesError(Exception):
    pass


class GoogleRoutesConfigurationError(GoogleRoutesError):
    pass


class GoogleRoutesTimeoutError(GoogleRoutesError):
    pass


class GoogleRoutesUnavailableError(GoogleRoutesError):
    pass


class GoogleRoutesValidationError(GoogleRoutesError):
    pass


@dataclass(frozen=True)
class RouteCoordinate:
    latitude: float
    longitude: float


@dataclass(frozen=True)
class RouteMatrixLeg:
    distance_meters: int
    static_duration_seconds: int
    traffic_duration_seconds: int | None = None

    @property
    def preferred_duration_seconds(self) -> int:
        return self.traffic_duration_seconds or self.static_duration_seconds


class GoogleRoutesService:
    """Fetch road travel matrices without exposing the Google API key."""

    def __init__(
        self,
        api_key: str | None,
        *,
        client: httpx.AsyncClient | None = None,
        timeout_seconds: float = 12.0,
    ) -> None:
        self._api_key = api_key.strip() if api_key else None
        self._client = client
        self._timeout = httpx.Timeout(timeout_seconds)

    async def compute_matrix(
        self,
        origins: list[RouteCoordinate],
        destinations: list[RouteCoordinate],
    ) -> dict[tuple[int, int], RouteMatrixLeg]:
        if not self._api_key:
            raise GoogleRoutesConfigurationError(
                "Google Routes is not configured on the backend."
            )
        if not origins or not destinations:
            raise GoogleRoutesValidationError(
                "At least one route origin and destination are required."
            )
        if len(origins) * len(destinations) > 625:
            raise GoogleRoutesValidationError(
                "The selected locations exceed the Google route-matrix limit."
            )

        response = await self._request(
            headers={
                "Content-Type": "application/json",
                "X-Goog-Api-Key": self._api_key,
                "X-Goog-FieldMask": ROUTE_MATRIX_FIELD_MASK,
            },
            json={
                "origins": [self._origin_payload(point) for point in origins],
                "destinations": [
                    self._destination_payload(point) for point in destinations
                ],
                "travelMode": "DRIVE",
                "routingPreference": "TRAFFIC_AWARE",
                "languageCode": "en",
                "regionCode": "in",
                "units": "METRIC",
            },
        )
        if not response.is_success:
            raise GoogleRoutesUnavailableError(
                "Google Routes is temporarily unavailable."
            )
        try:
            payload = response.json()
        except ValueError as exc:
            raise GoogleRoutesUnavailableError(
                "Google Routes returned an invalid route matrix."
            ) from exc
        if not isinstance(payload, list):
            raise GoogleRoutesUnavailableError(
                "Google Routes returned an invalid route matrix."
            )

        matrix: dict[tuple[int, int], RouteMatrixLeg] = {}
        for element in payload:
            parsed = self._parse_element(element)
            if parsed is not None:
                key, leg = parsed
                matrix[key] = leg
        if not matrix:
            raise GoogleRoutesUnavailableError(
                "Google Routes could not find drivable routes between the selected locations."
            )
        return matrix

    async def _request(self, **kwargs: Any) -> httpx.Response:
        try:
            if self._client is not None:
                return await self._client.post(ROUTE_MATRIX_URL, **kwargs)
            async with httpx.AsyncClient(timeout=self._timeout) as client:
                return await client.post(ROUTE_MATRIX_URL, **kwargs)
        except httpx.TimeoutException as exc:
            raise GoogleRoutesTimeoutError(
                "Google Routes did not respond in time."
            ) from exc
        except httpx.RequestError as exc:
            raise GoogleRoutesUnavailableError(
                "Google Routes could not be reached."
            ) from exc

    @staticmethod
    def _origin_payload(point: RouteCoordinate) -> dict[str, object]:
        return {"waypoint": GoogleRoutesService._waypoint(point)}

    @staticmethod
    def _destination_payload(point: RouteCoordinate) -> dict[str, object]:
        return {"waypoint": GoogleRoutesService._waypoint(point)}

    @staticmethod
    def _waypoint(point: RouteCoordinate) -> dict[str, object]:
        return {
            "location": {
                "latLng": {
                    "latitude": point.latitude,
                    "longitude": point.longitude,
                }
            }
        }

    @staticmethod
    def _parse_element(
        element: object,
    ) -> tuple[tuple[int, int], RouteMatrixLeg] | None:
        if not isinstance(element, dict):
            return None
        status = element.get("status", {})
        if isinstance(status, dict) and status.get("code") not in {None, 0}:
            return None
        if element.get("condition") not in {None, "ROUTE_EXISTS"}:
            return None
        try:
            origin_index = int(element.get("originIndex", 0))
            destination_index = int(element.get("destinationIndex", 0))
            distance_meters = int(element["distanceMeters"])
            traffic_seconds = GoogleRoutesService._duration_seconds(
                str(element["duration"])
            )
            static_seconds = GoogleRoutesService._duration_seconds(
                str(element.get("staticDuration", element["duration"]))
            )
        except (KeyError, TypeError, ValueError):
            return None
        if distance_meters < 0:
            return None
        return (
            (origin_index, destination_index),
            RouteMatrixLeg(
                distance_meters=distance_meters,
                static_duration_seconds=static_seconds,
                traffic_duration_seconds=traffic_seconds,
            ),
        )

    @staticmethod
    def _duration_seconds(value: str) -> int:
        match = _DURATION_PATTERN.fullmatch(value)
        if match is None:
            raise ValueError("Invalid Google duration")
        return ceil(float(match.group(1)))
