# Core Trip Flow Reliability Verification

Verified: 2026-09-07

Status: `[IMPLEMENTED]` in the repository and deterministic test environment. The configured
remote Supabase deployment remains `[PARTIAL]` until the reviewed opening-hours and itinerary-status
migrations in `backend/sql/README.md` are applied to a confirmed non-production target or through the
project's normal production change process.

## Verified flow

```text
Trip Creation
  -> TripDay Configuration
  -> Place Selection
  -> AUTO / LOCKED Assignment
  -> Day-Aware Planner
  -> Itinerary
  -> Map / POI Details
  -> Trip Execution
  -> COMPLETED / MISSED / SKIPPED
  -> Partial Replanning
```

`backend/tests/test_trip_flow_e2e.py` exercises the flow through FastAPI endpoints against an isolated
SQLite database and a deterministic local route provider. The wider backend and Flutter suites cover
the same boundaries in detail without live provider calls.

## Scenarios and invariants

| Scenario | Verified behavior |
|---|---|
| Five-day mixed trip | FULL, REST, HALF, and TRAVEL day windows survive from TripDay configuration through itinerary output. REST receives no visits, the locked place remains on Day 4, and the shorter day windows bound every arrival and departure. |
| Under-filled trip | Two selected places remain the only planned places. Empty days remain valid and no recommendation or discovery provider is called by optimization. |
| Over-packed trip | Feasible visits are scheduled; all excess selections are returned in `unscheduled_places` with a reason. The request succeeds without invalid times. |
| Opening hours | Known and split intervals bound the complete visit. The closed gap is never used. UNKNOWN remains schedulable with `is_opening_hours_known=false`; Flutter never labels it open. |
| Execution state | New stops are PLANNED. PLANNED can become COMPLETED, MISSED, or SKIPPED; MISSED can become SKIPPED or move. COMPLETED and SKIPPED are terminal. |
| Missed-place move | Completed prefixes remain unchanged, the moved place leaves the source future route, the target day is re-optimized, unrelated days remain byte-for-byte equivalent, and an infeasible target leaves the itinerary untouched. |
| Map | Map entry reads the persisted itinerary rather than generating a new one. POI markers open the existing-data sheet, the trip date drives weekday hours, REST days are not move targets, and map mutations publish the returned route to the parent itinerary screen. |
| Failure paths | Mutation guards prevent duplicate Flutter requests. Failed saved-place, TripDay, optimization, status, and move operations retain the previous valid UI state and present an error. |

Reusable itinerary validation asserts:

- arrival is at or after the TripDay start;
- departure is after arrival and at or before the TripDay end;
- departure minus arrival equals the category visit duration;
- `(day_number, visit_order)` is unique;
- a place appears at most once in a generated itinerary;
- known opening intervals contain the entire visit;
- REST days contain no visits;
- LOCKED assignments stay on their configured active day.

## Bugs corrected during this pass

1. Deep map loading called `optimize-route`, which could mutate the itinerary and refresh route-matrix
   data merely by viewing the map. It now reads `GET /trips/{trip_id}/itinerary`.
2. The map did not pass the TripDay date into the POI sheet, so known weekday hours could not be
   evaluated. TripDay data now reaches the sheet.
3. The map offered REST days as move targets. Only non-REST days with valid sightseeing windows are
   now offered.
4. POI actions disagreed with backend rules: PLANNED lacked move, MISSED lacked skip, and SKIPPED
   incorrectly offered move. The UI and backend now share the same transition matrix.
5. COMPLETED and SKIPPED statuses could be reopened through direct API calls. The backend now enforces
   terminal states while keeping idempotent same-status writes valid.
6. Map status and move mutations updated only the map route. `onItineraryChanged` now publishes the
   authoritative backend response to the underlying itinerary screen.
7. Circuit-breaker cooldown tests used a short wall-clock sleep and failed under load. They now use a
   deterministic monotonic clock.

## External API-call audit

| Operation | External POI/routing provider behavior |
|---|---|
| TripDay update | No provider call. Database mutation only. |
| AUTO/LOCKED assignment update | No provider call. Database validation only. |
| Mark COMPLETED/MISSED/SKIPPED | No provider call. Itinerary-row mutation only. |
| Move missed place | Uses `RouteMatrixCache`; calls the configured route provider only for missing or expired traffic-backed legs. A complete static matrix produced zero additional calls in the 15-place journey. |
| Open POI bottom sheet | No provider call. Uses `SavedPlace`, `Place`, `TripDay`, and itinerary data already in memory. |
| Directions / More details | No YatraCanvas provider or Google Places API call. Flutter hands an encoded Google Maps URL to the operating system. |
| Open map | Reads the persisted itinerary. If route geometry was not preloaded, the existing geometry endpoint may call its configured ORS/OSRM adapter; marker and POI data do not trigger discovery or optimization. |

Geoapify and OpenStreetMap remain confined to explicit discovery, search, and prefetch paths. The
audited trip-day, assignment, execution, POI-sheet, and cached partial-replan paths do not enter those
services. No duplicate Geoapify/OSM request was found in the core trip mutation flow.

## Route-matrix cache and performance

Measurements use the local deterministic route provider on the development machine. They are useful
regression baselines, not hosted-service latency guarantees.

| Flow | Result |
|---|---|
| 3 days / 15 places | 5.006 s; 14 scheduled, 1 unscheduled |
| 5 days / 20 places | 5.010 s; 20 scheduled, 0 unscheduled |
| 5 days / 30 places | 5.012 s; 25 scheduled, 5 unscheduled |
| Integrated 5 days / 15 places | 5.200 s optimization; 3.037 s missed-place move |
| Constrained 5 days / 30 places | 5.455 s; 5 scheduled, 25 unscheduled |

The 15-place initial plan populated all 240 directed legs for 16 nodes (depot plus 15 places) in 16
batched provider calls. Status changes and the later missed-place move added zero provider calls. The
30-place constrained plan populated 930 directed legs for 31 nodes in 31 calls. Solver measurements
reach the existing five-second search budget; the timeout was not increased.

## Database consistency

`[IMPLEMENTED]` model and test invariants include contiguous TripDays, unique `(trip_id, day_number)`,
valid day types, valid AUTO/LOCKED assignment pairs, assigned-day ownership, REST-day lock rejection,
unique itinerary visit slots, positive day/order values, valid lifecycle status, and cascade or guarded
behavior for owned rows. Removing a saved place intentionally leaves the last valid itinerary snapshot
available and marks it stale for reviewed re-planning; it does not silently rewrite the itinerary.

The configured remote database was audited read-only. It had 21 trips and 76 matching TripDay rows,
zero invalid saved-place assignments, and zero invalid itinerary day/order rows at audit time. It still
requires the reviewed opening-hours/status forward scripts documented in `backend/sql/README.md`.
No live DDL was executed in this pass.

## Validation

- Backend: 354 passed, 4 dependency deprecation warnings plus 1 local pytest-cache permission warning, 0 failures (277.84 s).
- Flutter: 170 passed, 0 failures.
- Flutter targeted map/POI/parent-state regression: 61 passed.
- Flutter analyze: 0 issues.
- Importer schema: `PlaceCategory.label` is consistent across the model, FSQ importer, and tests;
  `category_label` is not the persisted field.

## Known limitations and technical debt

- `[PARTIAL]` Unscheduled reasons are response metadata and are not stored as a durable plan snapshot.
- `[PARTIAL]` Full optimization is intended for planning. Partial replanning is the protected execution-time
  path; a user-triggered full optimize can replace the itinerary snapshot and reset execution states.
- `[PARTIAL]` SQLite integration tests do not reproduce PostgreSQL RLS or every production FK behavior.
  A follow-up read-only catalog verification confirms the opening-hours and itinerary-status
  migrations are now applied and aligned with current models; the execution actor is `[UNKNOWN]`.
- `[PARTIAL]` OR-Tools uses the complete configured search budget on realistic sizes, so exact optimality is
  not guaranteed even though all returned schedules satisfy the tested constraints.
- `[UNKNOWN]` Hosted provider latency and rate-limit behavior require staging telemetry; no live external
  providers were used in this deterministic reliability pass.
