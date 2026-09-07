"""Persistent pair-wise route cache with provider-neutral refreshes."""

from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Protocol
from uuid import UUID

from sqlalchemy import insert
from sqlmodel import Session, select

from app.models import Place, RouteMatrixCache, Trip
from app.services.google_routes_service import (
    GoogleRoutesConfigurationError,
    GoogleRoutesTimeoutError,
    GoogleRoutesUnavailableError,
    RouteCoordinate,
    RouteMatrixLeg,
)

TRAVEL_MODE = "local_estimate"


class RouteMatrixProvider(Protocol):
    async def compute_matrix(
        self,
        origins: list[RouteCoordinate],
        destinations: list[RouteCoordinate],
    ) -> dict[tuple[int, int], RouteMatrixLeg]: ...


@dataclass(frozen=True)
class RouteNode:
    key: str
    location_type: str
    name: str
    latitude: float
    longitude: float
    place_id: UUID | None = None

    @property
    def coordinate(self) -> RouteCoordinate:
        return RouteCoordinate(self.latitude, self.longitude)

    @classmethod
    def for_start(cls, trip: Trip) -> "RouteNode":
        if (
            not trip.start_location_type
            or not trip.start_location_name
            or trip.start_latitude is None
            or trip.start_longitude is None
        ):
            raise ValueError("Select a trip start location before optimization.")
        key = (
            f"start:{trip.start_location_type}:"
            f"{trip.start_latitude:.6f}:{trip.start_longitude:.6f}"
        )
        return cls(
            key=key,
            location_type=trip.start_location_type,
            name=trip.start_location_name,
            latitude=trip.start_latitude,
            longitude=trip.start_longitude,
        )

    @classmethod
    def for_place(cls, place: Place) -> "RouteNode":
        return cls(
            key=f"place:{place.id}",
            location_type="place",
            name=place.name,
            latitude=place.latitude,
            longitude=place.longitude,
            place_id=place.id,
        )


class RouteMatrixService:
    def __init__(self, traffic_ttl_minutes: int = 30) -> None:
        self._traffic_ttl = timedelta(minutes=traffic_ttl_minutes)

    async def get_complete_matrix(
        self,
        session: Session,
        trip: Trip,
        places: list[Place],
        provider: RouteMatrixProvider,
        *,
        start_node: RouteNode | None = None,
        now: datetime | None = None,
    ) -> tuple[RouteNode, list[RouteNode], dict[tuple[str, str], RouteMatrixLeg]]:
        current_time = now or datetime.now(timezone.utc)
        start = start_node if start_node is not None else RouteNode.for_start(trip)
        place_nodes = [RouteNode.for_place(place) for place in places]
        nodes = [start, *place_nodes]

        required_pairs = [
            (origin, destination)
            for origin in nodes
            for destination in nodes
            if origin.key != destination.key
        ]

        rows = list(
            session.exec(
                select(RouteMatrixCache).where(
                    RouteMatrixCache.trip_id == trip.id,
                    RouteMatrixCache.travel_mode == TRAVEL_MODE,
                )
            ).all()
        )
        cached = {(row.from_key, row.to_key): row for row in rows}
        refresh_by_origin: dict[str, list[RouteNode]] = defaultdict(list)
        nodes_by_key = {node.key: node for node in nodes}
        has_missing = False
        for origin, destination in required_pairs:
            row = cached.get((origin.key, destination.key))
            if row is None:
                has_missing = True
                refresh_by_origin[origin.key].append(destination)
            elif self._needs_refresh(row, current_time):
                refresh_by_origin[origin.key].append(destination)

        offline = False
        new_rows: list[RouteMatrixCache] = []
        cache_changed = False
        for origin_key, destinations in refresh_by_origin.items():
            origin = nodes_by_key[origin_key]
            try:
                fetched = await provider.compute_matrix(
                    [origin.coordinate],
                    [destination.coordinate for destination in destinations],
                )
            except (
                GoogleRoutesConfigurationError,
                GoogleRoutesTimeoutError,
                GoogleRoutesUnavailableError,
            ):
                if has_missing:
                    raise
                offline = True
                break

            for destination_index, destination in enumerate(destinations):
                leg = fetched.get((0, destination_index))
                if leg is None:
                    if (origin.key, destination.key) not in cached:
                        raise GoogleRoutesUnavailableError(
                            "Google Routes could not calculate every missing route pair."
                        )
                    continue
                row = cached.get((origin.key, destination.key))
                if row is None:
                    row = RouteMatrixCache(
                        trip_id=trip.id,
                        from_key=origin.key,
                        to_key=destination.key,
                        from_location_type=origin.location_type,
                        to_location_type=destination.location_type,
                        distance_meters=leg.distance_meters,
                        static_duration_seconds=leg.static_duration_seconds,
                        travel_mode=TRAVEL_MODE,
                        calculated_at=current_time,
                    )
                    cached[(origin.key, destination.key)] = row
                    new_rows.append(row)
                self._write_row(
                    row,
                    origin,
                    destination,
                    leg,
                    current_time,
                )
                cache_changed = True
        if new_rows:
            session.execute(
                insert(RouteMatrixCache).values(
                    [row.model_dump() for row in new_rows]
                )
            )
        if cache_changed:
            # The optimizer still needs the trip, saved places, places, and all
            # cache rows below. Prevent this intermediate cache commit from
            # expiring them and triggering hundreds of lazy reload queries.
            expire_on_commit = session.expire_on_commit
            session.expire_on_commit = False
            try:
                session.commit()
            finally:
                session.expire_on_commit = expire_on_commit

        matrix: dict[tuple[str, str], RouteMatrixLeg] = {}
        for origin, destination in required_pairs:
            row = cached.get((origin.key, destination.key))
            if row is None:
                raise GoogleRoutesUnavailableError(
                    "No cached route is available for every selected location."
                )
            traffic_duration = (
                row.traffic_duration_seconds
                if not offline and self._is_traffic_fresh(row, current_time)
                else None
            )
            matrix[(origin.key, destination.key)] = RouteMatrixLeg(
                distance_meters=row.distance_meters,
                static_duration_seconds=row.static_duration_seconds,
                traffic_duration_seconds=traffic_duration,
            )
        return start, place_nodes, matrix

    def _write_row(
        self,
        row: RouteMatrixCache,
        origin: RouteNode,
        destination: RouteNode,
        leg: RouteMatrixLeg,
        now: datetime,
    ) -> None:
        row.from_place_id = origin.place_id
        row.to_place_id = destination.place_id
        row.from_location_type = origin.location_type
        row.from_name = origin.name
        row.from_latitude = origin.latitude
        row.from_longitude = origin.longitude
        row.to_location_type = destination.location_type
        row.to_name = destination.name
        row.to_latitude = destination.latitude
        row.to_longitude = destination.longitude
        row.distance_meters = leg.distance_meters
        row.static_duration_seconds = leg.static_duration_seconds
        row.traffic_duration_seconds = leg.traffic_duration_seconds
        row.calculated_at = now
        row.expires_at = now + self._traffic_ttl

    @staticmethod
    def _is_traffic_fresh(row: RouteMatrixCache, now: datetime) -> bool:
        if row.traffic_duration_seconds is None or row.expires_at is None:
            return False
        expires_at = row.expires_at
        if expires_at.tzinfo is None:
            expires_at = expires_at.replace(tzinfo=timezone.utc)
        return expires_at > now

    @classmethod
    def _needs_refresh(cls, row: RouteMatrixCache, now: datetime) -> bool:
        # Static local estimates have no volatile traffic value. They stay valid
        # until an explicit trip/place invalidation removes the affected pair.
        if row.traffic_duration_seconds is None:
            return False
        return not cls._is_traffic_fresh(row, now)
