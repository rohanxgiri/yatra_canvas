"""Constraint regressions use actual TripDays and persisted-format weekday rows."""

from datetime import date, time, timedelta
from time import perf_counter
from uuid import uuid4

import pytest

from app.models.entities import Place, PlaceOpeningHours, TripDay, UserSavedPlace
from app.services.google_routes_service import RouteMatrixLeg
from app.services.route_matrix_service import RouteNode
from app.services.vrptw_solver_service import VrptwSolverService


def day(n, kind="FULL_DAY", start=time(9), end=time(19)):
    return TripDay(
        trip_id=uuid4(),
        day_number=n,
        date=date(2026, 9, 7) + timedelta(days=n - 1),
        day_type=kind,
        start_time=start,
        end_time=end,
    )


def fixture(categories):
    places = [
        Place(
            city_id=uuid4(),
            name=f"Place {i + 1}",
            category=c,
            latitude=20 + i * 0.01,
            longitude=75,
        )
        for i, c in enumerate(categories)
    ]
    saved = [UserSavedPlace(trip_id=uuid4(), place_id=p.id) for p in places]
    return places, saved


def solve(days, places, saved, weekly=None, seconds=0.15, lunch=0, travel=10):
    start = RouteNode("start", "hotel", "Hotel", 20, 75)
    nodes = [RouteNode.for_place(p) for p in places]
    matrix = {
        (a.key, b.key): RouteMatrixLeg(
            distance_meters=1000, static_duration_seconds=travel * 60
        )
        for a in [start, *nodes]
        for b in nodes
        if a.key != b.key
    }
    return VrptwSolverService(
        time_limit_seconds=seconds, lunch_duration_minutes=lunch
    ).solve(
        start,
        nodes,
        places,
        saved,
        matrix,
        len(days),
        day_configs=days,
        weekly_hours_map=weekly,
    )


def hours(p, weekday, status="KNOWN", intervals=None):
    return PlaceOpeningHours(
        place_id=p.id, day_of_week=weekday, status=status, intervals=intervals or []
    )


def check(result, days, places):
    scheduled = {s.place_id for s in result.optimized_places}
    dropped = {s.place_id for s in result.unscheduled_places}
    assert not scheduled & dropped
    assert scheduled | dropped == {p.id for p in places}
    assert len(scheduled) == len(result.optimized_places)
    for d in days:
        stops = [s for s in result.optimized_places if s.day_number == d.day_number]
        if d.day_type == "REST" or not d.start_time or not d.end_time:
            assert not stops
        for i, s in enumerate(stops):
            assert (
                d.start_time
                <= s.planned_arrival_time
                < s.planned_departure_time
                <= d.end_time
            )
            assert s.visit_order == i + 1

            def minutes(t):
                return t.hour * 60 + t.minute

            previous = stops[i - 1].planned_departure_time if i else d.start_time
            assert (
                minutes(s.planned_arrival_time)
                >= minutes(previous) + s.travel_time_minutes
            )
        for b in (b for b in result.breaks if b.day_number == d.day_number):
            assert d.start_time <= b.start_time < b.end_time <= d.end_time
            assert all(
                s.planned_departure_time <= b.start_time
                or s.planned_arrival_time >= b.end_time
                for s in stops
            )


def test_sparse_real_numbers_and_all_day_types():
    days = [
        day(1),
        day(2, "REST"),
        day(3),
        day(4, "HALF_DAY", time(9), time(11)),
        day(5, "TRAVEL", None, None),
        day(6, "TRAVEL", time(16), time(18)),
    ]
    p, s = fixture(["park"] * 4)
    for row, d in zip(s, [days[0], days[2], days[3], days[5]]):
        row.assignment_mode, row.assigned_day_id = "LOCKED", d.id
    result = solve(days, p, s)
    assert {x.day_number for x in result.optimized_places} == {1, 3, 4, 6}
    check(result, days, p)


@pytest.mark.parametrize("locked", [False, True])
def test_closed_weekday_moves_auto_but_never_locked(locked):
    days = [day(1), day(3)]
    p, s = fixture(["museum"])
    if locked:
        s[0].assignment_mode, s[0].assigned_day_id = "LOCKED", days[0].id
    weekly = {
        p[0].id: {
            0: hours(p[0], 0, "CLOSED"),
            2: hours(p[0], 2, intervals=[{"open": "14:00", "close": "17:00"}]),
        }
    }
    r = solve(days, p, s, weekly)
    if locked:
        assert r.unscheduled_places[0].reason == "LOCKED_DAY_INFEASIBLE"
    else:
        assert r.optimized_places[0].day_number == 3
        assert r.optimized_places[0].planned_arrival_time >= time(14)
    check(r, days, p)


@pytest.mark.parametrize(
    "start,end,scheduled",
    [
        (time(12), time(13), False),
        (time(12), time(16), True),
        (time(9), time(11), True),
    ],
)
def test_split_hours_and_visit_completion(start, end, scheduled):
    days = [day(1, start=start, end=end)]
    p, s = fixture(["park"])
    w = {
        p[0].id: {
            0: hours(
                p[0],
                0,
                intervals=[
                    {"open": "09:00", "close": "11:00"},
                    {"open": "14:00", "close": "22:00"},
                ],
            )
        }
    }
    r = solve(days, p, s, w)
    assert bool(r.optimized_places) == scheduled
    for stop in r.optimized_places:
        assert stop.planned_arrival_time <= time(
            10
        ) or stop.planned_arrival_time >= time(14)
        assert stop.is_opening_hours_known
    check(r, days, p)


def test_closing_duration_closed_and_unknown_are_distinct():
    days = [day(1, start=time(16), end=time(19))]
    p, s = fixture(["museum"] * 4)
    w = {
        p[0].id: {0: hours(p[0], 0, intervals=[{"open": "09:00", "close": "17:00"}])},
        p[1].id: {0: hours(p[1], 0, "CLOSED")},
        p[2].id: {0: hours(p[2], 0, "UNKNOWN")},
    }
    r = solve(days, p, s, w)
    reasons = {x.place_id: x.reason for x in r.unscheduled_places}
    assert reasons[p[0].id] == "NO_FEASIBLE_DAY"
    assert reasons[p[1].id] == "CLOSED_ON_AVAILABLE_DAYS"
    assert r.optimized_places and all(
        not x.is_opening_hours_known for x in r.optimized_places
    )
    check(r, days, p)


def test_no_active_routes_and_impossible_lock():
    days = [day(1, "REST"), day(2, "TRAVEL", None, None)]
    p, s = fixture(["park"] * 2)
    s[1].assignment_mode, s[1].assigned_day_id = "LOCKED", days[1].id
    r = solve(days, p, s)
    assert [x.reason for x in r.unscheduled_places] == [
        "NO_TIME_AVAILABLE",
        "LOCKED_DAY_INFEASIBLE",
    ]
    check(r, days, p)


def test_underfilled_can_use_one_day():
    days = [day(i) for i in range(1, 6)]
    p, s = fixture(["park"] * 2)
    r = solve(days, p, s)
    assert len(r.optimized_places) == 2
    assert len({x.day_number for x in r.optimized_places}) == 1
    check(r, days, p)


def test_time_distribution_not_equal_counts():
    days = [day(1, end=time(15, 20)), day(2, "HALF_DAY", time(9), time(12))]
    p, s = fixture(["theme_park"] * 2 + ["bakery"] * 4)
    r = solve(days, p, s, seconds=0.4)
    assert len(r.optimized_places) == 6
    assert sorted(
        sum(x.day_number == d.day_number for x in r.optimized_places) for d in days
    ) == [2, 4]
    check(r, days, p)


def test_locked_preserved_over_auto_under_capacity():
    days = [day(1, end=time(11)), day(2, end=time(11))]
    p, s = fixture(["museum"] * 3)
    s[2].assignment_mode, s[2].assigned_day_id = "LOCKED", days[1].id
    r = solve(days, p, s)
    assert next(x for x in r.optimized_places if x.place_id == p[2].id).day_number == 2
    assert len(r.unscheduled_places) == 1
    check(r, days, p)


def test_weekday_specific_intervals_do_not_leak_to_another_route():
    days = [day(1, start=time(14), end=time(18)), day(3, start=time(9), end=time(12))]
    p, s = fixture(["park"])
    w = {p[0].id: {
        0: hours(p[0], 0, intervals=[{"open": "09:00", "close": "11:00"}]),
        2: hours(p[0], 2, intervals=[{"open": "14:00", "close": "18:00"}]),
    }}
    r = solve(days, p, s, w)
    assert not r.optimized_places
    assert r.unscheduled_places[0].reason == "NO_FEASIBLE_DAY"


def test_latest_start_and_midnight_boundary():
    days = [day(1, start=time(15, 20), end=time(17))]
    p, s = fixture(["museum"])
    w = {p[0].id: {0: hours(p[0], 0, intervals=[{"open": "00:00", "close": "17:00"}])}}
    r = solve(days, p, s, w)
    assert r.optimized_places[0].planned_arrival_time == time(15, 30)
    assert r.optimized_places[0].planned_departure_time == time(17)
    check(r, days, p)
    days[0].start_time, days[0].end_time = time(22), time(23, 59)
    w[p[0].id][0].intervals = [{"open": "00:00", "close": "24:00"}]
    r = solve(days, p, s, w)
    assert r.optimized_places[0].is_opening_hours_known
    check(r, days, p)


@pytest.mark.parametrize("count,total_days", [(15, 3), (20, 5), (30, 5)])
def test_realistic_sizes(count, total_days):
    days = [day(i) for i in range(1, total_days + 1)]
    p, s = fixture(
        (["museum", "heritage", "park", "religious", "theme_park"] * 6)[:count]
    )
    before = perf_counter()
    r = solve(days, p, s, seconds=5, lunch=60, travel=20)
    elapsed = perf_counter() - before
    print(
        f"BENCHMARK {total_days} days / {count} places: {elapsed:.3f}s, {len(r.optimized_places)} scheduled, {len(r.unscheduled_places)} unscheduled"
    )
    assert r.optimized_places
    if count == 30:
        assert r.unscheduled_places
    check(r, days, p)
