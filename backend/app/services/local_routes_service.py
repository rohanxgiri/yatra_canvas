"""Offline route-cost estimates for the zero-paid development path."""

from math import asin, ceil, cos, radians, sin, sqrt

from app.services.google_routes_service import RouteCoordinate, RouteMatrixLeg


class LocalRoutesService:
    """Estimate pair costs from coordinates without calling an external API."""

    _earth_radius_meters = 6_371_000
    _road_distance_factor = 1.3
    _average_speed_meters_per_second = 25_000 / 3600

    async def compute_matrix(
        self,
        origins: list[RouteCoordinate],
        destinations: list[RouteCoordinate],
    ) -> dict[tuple[int, int], RouteMatrixLeg]:
        matrix: dict[tuple[int, int], RouteMatrixLeg] = {}
        for origin_index, origin in enumerate(origins):
            for destination_index, destination in enumerate(destinations):
                direct_distance = self._haversine_meters(origin, destination)
                estimated_distance = max(
                    1,
                    round(direct_distance * self._road_distance_factor),
                )
                estimated_seconds = max(
                    60,
                    ceil(estimated_distance / self._average_speed_meters_per_second),
                )
                matrix[(origin_index, destination_index)] = RouteMatrixLeg(
                    distance_meters=estimated_distance,
                    static_duration_seconds=estimated_seconds,
                    traffic_duration_seconds=None,
                )
        return matrix

    @classmethod
    def _haversine_meters(
        cls,
        origin: RouteCoordinate,
        destination: RouteCoordinate,
    ) -> float:
        origin_latitude = radians(origin.latitude)
        destination_latitude = radians(destination.latitude)
        latitude_delta = destination_latitude - origin_latitude
        longitude_delta = radians(destination.longitude - origin.longitude)
        value = (
            sin(latitude_delta / 2) ** 2
            + cos(origin_latitude)
            * cos(destination_latitude)
            * sin(longitude_delta / 2) ** 2
        )
        return cls._earth_radius_meters * 2 * asin(sqrt(value))
