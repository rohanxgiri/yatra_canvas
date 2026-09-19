# YatraCanvas itinerary balancing audit

Last verified against repository: 2026-09-19

Status: `[IMPLEMENTED]` for planner behavior and repository tests. Exact global optimality remains
`[UNKNOWN]`, as expected for the bounded OR-Tools search.

## Root cause

The original VRPTW objective minimized travel and charged a fixed cost for activating each day
vehicle. It had no utilization reward for an otherwise feasible active day. Packing POIs into fewer
days was therefore cheaper than using all available days. The weak per-day 75%-capacity soft bound
did not repair that incentive.

The database did not convert these days to `REST`: their `TripDay.day_type` remained `FULL_DAY`,
`HALF_DAY`, or `TRAVEL`. The planner returned no stops for them, and the earlier generic empty-day
presentation made them feel like implicit rest days.

ADR-019's first correction removed the activation cost and introduced visit-count balancing. That
fixed equal-duration fixtures but was `[PARTIAL]` for this audit because it did not account for
service/travel load, did not perform a constraint-checked repair pass, and lacked decision logging.

## Fix

`[IMPLEMENTED]` The solver now combines:

- the existing hard day windows, opening intervals, visit durations, routing, REST exclusion, and
  assignment locks;
- a `DayLoad` dimension containing service plus travel minutes normalized by each day's usable
  duration;
- a secondary `VisitCount` span signal and strong soft preference against avoidable empty routes;
- a bounded empty/under-filled repair pass that prefers feasible unscheduled POIs, then movable
  unlocked POIs from overloaded nearby days;
- a fresh full constraint solve for proposed moves. Temporary repair locks are never persisted, and
  a result is accepted only if it schedules at least as many POIs and reduces the capacity-weighted
  deficit.

No POI is invented or duplicated. Opening hours, route feasibility, user REST days, explicit day
assignments, `is_locked` POIs, and unscheduled output remain authoritative.

## Day states

| State | Result |
| --- | --- |
| User rest | PASS — only persisted `day_type=REST`; never receives a route or repair candidate |
| Planner empty | PASS — remains an active day and is repaired when a safe redistribution exists |
| Light/free day | PASS — insufficient-place/constraint emptiness is shown as flexible time, not rest |
| Normal day | PASS — one or more scheduled stops within its usable window |
| No feasible POI | PASS — remains empty with a debug reason and explicit unscheduled rows where applicable |

No new enum or migration was needed. Existing `TripDay.day_type`, route contents, and feasibility
metadata distinguish the states cleanly.

## Measured deterministic balancing

These measurements use equal 60-minute park visits and deterministic matrices unless stated:

| Scenario | Scheduled distribution | Unscheduled | Result |
| --- | --- | --- | --- |
| 15 POIs / 5 days | `3, 3, 3, 3, 3` | 0 | PASS |
| 20 POIs / 5 days | `5, 3, 3, 4, 5` | 0 | PASS — reasonable, not forced equality |
| 10 POIs / 5 days | `2, 2, 2, 2, 2` | 0 | PASS |
| 5 POIs / 5 days | `1, 1, 1, 1, 1` | 0 | PASS |
| 2 POIs / 5 days | two distinct one-stop days; three flexible days | 0 | PASS |
| 15 POIs / 3 days | `5, 5, 5` | 0 | PASS |
| 20 museums / 2 days | `4, 4` | 12 | PASS — overflow explicitly reported |

## Constraint matrix

- Opening hours: PASS — normal, split, closed, closes-before-completion, late-opening, unknown, and
  weekday-specific intervals.
- Arrival afternoon: PASS — shortened capacity receives proportionally less work.
- Departure morning: PASS — shortened capacity receives proportionally less work.
- One and two user REST days: PASS.
- Explicit day assignment and locked POI retention: PASS.
- Overloaded plus empty day: PASS.
- Clustered places: PASS — balanced without unnecessary route penalty.
- Geographically distant place: PASS — isolated on its own route when mixing would be infeasible;
  count equality does not override route quality.
- Missed-POI carry-over/partial replanning: PASS — existing affected-day-only behavior is unchanged.
- Duplicate scheduled POIs: 0 in all planner matrix cases.
- Invented POIs: 0.
- Unscheduled handling: PASS — scheduled and unscheduled sets are disjoint and exhaustive.

## Debug output

Debug-level records now include:

```text
ITINERARY_DAY date=... day=... available_minutes=... scheduled_minutes=...
travel_minutes=... place_count=... user_rest=... locked=...
unscheduled_candidates=... empty_reason=...
```

Empty reasons distinguish `USER_REST`, `NO_USABLE_DAY_WINDOW`, `DAY_LOCKED`,
`NO_FEASIBLE_OPEN_POI`, `INSUFFICIENT_PLACES`, `TIME_WINDOW_OR_TRAVEL_CONSTRAINT`, and
`NO_GLOBALLY_FEASIBLE_REDISTRIBUTION`. Repair proposals and acceptance/skips are also debug-only.

## UI verification

`[IMPLEMENTED]` No UI redesign was required. Existing Flutter itinerary and map views already show:

- `Rest day · Take it slow` only for persisted REST days;
- `Light day · Flexible time` / `Flexible time. This is not a rest day.` for empty active days;
- normal stop counts and schedules for populated days.

Images remain compact and schedule readability is unchanged.

## Test results

- Planner matrix: 27 passed, 0 failed.
- Partial replanning plus route optimization: 32 passed, 0 failed.
- Flutter itinerary/map/POI presentation: 58 passed, 0 failed.
- Ruff check and format verification: passed.
- Full backend: 431 passed, 1 failed, 5 setup errors in the first run. The five importer setup
  errors were caused by denied access to the default Windows pytest temp root; rerunning that file
  with a writable temp root passed 9/9. The remaining failure is the pre-existing Discover Places
  fake-provider call-count expectation (`tests/test_routes.py` expects one call/category but the
  implemented deepening flow makes two). It reproduces alone and was intentionally not changed by
  this itinerary-only task.

## Files changed

- `backend/app/services/vrptw_solver_service.py` — normalized load objective, bounded repair, and
  debug decision records.
- `backend/tests/test_day_aware_planner.py` — deterministic balancing, state, routing, capacity,
  overflow, and diagnostics matrix.
- `docs/PROJECT_CONTEXT.md`, `docs/ARCHITECTURE.md`, `docs/ROADMAP.md`, `docs/DECISIONS.md`, and
  `docs/PLANNER_IMPLEMENTATION.md` — update source-of-truth planner behavior.
- `docs/ITINERARY_BALANCING_AUDIT.md` — this audit and verification record.

## Remaining issues

- The bounded heuristic does not prove global optimality. Hard constraints can legitimately leave a
  non-REST day empty.
- Repair can add up to three two-second attempts after the primary solve in pathological imbalance
  cases; production timing should be observed before increasing this budget.
- The existing zero-cost synthetic return-to-hotel leg remains unchanged.
- A whole-day lock flag does not exist in the current model. Current lock guarantees are explicit
  POI-to-day assignments plus user REST/window constraints.
- The unrelated Discover Places call-count test remains red and is outside this task's authorized
  scope.
