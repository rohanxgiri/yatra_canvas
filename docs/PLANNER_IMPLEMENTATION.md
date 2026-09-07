# Day-aware itinerary planner implementation

Review date: 2026-09-07. Status: `[IMPLEMENTED]` for this planner slice; unrelated repository test failures noted below.

## Previous behavior

The existing VRPTW solver used one vehicle per integer trip day, a global 09:00–19:00
window, optional manually supplied single opening windows, and weekday exclusions. It
already included travel plus category service time and disjunction penalties. The normal
endpoint did not load normalized opening-hour rows or TripDays. Legacy order locks and
hard priority precedence could interfere with feasibility. The endpoint required at least
one selection per day, capped selections at 24, and raised when a must-visit was dropped.
Dropped IDs were not exposed as structured API results.

## Implementation

- Actual TripDays map to active routes, retaining dates and real day numbers. REST never
  has a route, even if it retains times. FULL_DAY, HALF_DAY and TRAVEL use their configured
  start/end; null, reversed or empty windows are inactive.
- AUTO can use any feasible active day. LOCKED uses only the assigned TripDay ID through
  native vehicle-variable domains, leaving the optional dropped state available. Explicit
  day locks take precedence over the legacy position-lock flag; they never move silently.
- Existing `estimate_visit_duration` remains the sole duration model. The Time transit
  includes origin visit duration plus matrix travel time, including the initial depot leg.
- Persisted weekday opening schedules are loaded without provider calls. Each active route
  has a separate internal time coordinate band, allowing exact unions of opening intervals
  on one node per place. Invalid vehicles and closed gaps are excluded; latest start is
  closing time minus the entire visit duration. Overnight schedules already normalized by
  ingestion and `24:00` endpoints are supported within each same-day sightseeing window.
- UNKNOWN applies no venue restriction, but stops retain `is_opening_hours_known=false`.
  This existing API/Flutter flag is the verification representation; it never claims unknown
  venues are known-open. A missing weekday row remains unverified.
- Hard day and opening constraints always take precedence. Existing priority and must-visit
  retention penalties are reused, with a stronger lock penalty. Hard priority visit
  precedence was removed because it could make an otherwise feasible route impossible.
- Daily balancing uses a soft route-span penalty beyond 75% of each day's capacity, weighted
  inversely by capacity. Span includes travel, service and waiting within the route. A small
  route activation cost avoids forcing sparse trips across all days. There are no place-count
  quotas or hard equal-duration targets.
- Lunch is constrained to a complete midday interval inside that day's window, with service
  metadata preventing overlap with visits. No breaks are returned for empty routes.
- Overpacked trips return partial results, including dropped must-visits. Each selected
  place appears once in either scheduled or unscheduled output. Reasons distinguish no
  active time, all days closed, infeasible day locks, no individual feasible window and
  capacity drops. The latter is a solver outcome, not a proof of global infeasibility.
- Start/depot and matrix cache behavior are preserved: the existing final depot arc carries
  zero return time/cost. No return-to-hotel route requirement was introduced.
- Both optimization and full-trip replan preview share database input loading. Preview does
  not persist TripDays or itinerary rows. Apply continues through the existing optimizer.

## API and Flutter

`POST /trips/{trip_id}/optimize-route` and full-trip replan previews add:

```json
{
  "unscheduled_places": [
    {
      "place_id": "<selected place UUID>",
      "name": "Museum",
      "reason": "LOCKED_DAY_INFEASIBLE",
      "assigned_day_id": "<assigned TripDay UUID>"
    }
  ]
}
```

Reasons: `NO_TIME_AVAILABLE`, `CLOSED_ON_AVAILABLE_DAYS`, `LOCKED_DAY_INFEASIBLE`,
`DAILY_CAPACITY_EXCEEDED`, `NO_FEASIBLE_DAY`. Scheduled stops retain original day, order,
arrival/departure, travel/distance, category duration and `is_opening_hours_known`.
`total_days` retains empty logical days. The cap is 50, with no minimum selection count.

Flutter models parse optional unscheduled lists and assigned-day IDs for routes and replan
previews. Old responses default to empty lists. Existing unknown-hours booleans remain
false by default. The route button accepts one selected place. No new itinerary/map UI,
recommendation behavior, visit state, enrichment, or partial/live replanning was added.

## Files created for this phase

- `backend/app/services/planner_inputs.py`
- `backend/tests/test_day_aware_planner.py`
- `backend/tests/conftest.py` (isolates startup from configured databases)
- `test/day_aware_planner_test.dart`
- `docs/PLANNER_IMPLEMENTATION.md`
- `docs/PLANNER_EXAMPLE.md`

## Files modified for this phase

- `backend/app/services/vrptw_solver_service.py`
- `backend/app/services/route_optimization_service.py`
- `backend/app/services/smart_replanning_service.py`
- `backend/app/schemas/route_optimization.py`
- `backend/app/schemas/smart_replanning.py`
- `backend/tests/test_route_optimization.py`
- `backend/tests/test_smart_replanning.py`
- `backend/tests/test_routes.py` (expected existing normalized-hours API fields)
- `lib/models/optimized_route.dart`
- `lib/models/smart_replanning.dart`
- `lib/screens/place_discovery/place_discovery_screen.dart`
- `docs/ARCHITECTURE.md`, `docs/DATA_MODEL.md`, `docs/API_AND_DATA_SOURCES.md`
- `docs/DECISIONS.md`, `docs/PROJECT_CONTEXT.md`, `docs/ROADMAP.md`

Pre-existing uncommitted TripDay assignment/opening-hour ingestion work was preserved.
No database schema, migration, environment variable, dependency or provider change was added.

## Tests and performance

New solver regressions cover every day type, sparse numbering, day locks and AUTO movement,
closed weekdays/all-days, split gaps, latest start including service duration, UNKNOWN and
missing hours, weekday-domain isolation, midnight boundary, underfilled and overfilled trips,
relative daily capacity, retention and exact scheduled/unscheduled partitioning. Integration
coverage checks persisted input loading, full-trip preview parity, verification flags and
itinerary timing persistence. Flutter tests cover optional lists, reasons, day IDs, sparse
days and unknown-hours state. Existing matrix, TripDay, assignment, hours, VRPTW and timing
regressions are included in the backend suite.

The existing PATH_CHEAPEST_ARC / GUIDED_LOCAL_SEARCH strategies and five-second default
budget are retained. An alternate insertion strategy was tested and rejected after a mixed
long/short attraction regression. Test-specific subsecond limits now use milliseconds.

| Synthetic scenario | Solve time | Scheduled | Unscheduled |
| --- | --- | --- | --- |
| 3 days / 15 places | 5.005 s | 14 | 1 |
| 5 days / 20 places | 5.007 s | 20 | 0 |
| 5 days / 30 places | 5.010 s | 25 | 5 |

These offline fixtures use mixed 45–180-minute categories, 20-minute travel legs and lunch.
Times exclude database/network/geometry latency. OR-Tools 9.15.6755 on the local Windows
Python environment; bounded heuristic results, not globally optimal solutions or provider
benchmarks. The requested five-day/rest-day fixture took 5.012 s and returned 13 scheduled,
2 unscheduled: see [the complete timed output](PLANNER_EXAMPLE.md).

Backend full-suite result: 325 passed, four failures. Two documentation failures caused by
Windows text encoding were corrected and the three documentation checks passed on rerun,
leaving **327 passing tests and two importer failures** across that verification run.
All planner, route matrix, TripDay, assignment, opening-hours, VRPTW, itinerary timing and
smart-replanning tests passed, including the persisted-input integration and 16 day-aware
solver cases. The importer failures exposed an uncommitted model mismatch: `PlaceCategory`
had been renamed to `category_label`, while the established database, migration, and importer
use `label`. The database follow-up restored the compatible `label` model contract, and the
targeted importer/opening-hours/partial-replanning/documentation suite then passed.

Full command (from backend):
`python -m pytest tests -q -p no:cacheprovider --basetemp=<workspace test directory>`.
The final full run took 235.72 s. Fixtures isolate FastAPI startup to SQLite, preventing
configured remote databases from being contacted. A workspace temp directory avoids the
host user's inaccessible pytest temp directory. Core solver/input/schema Ruff checks pass.
Flutter: all 90 tests passed. Analysis: no errors; five existing info notices and three
existing test override warnings outside this phase. Git whitespace verification passed.

## Compatibility and remaining technical debt

- No migrations were applied. Existing prerequisite TripDay/assignment/hours migrations
  still need the project's normal reviewed deployment process where not already installed.
- Reasons and known-hours verification are response metadata, not durable generation
  snapshots; persisted itinerary rows retain timing/leg metrics and saved places remain.
- Existing staleness checking treats intentionally unscheduled selections as stale. General
  plan-version/staleness redesign and weather-specific rearrangement constraints are outside
  this phase; the existing full-trip optimizer/preview inputs are aligned.
- The legacy single-window `ItineraryTimingService` remains for its existing callers/tests;
  normal optimization uses VRPTW and the shared duration estimator.
- The legacy `is_locked` flag is not an exact global-slot contract for every position; its
  existing first-position/relative-order behavior remains. New day assignment is authoritative.
- Venue holiday exceptions, reliable last-entry data and overnight TripDay windows are not
  represented by the existing model. Missing data stays unverified.
- Matrix travel remains approximate in normal keyless development. End-of-day return travel
  remains uncharged, matching the old solver. Fifty selections are an explicit runtime cap.
- A time-limited heuristic can report drops even if a better feasible arrangement exists.
  Five seconds is a search budget, not an optimality guarantee; no dramatic runtime increase.
- The OR-Tools 9.15 Windows Python SetAllowedVehiclesForIndex binding rejects list arguments;
  native `VehicleVar.RemoveValue` is used instead. The official routing API reference was
  checked on 2026-09-07: [official reference](https://or-tools.github.io/docs/python/classortools_1_1constraint__solver_1_1pywrapcp_1_1RoutingModel.html)

No next-phase work was started.
