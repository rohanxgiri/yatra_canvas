"""Google OR-Tools VRPTW (Vehicle Routing Problem with Time Windows) solver.

Solves multi-day tourist itineraries with:
- Normalized weekday opening intervals and closures
- Visit durations (service time per category)
- Active TripDay routes with individual sightseeing windows
- Lunch breaks (break intervals in midday window)
- Native day assignment locks and legacy conditional order locks
- Priority, must-visit and lock retention via optional-visit penalties
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, time, timedelta
from itertools import pairwise
from math import ceil
from uuid import UUID

from ortools.constraint_solver import pywrapcp, routing_enums_pb2

from app.core.itinerary_constants import (
    DEFAULT_DAY_END_TIME,
    DEFAULT_DAY_START_TIME,
    DEFAULT_LUNCH_BREAK_MINUTES,
    LUNCH_BREAK_EARLIEST_START,
    LUNCH_BREAK_LATEST_START,
    estimate_visit_duration,
)
from app.models.entities import Place, TripDay, UserSavedPlace
from app.models.entities import PlaceOpeningHours as WeeklyHours
from app.schemas.route_optimization import (
    ItineraryBreakRead,
    OptimizedPlaceRead,
    UnscheduledPlaceRead,
)
from app.services.google_routes_service import RouteMatrixLeg
from app.services.itinerary_timing_service import PlaceOpeningHours
from app.services.route_matrix_service import RouteNode


@dataclass(frozen=True, slots=True)
class VrptwSolution:
    optimized_places: list[OptimizedPlaceRead]
    breaks: list[ItineraryBreakRead]
    conflicts: list[str]
    total_distance_meters: int
    total_travel_minutes: int
    unvisited_place_ids: list[UUID] = field(default_factory=list)
    unscheduled_places: list[UnscheduledPlaceRead] = field(default_factory=list)


class VrptwSolverService:
    """Multi-day VRPTW solver engine backed by Google OR-Tools."""

    def __init__(
        self,
        day_start_time: time = DEFAULT_DAY_START_TIME,
        day_end_time: time = DEFAULT_DAY_END_TIME,
        lunch_earliest_start: time = LUNCH_BREAK_EARLIEST_START,
        lunch_latest_start: time = LUNCH_BREAK_LATEST_START,
        lunch_duration_minutes: int = DEFAULT_LUNCH_BREAK_MINUTES,
        time_limit_seconds: float = 5.0,
    ) -> None:
        self.day_start_time = day_start_time
        self.day_end_time = day_end_time
        self.lunch_earliest_start = lunch_earliest_start
        self.lunch_latest_start = lunch_latest_start
        self.lunch_duration_minutes = lunch_duration_minutes
        self.time_limit_seconds = time_limit_seconds

    def solve(
        self,
        start_node: RouteNode,
        place_nodes: list[RouteNode],
        places: list[Place],
        saved_rows: list[UserSavedPlace],
        matrix: dict[tuple[str, str], RouteMatrixLeg],
        trip_days: int,
        start_date: date | None = None,
        opening_hours_map: dict[UUID, PlaceOpeningHours] | None = None,
        day_configs: list[TripDay] | None = None,
        weekly_hours_map: dict[UUID, dict[int, WeeklyHours]] | None = None,
    ) -> VrptwSolution:
        num_places = len(places)
        if num_places == 0:
            return VrptwSolution(
                optimized_places=[],
                breaks=[],
                conflicts=[],
                total_distance_meters=0,
                total_travel_minutes=0,
            )

        opening_hours = opening_hours_map or {}
        base_date = start_date or date.today()  # noqa: DTZ011 - legacy local-date fallback
        days = (
            day_configs
            if day_configs is not None
            else [
                TripDay(
                    trip_id=saved_rows[0].trip_id,
                    day_number=n + 1,
                    date=base_date + timedelta(days=n),
                    start_time=self.day_start_time,
                    end_time=self.day_end_time,
                )
                for n in range(max(1, trip_days))
            ]
        )
        active_days = sorted(
            (
                d
                for d in days
                if d.day_type != "REST"
                and d.start_time is not None
                and d.end_time is not None
                and d.end_time > d.start_time
            ),
            key=lambda d: d.day_number,
        )
        num_vehicles = len(active_days)
        num_locations = num_places + 1
        weekly_hours = weekly_hours_map or {}

        def unscheduled(i, reason):
            return UnscheduledPlaceRead(
                place_id=places[i].id,
                name=places[i].name,
                reason=reason,
                assigned_day_id=saved_rows[i].assigned_day_id,
            )

        if not active_days:
            dropped = [
                unscheduled(
                    i,
                    "LOCKED_DAY_INFEASIBLE"
                    if s.assignment_mode == "LOCKED"
                    else "NO_TIME_AVAILABLE",
                )
                for i, s in enumerate(saved_rows)
            ]
            return VrptwSolution([], [], [], 0, 0, [p.id for p in places], dropped)

        def minutes(t):
            return t.hour * 60 + t.minute

        # Separate route time domains encode actual weekdays without duplicating POIs.
        windows = [
            (v * 1440 + minutes(d.start_time), v * 1440 + minutes(d.end_time))
            for v, d in enumerate(active_days)
        ]
        max_day_capacity = num_vehicles * 1440
        lunch_earliest_min = minutes(self.lunch_earliest_start)
        lunch_latest_min = minutes(self.lunch_latest_start)

        # Build distance and travel time lookup tables
        travel_times: list[list[int]] = [
            [0] * num_locations for _ in range(num_locations)
        ]
        travel_seconds: list[list[int]] = [
            [0] * num_locations for _ in range(num_locations)
        ]
        distances: list[list[int]] = [[0] * num_locations for _ in range(num_locations)]
        service_times: list[int] = [0] * num_locations

        for i in range(num_places):
            service_times[i + 1] = estimate_visit_duration(places[i].category)

        for i in range(num_locations):
            for j in range(num_locations):
                if i == j or j == 0:
                    travel_times[i][j] = 0
                    travel_seconds[i][j] = 0
                    distances[i][j] = 0
                    continue
                from_key = start_node.key if i == 0 else place_nodes[i - 1].key
                to_key = place_nodes[j - 1].key
                leg = matrix.get((from_key, to_key))
                if leg is None:
                    # Symmetrical fallback if directional pair is absent
                    leg = matrix.get((to_key, from_key))
                if leg is None:
                    leg = matrix.get((start_node.key, to_key))
                if leg is None:
                    raise ValueError("No routing leg available between locations.")
                dur = max(1, ceil(leg.preferred_duration_seconds / 60))
                travel_times[i][j] = dur
                travel_seconds[i][j] = leg.preferred_duration_seconds
                distances[i][j] = leg.distance_meters

        # Create OR-Tools routing model
        starts = [0] * num_vehicles
        ends = [0] * num_vehicles
        manager = pywrapcp.RoutingIndexManager(
            num_locations, num_vehicles, starts, ends
        )
        routing = pywrapcp.RoutingModel(manager)

        # Transit callback: service time at origin + travel time to destination in minutes
        def time_evaluator(from_index: int, to_index: int) -> int:
            from_node = manager.IndexToNode(from_index)
            to_node = manager.IndexToNode(to_index)
            return service_times[from_node] + travel_times[from_node][to_node]

        transit_callback_index = routing.RegisterTransitCallback(time_evaluator)
        routing.SetArcCostEvaluatorOfAllVehicles(transit_callback_index)

        routing.AddDimension(
            transit_callback_index, 1440, max_day_capacity, False, "Time"
        )
        time_dimension = routing.GetDimensionOrDie("Time")
        solver = routing.solver()
        conflicts: list[str] = []
        for v, (start, end) in enumerate(windows):
            time_dimension.CumulVar(routing.Start(v)).SetRange(start, end)
            time_dimension.CumulVar(routing.End(v)).SetRange(start, end)
            # Penalize heavy utilization relative to this day's capacity, not POI count.
            capacity = end - start
            time_dimension.SetSoftSpanUpperBoundForVehicle(
                pywrapcp.BoundCost(int(capacity * 0.75), max(1, round(600 / capacity))),
                v,
            )
            routing.SetFixedCostOfVehicle(100, v)
            routing.AddVariableMinimizedByFinalizer(
                time_dimension.CumulVar(routing.Start(v))
            )
            routing.AddVariableMinimizedByFinalizer(
                time_dimension.CumulVar(routing.End(v))
            )

        reasons = {}
        verified = {}
        for i, (place, saved) in enumerate(zip(places, saved_rows)):
            idx = manager.NodeToIndex(i + 1)
            duration = service_times[i + 1]
            ranges = []
            allowed = []
            statuses = []
            for v, day in enumerate(active_days):
                if (
                    saved.assignment_mode == "LOCKED"
                    and saved.assigned_day_id != day.id
                ):
                    continue
                start, end = windows[v]
                offset = v * 1440
                row = weekly_hours.get(place.id, {}).get(day.date.weekday())
                legacy = opening_hours.get(place.id)
                if row is not None:
                    status = row.status
                    intervals = row.intervals
                elif legacy is not None:
                    status = (
                        "CLOSED"
                        if day.date.weekday() in legacy.closed_days
                        else "KNOWN"
                    )
                    intervals = [
                        {
                            "open": legacy.open_time.strftime("%H:%M"),
                            "close": legacy.close_time.strftime("%H:%M"),
                        }
                    ]
                else:
                    status = (
                        "CLOSED"
                        if place.opening_hours_status == "CLOSED"
                        else "UNKNOWN"
                    )
                    intervals = []
                statuses.append(status)
                verified[i, v] = status == "KNOWN"
                if status == "UNKNOWN":
                    candidates = [(start, end - duration)]
                elif status == "CLOSED":
                    candidates = []
                else:

                    def parse(value):
                        h, m = map(int, value.split(":"))
                        return h * 60 + m

                    candidates = [
                        (
                            max(start, offset + parse(t["open"])),
                            min(end, offset + parse(t["close"])) - duration,
                        )
                        for t in intervals
                    ]
                valid = [(a, b) for a, b in candidates if a <= b]
                if valid:
                    allowed.append(v)
                    ranges.extend(valid)
            if not allowed:
                routing.ActiveVar(idx).SetValue(0)
                reasons[i] = (
                    "LOCKED_DAY_INFEASIBLE"
                    if saved.assignment_mode == "LOCKED"
                    else "CLOSED_ON_AVAILABLE_DAYS"
                    if statuses and all(s == "CLOSED" for s in statuses)
                    else "NO_FEASIBLE_DAY"
                )
            else:
                # Native vehicle-domain restriction; retain -1 for optional drops.
                # Avoid the broken absl::Span binding in OR-Tools 9.15 Windows.
                for v in range(num_vehicles):
                    if v not in allowed:
                        routing.VehicleVar(idx).RemoveValue(v)
                # Exact union of valid start ranges, preserving every closed gap.
                merged = []
                for a, b in sorted(ranges):
                    if merged and a <= merged[-1][1] + 1:
                        merged[-1] = (merged[-1][0], max(b, merged[-1][1]))
                    else:
                        merged.append((a, b))
                cumul = time_dimension.CumulVar(idx)
                cumul.SetRange(merged[0][0], merged[-1][1])
                for left, right in pairwise(merged):
                    cumul.RemoveInterval(left[1] + 1, right[0] - 1)
                routing.AddVariableMinimizedByFinalizer(cumul)
            penalty = (
                100_000_000
                if saved.must_visit
                else 50_000 + int(saved.priority) * 10_000
            )
            if saved.assignment_mode == "LOCKED" or saved.is_locked:
                penalty += 1_000_000_000
            routing.AddDisjunction([idx], penalty)

        # Preserve the legacy first-position lock, but make it conditional on being
        # scheduled. An explicit day assignment takes precedence over this old flag.
        legacy_locks = {}
        for i, saved in enumerate(saved_rows):
            if saved.is_locked and saved.assignment_mode != "LOCKED":
                if (
                    saved.custom_order is None
                    or not 1 <= saved.custom_order <= num_places
                ):
                    raise ValueError(
                        "A locked place has an invalid custom_order position."
                    )
                if saved.custom_order in legacy_locks:
                    raise ValueError(
                        "Two locked places cannot use the same custom_order position."
                    )
                legacy_locks[saved.custom_order] = i
                idx = manager.NodeToIndex(i + 1)
                if saved.custom_order == 1:
                    solver.Add(
                        solver.IsEqualCstVar(routing.NextVar(routing.Start(0)), idx)
                        >= routing.ActiveVar(idx)
                    )
        for (_, a), (_, b) in zip(
            sorted(legacy_locks.items()), sorted(legacy_locks.items())[1:]
        ):
            ia, ib = manager.NodeToIndex(a + 1), manager.NodeToIndex(b + 1)
            solver.Add(
                time_dimension.CumulVar(ia)
                <= time_dimension.CumulVar(ib)
                + (2 - routing.ActiveVar(ia) - routing.ActiveVar(ib)) * max_day_capacity
            )

        # Breaks only on windows which cover a full midday lunch. Origin service
        # times prevent a break from overlapping an attraction visit.
        lunch_intervals = {}
        node_visits = [
            service_times[manager.IndexToNode(i)] for i in range(routing.Size())
        ]
        if self.lunch_duration_minutes > 0:
            for v, (start, end) in enumerate(windows):
                earliest = max(start, v * 1440 + lunch_earliest_min)
                latest = min(
                    end - self.lunch_duration_minutes, v * 1440 + lunch_latest_min
                )
                if earliest <= latest:
                    interval = solver.FixedDurationIntervalVar(
                        earliest,
                        latest,
                        self.lunch_duration_minutes,
                        False,
                        f"lunch_{v}",
                    )
                    lunch_intervals[v] = interval
                    time_dimension.SetBreakIntervalsOfVehicle(
                        [interval], v, node_visits
                    )

        # Solve with guided local search
        search_parameters = pywrapcp.DefaultRoutingSearchParameters()
        search_parameters.first_solution_strategy = (
            routing_enums_pb2.FirstSolutionStrategy.PATH_CHEAPEST_ARC
        )
        search_parameters.local_search_metaheuristic = (
            routing_enums_pb2.LocalSearchMetaheuristic.GUIDED_LOCAL_SEARCH
        )
        search_parameters.time_limit.FromMilliseconds(
            max(1, int(self.time_limit_seconds * 1000))
        )

        solution = routing.SolveWithParameters(search_parameters)

        if solution is None:
            dropped = [
                unscheduled(
                    i,
                    reasons.get(
                        i,
                        "LOCKED_DAY_INFEASIBLE"
                        if saved_rows[i].assignment_mode == "LOCKED"
                        else "NO_FEASIBLE_DAY",
                    ),
                )
                for i in range(num_places)
            ]
            return VrptwSolution(
                [],
                [],
                ["No feasible solution found within the solver limit."],
                0,
                0,
                [p.id for p in places],
                dropped,
            )

        # Decode solution
        scheduled_places: list[OptimizedPlaceRead] = []
        breaks: list[ItineraryBreakRead] = []
        unvisited_ids: list[UUID] = []
        dropped = []
        total_distance = 0
        total_travel_minutes = 0

        # Check dropped places
        for i in range(num_places):
            node_idx = i + 1
            routing_idx = manager.NodeToIndex(node_idx)
            if solution.Value(routing.NextVar(routing_idx)) == routing_idx:
                unvisited_ids.append(places[i].id)
                saved = saved_rows[i]
                dropped.append(
                    unscheduled(
                        i,
                        reasons.get(
                            i,
                            "LOCKED_DAY_INFEASIBLE"
                            if saved.assignment_mode == "LOCKED"
                            else "DAILY_CAPACITY_EXCEEDED",
                        ),
                    )
                )
                conflicts.append(
                    f"'{places[i].name}' cannot fit within available trip days."
                )

        for v in range(num_vehicles):
            day_number = active_days[v].day_number
            visit_order = 0
            index = routing.Start(v)
            prev_node = manager.IndexToNode(index)

            # Record lunch break for this day if vehicle performed visits
            has_visits = False
            while not routing.IsEnd(index):
                node = manager.IndexToNode(index)
                if node > 0:
                    has_visits = True
                    visit_order += 1
                    place_idx = node - 1
                    place = places[place_idx]

                    arrival_min = (
                        solution.Value(time_dimension.CumulVar(index)) - v * 1440
                    )
                    dur = service_times[node]
                    departure_min = arrival_min + dur

                    arr_time = time(hour=arrival_min // 60, minute=arrival_min % 60)
                    dep_time = time(hour=departure_min // 60, minute=departure_min % 60)

                    leg_dist = distances[prev_node][node]
                    leg_dur = travel_times[prev_node][node]

                    total_distance += leg_dist
                    total_travel_minutes += leg_dur

                    scheduled_places.append(
                        OptimizedPlaceRead(
                            place_id=place.id,
                            name=place.name,
                            day_number=day_number,
                            visit_order=visit_order,
                            distance_from_previous=round(leg_dist / 1000, 3),
                            travel_time_minutes=leg_dur,
                            planned_arrival_time=arr_time,
                            planned_departure_time=dep_time,
                            visit_duration_minutes=dur,
                            is_opening_hours_known=verified[place_idx, v],
                        )
                    )
                    prev_node = node
                index = solution.Value(routing.NextVar(index))

            if has_visits and v in lunch_intervals:
                # Add lunch break
                lunch_var = lunch_intervals[v]
                l_start = solution.StartValue(lunch_var) - v * 1440
                l_end = solution.EndValue(lunch_var) - v * 1440
                breaks.append(
                    ItineraryBreakRead(
                        day_number=day_number,
                        start_time=time(hour=l_start // 60, minute=l_start % 60),
                        end_time=time(hour=l_end // 60, minute=l_end % 60),
                        duration_minutes=l_end - l_start,
                        label="Midday Break / Lunch",
                    )
                )

        return VrptwSolution(
            optimized_places=scheduled_places,
            breaks=breaks,
            conflicts=conflicts,
            total_distance_meters=total_distance,
            total_travel_minutes=total_travel_minutes,
            unvisited_place_ids=unvisited_ids,
            unscheduled_places=dropped,
        )
