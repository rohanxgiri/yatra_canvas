"""Google OR-Tools VRPTW (Vehicle Routing Problem with Time Windows) solver.

Solves multi-day tourist itineraries with:
- Opening hours (time windows on nodes & day-of-week closures)
- Visit durations (service time per category)
- Multiple days (vehicles = days, daily start & end touring hours)
- Lunch breaks (break intervals in midday window)
- Locked places (pinned positions / relative ordering)
- Priorities & must-visit rules (disjunction penalties & precedence)
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta
from math import ceil
from typing import Final
from uuid import UUID

from ortools.constraint_solver import routing_enums_pb2, pywrapcp

from app.core.itinerary_constants import (
    DEFAULT_DAY_END_TIME,
    DEFAULT_DAY_START_TIME,
    DEFAULT_LUNCH_BREAK_MINUTES,
    LUNCH_BREAK_EARLIEST_START,
    LUNCH_BREAK_LATEST_START,
    MIN_TRAVEL_BUFFER_MINUTES,
    estimate_visit_duration,
)
from app.models.entities import Place, UserSavedPlace
from app.schemas.route_optimization import ItineraryBreakRead, OptimizedPlaceRead
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


class VrptwSolverService:
    """Multi-day VRPTW solver engine backed by Google OR-Tools."""

    def __init__(
        self,
        day_start_time: time = DEFAULT_DAY_START_TIME,
        day_end_time: time = DEFAULT_DAY_END_TIME,
        lunch_earliest_start: time = LUNCH_BREAK_EARLIEST_START,
        lunch_latest_start: time = LUNCH_BREAK_LATEST_START,
        lunch_duration_minutes: int = DEFAULT_LUNCH_BREAK_MINUTES,
        time_limit_seconds: float = 3.0,
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
        base_date = start_date or date.today()
        num_vehicles = max(1, trip_days)
        num_locations = num_places + 1  # 0 is depot (start_node), 1..N are places

        # Validate locked place slots
        locked_slots: dict[int, int] = {}
        for index, saved in enumerate(saved_rows):
            if not saved.is_locked:
                continue
            if saved.custom_order is None:
                raise ValueError("Locked places require a custom_order position.")
            slot = saved.custom_order - 1
            if slot < 0 or slot >= num_places:
                raise ValueError("A locked place has an invalid custom_order position.")
            if slot in locked_slots:
                raise ValueError("Two locked places cannot use the same custom_order position.")
            locked_slots[slot] = index

        # Convert times to minutes from midnight
        day_start_min = self.day_start_time.hour * 60 + self.day_start_time.minute
        day_end_min = self.day_end_time.hour * 60 + self.day_end_time.minute
        lunch_earliest_min = self.lunch_earliest_start.hour * 60 + self.lunch_earliest_start.minute
        lunch_latest_min = self.lunch_latest_start.hour * 60 + self.lunch_latest_start.minute

        # Build distance and travel time lookup tables
        travel_times: list[list[int]] = [[0] * num_locations for _ in range(num_locations)]
        travel_seconds: list[list[int]] = [[0] * num_locations for _ in range(num_locations)]
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
                    raise ValueError(f"No routing leg available between locations.")
                dur = max(1, ceil(leg.preferred_duration_seconds / 60))
                travel_times[i][j] = dur
                travel_seconds[i][j] = leg.preferred_duration_seconds
                distances[i][j] = leg.distance_meters

        # Create OR-Tools routing model
        starts = [0] * num_vehicles
        ends = [0] * num_vehicles
        manager = pywrapcp.RoutingIndexManager(num_locations, num_vehicles, starts, ends)
        routing = pywrapcp.RoutingModel(manager)

        # Transit callback: service time at origin + travel time to destination in minutes
        def time_evaluator(from_index: int, to_index: int) -> int:
            from_node = manager.IndexToNode(from_index)
            to_node = manager.IndexToNode(to_index)
            return service_times[from_node] + travel_times[from_node][to_node]

        transit_callback_index = routing.RegisterTransitCallback(time_evaluator)
        routing.SetArcCostEvaluatorOfAllVehicles(transit_callback_index)

        # Distance callback for secondary metrics
        def distance_evaluator(from_index: int, to_index: int) -> int:
            from_node = manager.IndexToNode(from_index)
            to_node = manager.IndexToNode(to_index)
            return distances[from_node][to_node]

        # Time Dimension: allows slack for waiting (e.g. before opening hours / lunch)
        max_slack = 12 * 60  # 720 minutes slack max
        max_day_capacity = 24 * 60  # 1440 minutes max
        time_dimension_name = "Time"
        routing.AddDimension(
            transit_callback_index,
            max_slack,
            max_day_capacity,
            False,
            time_dimension_name,
        )
        time_dimension = routing.GetDimensionOrDie(time_dimension_name)

        # Configure vehicle start/end time windows (daily touring budget)
        for v in range(num_vehicles):
            time_dimension.CumulVar(routing.Start(v)).SetRange(day_start_min, day_end_min)
            time_dimension.CumulVar(routing.End(v)).SetRange(day_start_min, day_end_min)

        solver = routing.solver()
        conflicts: list[str] = []

        # Opening hours & closed-day constraints
        for i in range(num_places):
            node_idx = i + 1
            place = places[i]
            visit_dur = service_times[node_idx]
            routing_idx = manager.NodeToIndex(node_idx)
            hours = opening_hours.get(place.id)

            if hours is not None:
                open_m = hours.open_time.hour * 60 + hours.open_time.minute
                close_m = hours.close_time.hour * 60 + hours.close_time.minute
                earliest_arrival = max(day_start_min, open_m)
                latest_arrival = min(day_end_min, close_m - visit_dur)

                if earliest_arrival <= latest_arrival:
                    time_dimension.CumulVar(routing_idx).SetRange(earliest_arrival, latest_arrival)
                else:
                    conflicts.append(
                        f"'{place.name}' opening hours ({hours.open_time.strftime('%I:%M %p')}–"
                        f"{hours.close_time.strftime('%I:%M %p')}) conflict with daily touring hours."
                    )

                # Day-of-week closure check across vehicles
                for v in range(num_vehicles):
                    day_date = base_date + timedelta(days=v)
                    if day_date.weekday() in hours.closed_days:
                        routing.VehicleVar(routing_idx).RemoveValue(v)
            else:
                # Default daily touring hours
                latest_arrival = day_end_min - visit_dur
                if day_start_min <= latest_arrival:
                    time_dimension.CumulVar(routing_idx).SetRange(day_start_min, latest_arrival)

        # Lunch break intervals for each vehicle
        lunch_intervals: list[pywrapcp.IntervalVar] = []
        for v in range(num_vehicles):
            lunch_var = solver.FixedDurationIntervalVar(
                lunch_earliest_min,
                lunch_latest_min + self.lunch_duration_minutes,
                self.lunch_duration_minutes,
                False,
                f"lunch_day_{v + 1}",
            )
            lunch_intervals.append(lunch_var)
            time_dimension.SetBreakIntervalsOfVehicle(
                [lunch_var], v, [0] * num_locations
            )

        # Locked place constraints
        for slot, place_index in locked_slots.items():
            node_idx = place_index + 1
            routing_idx = manager.NodeToIndex(node_idx)
            if slot == 0:
                # Fixed as the first stop on Day 1
                solver.Add(routing.NextVar(routing.Start(0)) == routing_idx)

        # If multiple locked places have defined custom orders, enforce relative ordering
        sorted_locked = sorted(locked_slots.items())
        for k in range(len(sorted_locked) - 1):
            slot_a, idx_a = sorted_locked[k]
            slot_b, idx_b = sorted_locked[k + 1]
            idx_a_routing = manager.NodeToIndex(idx_a + 1)
            idx_b_routing = manager.NodeToIndex(idx_b + 1)
            both_locked_active = routing.ActiveVar(idx_a_routing) * routing.ActiveVar(idx_b_routing)
            solver.Add(
                time_dimension.CumulVar(idx_a_routing) - time_dimension.CumulVar(idx_b_routing)
                <= (1 - both_locked_active) * max_day_capacity
            )

        # Priority & Must-Visit Rules using Disjunctions
        for i in range(num_places):
            node_idx = i + 1
            routing_idx = manager.NodeToIndex(node_idx)
            saved = saved_rows[i]
            if saved.must_visit:
                # Prohibitively large penalty ensures must-visit places are dropped only if impossible
                routing.AddDisjunction([routing_idx], 100_000_000)
            else:
                # Scaled penalty ensures higher priority places are retained over lower priority places
                drop_penalty = 50_000 + int(saved.priority) * 10_000
                routing.AddDisjunction([routing_idx], drop_penalty)

        # Priority precedence: when place A has strictly higher priority than place B and neither is locked,
        # incentivize or constrain visiting higher priority earlier on the same day if time windows permit
        for i in range(num_places):
            for j in range(num_places):
                if i == j:
                    continue
                saved_a = saved_rows[i]
                saved_b = saved_rows[j]
                if saved_a.priority > saved_b.priority and not saved_a.is_locked and not saved_b.is_locked:
                    hours_a = opening_hours.get(places[i].id)
                    hours_b = opening_hours.get(places[j].id)
                    # Only add precedence if opening hours don't conflict with A before B
                    can_precede = True
                    if hours_a and hours_b:
                        open_a = hours_a.open_time.hour * 60 + hours_a.open_time.minute
                        close_b = hours_b.close_time.hour * 60 + hours_b.close_time.minute
                        if open_a + service_times[i + 1] > close_b:
                            can_precede = False
                    if can_precede:
                        idx_a_routing = manager.NodeToIndex(i + 1)
                        idx_b_routing = manager.NodeToIndex(j + 1)
                        both_active = routing.ActiveVar(idx_a_routing) * routing.ActiveVar(idx_b_routing)
                        solver.Add(
                            routing.VehicleVar(idx_a_routing) - routing.VehicleVar(idx_b_routing)
                            <= (1 - both_active) * num_vehicles
                        )
                        solver.Add(
                            (time_dimension.CumulVar(idx_a_routing) - time_dimension.CumulVar(idx_b_routing))
                            <= (1 - both_active) * max_day_capacity
                            + (routing.VehicleVar(idx_b_routing) - routing.VehicleVar(idx_a_routing)) * max_day_capacity
                        )

        # Solve with guided local search
        search_parameters = pywrapcp.DefaultRoutingSearchParameters()
        search_parameters.first_solution_strategy = (
            routing_enums_pb2.FirstSolutionStrategy.PATH_CHEAPEST_ARC
        )
        search_parameters.local_search_metaheuristic = (
            routing_enums_pb2.LocalSearchMetaheuristic.GUIDED_LOCAL_SEARCH
        )
        search_parameters.time_limit.seconds = int(ceil(self.time_limit_seconds))

        solution = routing.SolveWithParameters(search_parameters)

        if solution is None:
            # Check if locked place conflict exists
            if len(locked_slots) > 1:
                raise ValueError("Locked place positions conflict.")
            raise ValueError("The route constraints could not connect every selected place.")

        # Decode solution
        scheduled_places: list[OptimizedPlaceRead] = []
        breaks: list[ItineraryBreakRead] = []
        unvisited_ids: list[UUID] = []
        total_distance = 0
        total_travel_minutes = 0

        # Check dropped places
        for i in range(num_places):
            node_idx = i + 1
            routing_idx = manager.NodeToIndex(node_idx)
            if solution.Value(routing.NextVar(routing_idx)) == routing_idx:
                unvisited_ids.append(places[i].id)
                saved = saved_rows[i]
                if saved.must_visit:
                    raise ValueError("Cannot fit all must-visit places within the trip duration.")
                conflicts.append(f"'{places[i].name}' cannot fit within available trip days.")

        for v in range(num_vehicles):
            day_number = v + 1
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
                    hours = opening_hours.get(place.id)

                    arrival_min = solution.Min(time_dimension.CumulVar(index))
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
                            is_opening_hours_known=hours is not None,
                        )
                    )
                    prev_node = node
                index = solution.Value(routing.NextVar(index))

            if has_visits:
                # Add lunch break
                lunch_var = lunch_intervals[v]
                l_start = solution.StartValue(lunch_var)
                l_end = solution.EndValue(lunch_var)
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
        )
