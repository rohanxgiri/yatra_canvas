# YatraCanvas Current System Verification

Verified: 2026-08-31; database schema parity, trip lifecycle, saved places, keyless
recommendations, and local route estimates re-verified 2026-09-01

Environment: Windows, Python 3.12.14, Flutter 3.47.0, Dart 3.13.0
Scope: current repository, configured backend environment, isolated SQLite API tests, mocked
Flutter/backend integration and legacy Google provider responses, one live Geoapify probe, one
live OpenStreetMap/Overpass Udaipur recommendation flow, and a configured-database audit.
No authentication was added and no production migration was applied. The live recommendation
verification refreshed the existing Udaipur city/category cache and persisted its OSM-backed POIs.

Status labels in this report follow the repository convention: `[IMPLEMENTED]`, `[PARTIAL]`,
`[PLANNED]`, `[DEPRECATED]`, and `[UNKNOWN]`.

## Executive verdict

**PARTIALLY WORKING**

`[IMPLEMENTED]` The FastAPI application imports and starts after one tiny annotation fix. Its
complete automated backend suite passes, every listed endpoint works against a fresh isolated
database, live Geoapify autocomplete works, the Flutter analyzer is clean, and all Flutter tests
pass.

`[IMPLEMENTED]` In the current unauthenticated development slice, the normal Flutter Destination
→ Dates → Arrival → Purpose → Preferences flow calls `POST /trips`. The backend transactionally
creates a `Trip` plus `TripPreference` rows, returns a generated `trip_id`, and Flutter retains it
in the in-memory `TripDraft` and passes it to Place Discovery.

`[IMPLEMENTED]` Place Discovery uses that real ID to load, add, update, reorder, and delete
`UserSavedPlace` rows. Duplicate conflicts reload authoritative state; failed saves do not appear
saved; update responses replace local state; failed reorder reloads backend order; and delete
changes local state only after backend success.

`[PARTIAL]` Authentication, ownership enforcement, trip listing/deletion, and restart persistence
remain absent. The configured remote PostgreSQL target is not proven development/test and has no
verified recovery path, so this feature's write path was proven against isolated test data but
was not manually executed against that database.

`[IMPLEMENTED]` A 2026-09-01 read-only catalog re-audit found all current model fields, types,
nullability, defaults, indexes, unique rules, checks, and foreign keys present in the configured
PostgreSQL database. Read-only `PlaceSource` and `Trip` ORM probes now pass. The catalog changed
during verification even though this task did not execute the repair migration; the actor and
backup/recovery status are unknown, so no write probe was run against that remote database.

`[IMPLEMENTED]` Normal recommendations use keyless OpenStreetMap/Overpass discovery and the
normal optimizer uses local coordinate estimates. A live Udaipur recommendation request returned
200 with 30 results. Google adapters remain legacy and were verified only with owned payloads.
Geoapify is configured and live-tested but remains a freemium autocomplete dependency.

## Backend

### Startup and configuration

- `[IMPLEMENTED]` Settings load successfully and redact `SecretStr` values.
- `[IMPLEMENTED]` `DATABASE_URL` has a supported PostgreSQL scheme and a read-only connection
  succeeds.
- `[IMPLEMENTED]` The FastAPI lifespan completed against the configured database while
  PostgreSQL was forced to `default_transaction_read_only=on`; `GET /` returned 200.
- `[IMPLEMENTED]` A full writable application lifespan completed against a fresh isolated SQLite
  schema; `GET /` returned 200.
- `[PARTIAL]` Normal startup still uses `SQLModel.metadata.create_all`. It creates absent tables
  but cannot repair existing columns or constraints. No normal write-capable startup was run
  against the remote, non-test-named database.

### Implemented endpoint verification

All endpoints below were exercised with controlled local data. Google/Geoapify/Routes responses
in the chained test were fakes at the dependency boundary; live provider results are reported in
their provider sections.

| Endpoint | Result | Evidence |
| --- | --- | --- |
| `POST /cities` | 201 | Created controlled Ajmer row |
| `GET /cities` | 200 | Returned stored cities |
| `GET /cities/search` | 200 | Found controlled city by partial query |
| `GET /cities/{city_id}` | 200 | Returned the created city |
| `GET /cities/autocomplete` | 200 | Normalized fake Google city suggestion |
| `GET /cities/place-details/{google_place_id}` | 200 | Normalized fake Google details |
| `POST /cities/resolve` | 200 | Idempotent Google and non-Google city resolution is covered by tests |
| `GET /locations/autocomplete` | 200 | Fake endpoint test and separate live Geoapify test |
| `POST /places` | 201 | Created a controlled canonical place |
| `GET /cities/{city_id}/places` | 200 | Returned stored canonical places |
| `GET /cities/{city_id}/discover-places` | 200 | Persisted fake nearby results and reused cache |
| `POST /cities/{city_id}/recommendations` | 200 | Deduplicated and ranked three categories |
| `POST /trips` | 201 | Created a controlled trip and related preferences; returned generated `trip_id` |
| `GET /trips/{trip_id}` | 200 | Returned the complete application trip representation including destination, dates, arrival/start, provider IDs, and preferences |
| `PATCH /trips/{trip_id}` | 200 | Partially updated trip fields and reconciled preferences transactionally; invalidated stale route cache |
| `GET /trips/{trip_id}/saved-places` | 200 | Returned the controlled trip list |
| `POST /trips/{trip_id}/saved-places` | 201 | Saved three recommended places |
| `PATCH /trips/{trip_id}/saved-places/reorder` | 200 | Persisted a complete contiguous order |
| `PATCH /trips/{trip_id}/saved-places/{place_id}` | 200 | Persisted notes, priority, lock, and must-visit and returned authoritative state |
| `DELETE /trips/{trip_id}/saved-places/{place_id}` | 204 | Removed one place and normalized order |
| `GET /trips/{trip_id}/start-location` | 200 | Returned selected arrival start |
| `PATCH /trips/{trip_id}/start-location` | 200 | Persisted selected arrival start |
| `POST /trips/{trip_id}/optimize-route` | 200 | Wrote route cache and partitioned multi-day itinerary rows |
| `GET /trips/{trip_id}/route-geometry` | 200 | Returned real road-route coordinates, distance, and duration partitioned by day; verified with openrouteservice, OSRM, and in-memory TTL caching |

Trip listing and trip deletion endpoints remain absent. Authentication is not implemented.

### Tiny verification fix

- **HIGH — fixed:** Python 3.12 initially could not import `app.main`. Inside
  `SavedPlaceService`, the method named `list` shadowed the built-in `list`, so the later runtime
  annotation `list[SavedPlaceRead]` raised `TypeError: 'function' object is not subscriptable`.
  `from __future__ import annotations` was added to defer annotation evaluation. This was the
  source-code fix made during the initial verification.

## Flutter

### Tool results

- `flutter analyze`: **passed**, no issues.
- `flutter test`: **37 passed**, 0 failed.
- `flutter build apk --debug`: **passed** and produced
  `build/app/outputs/flutter-apk/app-regular-debug.apk`.
- Flutter web-server launch: **passed**; `lib/main.dart` was served successfully and then stopped.
- `[IMPLEMENTED]` `regular` is the default Flutter flavor, so plain `flutter run`/`flutter build
  apk` no longer builds both Android flavors and searches for a nonexistent unflavoured APK.

### Flow trace

| Step | Current behavior | Backend dependency |
| --- | --- | --- |
| Destination | Searches stored cities, then Geoapify; persists a new normalized city without requiring Google and stores it in `TripDraft.destination` | `/cities/search`, `/locations/autocomplete`, `/cities/resolve` |
| Dates | Mutates `TripDraft.startDate`, `endDate`, flexibility, and duration | None |
| Arrival | Mutates arrival/start fields; searches Geoapify for hotel/custom and can use device location | `/locations/autocomplete`; values are included in `POST /trips` |
| Purpose | Mutates `TripDraft.purposes` | None |
| Preferences | Mutates pace, budget, and transport, submits the complete draft once, retains the returned ID, and navigates only after success | `POST /trips` |
| Place Discovery | Receives the resolved city and created `trip_id` from the normal setup flow | `/cities/{city_id}/recommendations` |
| Saved Places | Loads backend state on entry; adds/removes recommendations; edits priority/lock/must-visit/notes; persists and reconciles reorder | `/trips/{trip_id}/saved-places...` |
| Route Optimization | Enabled only with non-null `tripId` and at least two saved places | `/trips/{trip_id}/optimize-route` |

`TripDraft` is an in-memory mutable object passed through the five create-trip screens. It is now
submitted through `TripService.createTrip`, and `TripDraft.tripId` retains the generated UUID for
the next trip-dependent flow. It is not serialized or restored after restart. A real `trip_id`
is required in Place Discovery for all saved-place and optimization operations; Arrival can also
use one when editing an already-created trip.

### Flutter issues

- **HIGH:** `TripDraft.tripId` is only retained in memory and is lost when the application
  process restarts; there is no trip-list/resume UI.
- **HIGH:** The configured remote PostgreSQL database is unsafe for a write probe until its
  development/test classification and recovery path are proven.
- **HIGH:** `TripDraft` defaults every destination to `Ujjain Railway Station`, and the arrival
  screen uses Ujjain-only mock arrival suggestions. Selecting Jaipur does not reset this value.
- **MEDIUM:** The date UI is fixed to August 2026 and `TripDraft` defaults to 25–26 August 2026.
  It cannot support a normal trip outside that hard-coded month.
- **MEDIUM:** `LocationService.autocomplete` accepts `hotelOnly`, but ignores it and always sends
  `type=amenity`; hotel searches are not actually narrowed by that argument.
- **MEDIUM:** The optimizer stores and returns only day 1 even when `Trip.days > 1`.

## Trip Creation Verification

Implemented on branch `feature/trip-creation` without authentication or a new provider.

- `[IMPLEMENTED]` `POST /trips` accepts the resolved `city_id`, optional supported trip name,
  start/end dates plus inclusive days, arrival/start-location fields, purposes, and existing
  preference strings. It rejects unknown fields, including client-selected `trip_id`, `user_id`,
  and timestamps.
- `[IMPLEMENTED]` The endpoint validates city existence, date order/day consistency, coordinate
  pairs/ranges, provider identifier pairs, and the name/coordinates required by a non-arrival
  start location.
- `[IMPLEMENTED]` One transaction inserts the `Trip` and unique `TripPreference` rows. A forced
  related-row insertion failure rolled back the complete transaction in tests.
- `[IMPLEMENTED]` The response is `201` and includes the generated UUID `trip_id`, persisted trip
  values, preference values, and server timestamp. The current `Trip` model stores `start_date`
  and `days`, not a separate `end_date` column.
- `[PARTIAL]` Because authentication is intentionally absent while `Trip.user_id` is required,
  the service assigns a fixed server-owned development-only UUID. The request cannot override it.
- `[IMPLEMENTED]` Flutter sends the draft through `TripService`, not widget-owned raw HTTP. The
  Preferences screen disables duplicate submission, presents loading/errors, stores the returned
  ID in `TripDraft.tripId`, and navigates to Place Discovery only after success.
- `[IMPLEMENTED]` Mocked Flutter integration proves the ID reaches
  `PlaceDiscoveryScreen.tripId`; backend API tests prove corresponding Trip/preference rows.
- `[UNKNOWN]` No manual write was issued to the configured remote PostgreSQL target. Its
  development/test classification and recovery path remain unproven, and no disposable local
  PostgreSQL, Docker, `psql`, or `pg_dump` installation was available. This is a safety boundary,
  not an automated feature-test failure.

## Trip Loading and Editing Verification

Implemented on branch `feature/trip-editing` without authentication or new providers.

- `[IMPLEMENTED]` `GET /trips/{trip_id}` returns the complete application trip representation
  including `trip_id`, `city_id`, populated `city` object (`name`, `country`, `state`, etc.),
  `trip_name`, `days`, `start_date`, `end_date`, arrival/start location fields, provider
  identifiers, and all persisted `preferences` (purposes, pace, budget, transport). Returns 404
  for unknown trip UUIDs.
- `[IMPLEMENTED]` `PATCH /trips/{trip_id}` accepts partial updates for user-editable fields:
  `city_id`, `trip_name`, `start_date`, `end_date`, `days`, arrival location/coordinates, start
  location type/name/coordinates/provider, and `purposes`/`preferences`. It rejects forbidden
  server-owned fields (`id`, `trip_id`, `user_id`, `created_at`).
- `[IMPLEMENTED]` Preference updates transactionally delete old rows and insert new deduplicated
  `TripPreference` rows; failure rolls back the entire transaction without leaving partial state.
- `[IMPLEMENTED]` Downstream data safety: `UserSavedPlace` rows are strictly preserved when
  updating a trip. If `city_id` or start location coordinates change, stale `RouteMatrixCache` and
  `TripItinerary` rows for that trip are safely invalidated.
- `[IMPLEMENTED]` Flutter `TripService` provides `getTrip(tripId)` and `updateTrip(tripId, draft)`.
  `TripDraft.fromJson` deserializes the API payload into editable state. `TripPreferencesScreen`
  detects existing `tripId` and executes `updateTrip` (PATCH) instead of `createTrip` (POST),
  retaining the existing trip ID and proceeding to Place Discovery.
- `[IMPLEMENTED]` Current combined backend suite passes 118 tests; the Flutter suite passes 37
  tests and the analyzer reports 0 issues.

## Saved Places Flow Verification

Implemented on branch `feature/saved-places-flow` using the existing schemas and endpoints.

- `[IMPLEMENTED]` `SavedPlaceService` calls list/create/update/reorder/delete with the runtime
  `trip_id`; there is no production hard-coded trip UUID.
- `[IMPLEMENTED]` Place Discovery loads persisted saved places on entry. A successful add uses
  the returned `SavedPlace`; failed adds do not modify the saved list. Concurrent taps for the
  same recommendation are blocked while its request is active.
- `[IMPLEMENTED]` Backend duplicate saves return `409`. Flutter exposes the status safely,
  reloads the collection, and treats the place as saved only if the authoritative response
  contains it.
- `[IMPLEMENTED]` The customization dialog persists and renders `priority`, `is_locked`,
  `must_visit`, and `notes` from the PATCH response.
- `[IMPLEMENTED]` Reorder sends every saved place with contiguous one-based `custom_order`.
  Success replaces the list with the API response; failure reloads authoritative backend order,
  falling back to the previous snapshot only if that reload also fails.
- `[IMPLEMENTED]` Delete addresses the exact `trip_id`/`place_id`. Local removal occurs only
  after `204`, then a collection reload confirms normalized order. A failed delete retains the
  target and all unrelated places.
- `[IMPLEMENTED]` An isolated full-flow test creates a trip through `POST /trips`, loads three
  stored places, saves all three, customizes one, reorders, edits trip metadata, confirms all
  saved rows remain, removes one, and reloads the final two with customization intact.
- `[PARTIAL]` Trip city edits deliberately preserve saved rows. If the city changes, places from
  the previous city can remain associated with the trip; this task reports that cross-city state
  and does not invent a destructive policy.
- `[UNKNOWN]` The configured remote PostgreSQL target was not mutated because its development/test
  classification and recovery path remain unproven. Persistence was verified with controlled
  isolated database records.

## Database

### Fresh test schema

`[IMPLEMENTED]` A fresh SQLModel schema contains all requested models/tables and supports the
isolated endpoint and importer tests:

- `City` / `cities`
- `Place` / `places`
- `CityCategoryCache` / `city_category_cache`
- `PlaceTag` / `place_tags`
- `PlaceSource` / `place_sources`
- `PlaceCategory` / `place_categories`
- `PlaceImportReview` / `place_import_reviews`
- `Trip` / `trips`
- `TripPreference` / `trip_preferences`
- `UserSavedPlace` / `user_saved_places`
- `RouteMatrixCache` / `route_matrix_cache`
- `TripItinerary` / `trip_itinerary`

### Configured database

`[IMPLEMENTED]` All 12 table names now have model-compatible columns and constraints. Read-only
`select(City)`, `select(Place)`, `select(PlaceSource)`, and `select(Trip)` probes succeed. The full
before/after audit, unexpected external state change, and remaining write-verification limits are
recorded in [Database Schema Parity Repair](#database-schema-parity-repair).

## Geoapify

- `[IMPLEMENTED]` `GEOAPIFY_API_KEY` is configured.
- Live `GET /locations/autocomplete` returned 200 for a controlled Jaipur query, with 3 results.
- Every returned result had provider `geoapify`, country code `in`, valid coordinates, and a
  unique provider place ID.
- A repeated identical request returned the same payload. The unit test additionally proves the
  second call is served from the in-process cache rather than issuing another provider request.
- Missing-key behavior is safe: the service raises a stable configuration error without making a
  request or logging the key; the router maps it to 503.

## OpenStreetMap recommendations and legacy Google Places

- `[IMPLEMENTED]` Adapter and endpoint behavior for city autocomplete, city details, location
  details, nearby discovery, normalization, timeouts, invalid IDs, and missing credentials passes
  owned-payload tests.
- `[IMPLEMENTED]` Normal recommendations write canonical `Place`, `PlaceSource`, and `PlaceTag`
  records from bounded Overpass queries, then reuse `CityCategoryCache`.
- `[IMPLEMENTED]` Recommendations reuse each category cache, deduplicate a place appearing in
  more than one category, and rank results deterministically.
- `[IMPLEMENTED]` A live Udaipur normal-flow request returned 200 with 30 religious results,
  retained OSM element provenance, and filtered one malformed OSM business classification.
- `[DEPRECATED]` Legacy Google city/discovery endpoints still return safe 503 responses without
  `GOOGLE_PLACES_API_KEY`; Flutter does not call them in the normal journey.
- `[IMPLEMENTED]` A read-only `PlaceSource` ORM probe now succeeds against the configured
  database; live discovery remains unavailable only because the Google Places key is absent.

## Local route estimates and legacy Google Routes

- `[IMPLEMENTED]` Owned-payload tests verify the Compute Route Matrix request URL, field mask,
  traffic-aware request, static/traffic duration parsing, timeout mapping, and missing-key failure.
- `[IMPLEMENTED]` The normal optimizer writes directed `local_estimate` matrix pairs from stored
  coordinates and requires no external key. The UI labels distance/time as approximate.
- `[IMPLEMENTED]` Fresh cache rows are reused. Expired traffic rows are refreshed; when the
  provider is unavailable and every static leg exists, optimization uses the complete static
  cache.
- `[IMPLEMENTED]` An uncached partial provider matrix fails explicitly and, after caller rollback,
  leaves 0 cache rows. A partial refresh over a complete stale cache retained all 6 static pairs;
  omitted refreshed legs had no traffic duration.
- `[DEPRECATED]` The Google Routes adapter and its owned-payload tests remain, but the normal
  route-optimization endpoint no longer injects it or requires `GOOGLE_ROUTES_API_KEY`.
- `[IMPLEMENTED]` A read-only `Trip` ORM probe now succeeds against the configured database.
  Configured-database route writes were not attempted because its development/test status and
  backup path remain unknown.
- **MEDIUM:** Itinerary persistence is single-day only (`day_number = 1`).

## FSQ Import

- `[IMPLEMENTED]` All 9 importer tests pass. They cover record mapping, invalid coordinates,
  India/city filtering, closed new places, dry-run rollback, repeat-ID idempotency, conservative
  exact-match deduplication, preservation of curated fields, ambiguous review creation, and
  closure metadata updates.
- A controlled one-row Ujjain JSONL import inserted one `Place`, one `PlaceSource`, and one
  `PlaceCategory`. Reimport updated the source without duplication and preserved `imported_at`,
  Apache-2.0 licence metadata, provider lifecycle dates, and unresolved flags.
- `[IMPLEMENTED]` Ambiguous nearby matches create a pending `PlaceImportReview` and do not create
  or overwrite a canonical place.
- **HIGH:** `FSQ_OS_PLACES_PATH` is configured but its target is unavailable/nonexistent in this
  environment, so the configured CLI command cannot currently run without `--source`.
- **HIGH:** Import city configuration contains only Ujjain. A Jaipur import is rejected as an
  unsupported city.
- `[IMPLEMENTED]` The configured schema now contains the current provenance fields. No import was
  run because this repair task explicitly excludes dataset work and the remote database was not
  proven safe for writes.

## End-to-End Seeded Trip Test

The controlled Jaipur flow used a fresh SQLite schema, fake Google Places/Routes responses, and a
fake location provider. The trip itself had to be inserted directly because no trip-create API
exists.

1. City create/list/search/get: succeeded.
2. Google city autocomplete/details and `/cities/resolve`: succeeded with normalized fakes.
3. Arrival/start location: succeeded after direct trip seeding with arrival coordinates.
4. Religious place discovery and cache hit: succeeded.
5. Multi-category recommendations: succeeded.
6. Save three places: succeeded.
7. Update notes/priority/must-visit: succeeded.
8. Reorder all saved places: succeeded.
9. Delete one saved place: succeeded; two remained.
10. Optimize route: succeeded; 6 cache rows and 2 day-1 itinerary rows were stored.

Verdict: **the backend's supported sub-flow works with a pre-existing trip and working provider
adapters. A separate trip-creation verification now proves that the normal Flutter flow can
create that prerequisite trip and hand its real ID to Place Discovery with isolated test data.**

## Broken Flows

- **HIGH:** A created trip cannot be resumed from a trip list after app restart because
  `TripDraft` has no durable client session storage and the backend has no trip-list endpoint.
- **MEDIUM:** Changing `Trip.city_id` preserves existing saved places even when those places
  belong to the prior city; no cross-city reconciliation policy exists.
- **HIGH:** The configured remote PostgreSQL write path remains unverified because target safety
  and backup/recovery status are unknown.
- **HIGH:** Arrival-as-start can be created without coordinates because the existing built-in
  station/airport suggestions provide labels only; start-location reads and route optimization
  still require coordinates.
- **MEDIUM:** Public Overpass instances are best-effort and can time out or rate limit; production
  scale needs reviewed regional extracts or a self-hosted deployment.
- **MEDIUM:** Destination/arrival autocomplete still uses the freemium Geoapify service, so the
  full new-city journey is not yet strictly provider-free.
- **MEDIUM:** Multi-day trips are collapsed into a day-1 itinerary.
- **MEDIUM:** Date selection and arrival suggestions are prototype-hard-coded.

## Configuration Problems

Secret values were never printed.

| Variable | Required | Configured | Used by code | Assessment |
| --- | --- | --- | --- | --- |
| `DATABASE_URL` | Yes | Yes | Yes | Valid scheme and reachable; remote/non-test-named, environment classification and backup status unknown |
| `GEOAPIFY_API_KEY` | For Geoapify path | Yes | Yes | Live request passed |
| `GOOGLE_PLACES_API_KEY` | Legacy endpoints only | No | Yes | Normal destination and recommendation journey remains available |
| `GOOGLE_ROUTES_API_KEY` | Legacy adapter only | No | Yes | Normal optimizer uses local estimates |
| `OVERPASS_API_URL` | No | Default | Yes | Keyless recommendation endpoint; public instance is best-effort |
| `OVERPASS_TIMEOUT_SECONDS` | No | Default | Yes | Bounded provider timeout |
| `OVERPASS_RADIUS_METERS` | No | Default | Yes | Bounded Udaipur discovery area |
| `FSQ_OS_PLACES_PATH` | No; CLI source may override | Yes | Yes | Configured target does not exist/is unavailable |
| `GEOAPIFY_BASE_URL` | No | Yes | Yes | Settings validation passed |
| `GEOAPIFY_TIMEOUT_SECONDS` | No | Yes | Yes | Settings validation passed |
| `GEOAPIFY_AUTOCOMPLETE_CACHE_TTL_SECONDS` | No | Yes | Yes | Settings validation and cache tests passed |
| `FSQ_DEDUPE_DISTANCE_METERS` | No | Yes | Yes | Settings validation and importer construction passed |
| `FSQ_IMPORT_BATCH_SIZE` | No | Yes | Yes | Settings validation and importer construction passed |
| `ROUTE_MATRIX_TRAFFIC_TTL_MINUTES` | No | Yes | Yes | Expiry/fallback tests passed |
| `PLACE_DISCOVERY_CACHE_TTL_HOURS` | No | Yes | Yes | Discovery cache test passed |
| `GOOGLE_NEARBY_RADIUS_METERS` | No | Yes | Yes | Passed to nearby adapter in tests |
| `PLACE_POPULAR_MIN_RATING` | No | Yes | Yes | Classification path tested |
| `PLACE_POPULAR_MIN_REVIEW_COUNT` | No | Yes | Yes | Classification path tested |

There are no unknown variable names in `backend/.env`, no implemented settings missing from
`.env.example` or the environment documentation, and no settings fields found unused or
incorrectly named in backend code. The two absent Google key names are not present in the local
`.env`, rather than present with blank values. Flutter's public `API_BASE_URL` uses the documented
emulator default unless overridden at build time.

## Bugs Found

| Severity | Bug | Current effect |
| --- | --- | --- |
| CRITICAL | Configured database cannot be proven development/test and has no verified recovery evidence | Blocks authorized write/migration verification despite current catalog parity |
| HIGH | Configured catalog changed during the audit without an execution by this task | Migration actor, review, and backup context are unknown |
| HIGH | Runtime `ApiConfig.baseUrl` getter was used as seven constructor default values | Fixed; Dart kernel compilation and regular debug APK build now pass |
| HIGH | Created `TripDraft.tripId` is in-memory only | Trip cannot be resumed after app restart |
| HIGH | Arrival label suggestions may lack coordinates | Arrival-as-start route optimization can remain blocked |
| HIGH | Ujjain arrival defaults survive selection of another city | A trip can show/save the wrong arrival label |
| HIGH | Python 3.12 annotation shadowing blocked backend import | Fixed with deferred annotations during this audit |
| MEDIUM | August 2026-only date picker | Trips outside one prototype month cannot be selected |
| MEDIUM | `hotelOnly` is ignored | Hotel autocomplete is not actually hotel-specific |
| MEDIUM | Optimizer writes only day 1 | Multi-day itinerary is incomplete |
| LOW | Starlette deprecates the current `httpx` TestClient bridge | One warning; tests still pass |

## Tests

### Backend

Initial run:

- Collection stopped with 3 errors in `test_route_optimization.py`, `test_routes.py`, and
  `test_saved_places_routes.py` due to the `SavedPlaceService.list` annotation-shadowing bug.

After the tiny fix and trip-creation implementation:

- First sandboxed rerun: 77 passed, 5 FSQ setup errors caused only by pytest trying to use an
  inaccessible user temp directory.
- Current complete rerun with repository-local `--basetemp`: **118 passed, 0 failed, 1 warning**.
- Warning: `StarletteDeprecationWarning` says the `httpx` bridge in `starlette.testclient` is
  deprecated in favor of `httpx2`.
- Additional targeted verification: all listed endpoints passed; live Geoapify passed; configured
  database audit found the documented drift; partial route-matrix behavior passed; controlled
  FSQ import passed.

### Flutter

- `flutter analyze`: **0 issues**.
- `flutter test`: **37 passed, 0 failed**.

## Database Schema Parity Repair

Re-audited: 2026-09-01

Branch: `fix/database-schema-parity`

### Target classification and execution decision

- **CRITICAL — `[UNKNOWN]`:** The configured PostgreSQL target is remote, its database name has
  no development/test marker, and neither repository configuration nor process environment
  declares it to be development/test. The target therefore could not be confidently classified
  as safe.
- **CRITICAL — `[UNKNOWN]`:** No recoverable backup, snapshot identifier, restore drill, or
  equivalent recovery path could be verified from repository or database evidence.
- Migration application by this task: **NO**. No DDL or test-data write was issued to the
  configured database.
- During the audit, the remote catalog changed from the documented pre-repair state to a state
  containing the repair's equivalent columns, types, indexes, and constraint names. This task did
  not execute that change, so its actor, review path, and backup status remain **`[UNKNOWN]`**.

### Complete mismatch list before repair

The audit compared every model column's PostgreSQL type, nullability, server default, primary-key
membership, index and uniqueness metadata, foreign-key target/delete behavior, and named checks.
All table and column names below refer to `public`.

| Table | Model/database field | Expected model definition | Database definition before repair | Classification |
| --- | --- | --- | --- | --- |
| `place_sources` | `source_url` | `VARCHAR(1000) NULL`, no server default | absent | `MISSING_IN_DATABASE` |
| `place_sources` | `licence_identifier` | `VARCHAR(120) NOT NULL`, default `unknown` | absent | `MISSING_IN_DATABASE` |
| `place_sources` | `address` | `VARCHAR(500) NULL`, no server default | absent | `MISSING_IN_DATABASE` |
| `place_sources` | `locality` | `VARCHAR(160) NULL`, no server default | absent | `MISSING_IN_DATABASE` |
| `place_sources` | `region` | `VARCHAR(160) NULL`, no server default | absent | `MISSING_IN_DATABASE` |
| `place_sources` | `postcode` | `VARCHAR(40) NULL`, no server default | absent | `MISSING_IN_DATABASE` |
| `place_sources` | `country_code` | `VARCHAR(2) NULL`, no server default | absent | `MISSING_IN_DATABASE` |
| `place_sources` | `telephone` | `VARCHAR(80) NULL`, no server default | absent | `MISSING_IN_DATABASE` |
| `place_sources` | `website` | `VARCHAR(1000) NULL`, no server default | absent | `MISSING_IN_DATABASE` |
| `place_sources` | `email` | `VARCHAR(320) NULL`, no server default | absent | `MISSING_IN_DATABASE` |
| `place_sources` | `social_identifiers` | `JSON NOT NULL`, default `{}` | absent | `MISSING_IN_DATABASE` |
| `place_sources` | `source_date_created` | `DATE NULL`, no server default | absent | `MISSING_IN_DATABASE` |
| `place_sources` | `source_date_refreshed` | `DATE NULL`, no server default | absent | `MISSING_IN_DATABASE` |
| `place_sources` | `source_date_closed` | `DATE NULL`, no server default | absent | `MISSING_IN_DATABASE` |
| `place_sources` | `unresolved_flags` | `JSON NOT NULL`, default `[]` | absent | `MISSING_IN_DATABASE` |
| `place_sources` | `imported_at` | `TIMESTAMPTZ NOT NULL`, default `now()` | absent | `MISSING_IN_DATABASE` |
| `place_sources` | `ix_place_sources_locality` | non-unique index on `locality` | absent | `CONSTRAINT_MISMATCH` |
| `trips` | `start_location_type` | `VARCHAR(30) NULL` | `TEXT NULL` | `TYPE_MISMATCH` |
| `trips` | `start_location_name` | `VARCHAR(255) NULL` | `TEXT NULL` | `TYPE_MISMATCH` |
| `trips` | `start_location_provider` | `VARCHAR(50) NULL` | absent | `MISSING_IN_DATABASE` |
| `trips` | `start_location_provider_place_id` | `VARCHAR(500) NULL` | absent | `MISSING_IN_DATABASE` |
| `user_saved_places` | `priority` default | model metadata omitted server default | `0` | `DEFAULT_MISMATCH` |
| `user_saved_places` | `is_locked` default | model metadata omitted server default | `false` | `DEFAULT_MISMATCH` |
| `user_saved_places` | `must_visit` default | model metadata omitted server default | `false` | `DEFAULT_MISMATCH` |
| `route_matrix_cache` | `from_location_type` | `VARCHAR(30) NOT NULL` | `TEXT NOT NULL` | `TYPE_MISMATCH` |
| `route_matrix_cache` | `from_name` | `VARCHAR(255) NULL` | `TEXT NULL` | `TYPE_MISMATCH` |
| `route_matrix_cache` | `to_location_type` | `VARCHAR(30) NOT NULL` | `TEXT NOT NULL` | `TYPE_MISMATCH` |
| `route_matrix_cache` | `to_name` | `VARCHAR(255) NULL` | `TEXT NULL` | `TYPE_MISMATCH` |
| `route_matrix_cache` | `from_key` | `VARCHAR(350) NOT NULL` | `TEXT NOT NULL` | `TYPE_MISMATCH` |
| `route_matrix_cache` | `to_key` | `VARCHAR(350) NOT NULL` | `TEXT NOT NULL` | `TYPE_MISMATCH` |
| `route_matrix_cache` | `travel_mode` | `VARCHAR(30) NOT NULL` | `TEXT NOT NULL` | `TYPE_MISMATCH` |
| `route_matrix_cache` | `travel_mode` default | model metadata omitted server default | `driving` | `DEFAULT_MISMATCH` |
| `route_matrix_cache` | pair uniqueness | named `UNIQUE` constraint on `trip_id, from_key, to_key, travel_mode` | standalone unique index with the same name/columns | `CONSTRAINT_MISMATCH` |
| `route_matrix_cache` | `ix_route_matrix_cache_from_key` | non-unique index on `from_key` | absent | `CONSTRAINT_MISMATCH` |
| `route_matrix_cache` | `ix_route_matrix_cache_to_key` | non-unique index on `to_key` | absent | `CONSTRAINT_MISMATCH` |
| `route_matrix_cache` | `ix_route_matrix_cache_from_place_id` | non-unique index on `from_place_id` | absent | `CONSTRAINT_MISMATCH` |
| `route_matrix_cache` | `ix_route_matrix_cache_to_place_id` | non-unique index on `to_place_id` | absent | `CONSTRAINT_MISMATCH` |
| `route_matrix_cache` | distance check name | `ck_route_matrix_distance` | equivalent check named `route_matrix_cache_distance_meters_check` | `CONSTRAINT_MISMATCH` |
| `route_matrix_cache` | static-duration check name | `ck_route_matrix_static_duration` | equivalent check named `route_matrix_cache_static_duration_seconds_check` | `CONSTRAINT_MISMATCH` |
| `route_matrix_cache` | traffic-duration check name | `ck_route_matrix_traffic_duration` | equivalent check named `route_matrix_cache_traffic_duration_seconds_check` | `CONSTRAINT_MISMATCH` |
| `route_matrix_cache` | `trip_id` foreign key | model metadata omitted delete action | valid database foreign key used `ON DELETE CASCADE` | `CONSTRAINT_MISMATCH` |
| `route_matrix_cache` | `from_place_id` foreign key | model metadata omitted delete action | valid database foreign key used `ON DELETE CASCADE` | `CONSTRAINT_MISMATCH` |
| `route_matrix_cache` | `to_place_id` foreign key | model metadata omitted delete action | valid database foreign key used `ON DELETE CASCADE` | `CONSTRAINT_MISMATCH` |

All unlisted properties were `MATCH`. In particular, there were no extra columns, missing tables,
primary-key mismatches, nullability mismatches, or foreign-key target mismatches. PostgreSQL
reflects some checks in canonical forms such as `BETWEEN` as `>=`/`<=`, `IN` as `ANY(array)`, and
numeric expressions with explicit casts. The 15 remaining textual differences after repair have
the same constraint names and semantics and are classified `MATCH`, not schema discrepancies.

### Root cause and migration history

- **CRITICAL:** `SQLModel.metadata.create_all` creates absent objects but never upgrades existing
  tables. The configured database therefore retained earlier table definitions.
- The city and provider-external-ID unique migrations appear applied because their named
  constraints exist.
- `add_route_matrix_priorities_start_location.sql` clearly supplied the original route table,
  defaults, cascade foreign keys, start fields, and unique index, but its `TEXT` types, omitted
  secondary indexes, anonymous inline checks, and index-vs-constraint representation drifted from
  current metadata.
- `add_fsq_geoapify_foundation.sql` was not fully applied before the repair: its two new table
  names existed, plausibly from `create_all`, while all 16 `place_sources` additions and both trip
  provider fields were absent.
- There is no ordered migration ledger, so repository evidence cannot prove execution order.
  Existing forward scripts are not needed after this parity repair and must not be blindly rerun.
  `rollback_fsq_geoapify_foundation.sql` is destructive and must not be run after provenance data
  is written.

### Repair artifacts and safety

- Migration created: `backend/sql/repair_current_schema_parity.sql`.
- It uses one PostgreSQL transaction, verifies all 12 prerequisite tables, adds only current-model
  fields, rejects over-length existing text before bounded conversions, preserves provider IDs and
  foreign keys, retains valid cascade behavior, and adds the missing indexes.
- Legacy source rows are backfilled conservatively: unknown licenses remain explicitly `unknown`;
  JSON metadata becomes empty rather than fabricated; `imported_at` preserves `last_fetched_at`
  when available and otherwise uses transaction time. No source lifecycle field is overwritten.
- The migration contains no `DROP COLUMN`, `DROP TABLE`, `DELETE`, `TRUNCATE`, or table recreation.
  Existing route checks are renamed rather than dropped, and the existing unique index is promoted
  to the model-declared constraint.
- Model metadata now declares the already-valid server defaults and route-cache cascade delete
  actions, preventing a fresh `create_all` schema from drifting from the preserved database
  behavior.
- Local PostgreSQL syntax validation: `pglast` accepted all 18 statements. No local PostgreSQL
  server or container runtime was available for an execution test.
- Recovery before commit is transactional rollback. After application writes use the repaired
  columns, automatic down-migration is unsafe; recovery is roll-forward or restoration of a
  verified pre-migration backup.

### Schema and ORM status afterward

- Current read-only catalog comparison: **0 genuine mismatches** across all 12 models/tables.
- Remaining extra/legacy columns: **none found**.
- Configured-database read-only ORM: `City`, `Place`, `PlaceSource`, and `Trip` all pass.
- Controlled isolated ORM smoke: create/read/update `PlaceSource`, preserve provider ID,
  provenance, licensing and lifecycle fields, and read its `PlaceCategory`: **passed**.
- Controlled isolated ORM smoke: create/read/update `Trip` and read related `TripPreference`,
  `UserSavedPlace`, `RouteMatrixCache`, and `TripItinerary`: **passed**.
- **HIGH:** Configured-database create/update/delete ORM verification was not run because the
  target and backup preconditions were not satisfied.

### API verification after catalog repair

- Configured database in enforced read-only mode: `GET /cities` 200, `GET /cities/{city_id}` 200,
  and `GET /cities/{city_id}/places` 200.
- A random missing trip now produces normal 404 responses from saved-place and start-location
  reads instead of a missing-column database error.
- The configured database contains zero trips, saved places, route-cache rows, and itineraries;
  there is no configured seeded trip to exercise.
- The complete isolated backend suite still verifies discovery, recommendations, seeded trip,
  start location, saved-place add/update/reorder/delete, route caching, and optimization.
- **HIGH:** Mutating configured-database APIs were not run because doing so would violate the
  target-classification and backup gates.

### Test results and remaining database risks

- At schema-parity repair time, backend: **82 passed, 0 failed, 1 Starlette deprecation warning**. An initial sandbox run had
  five temp-directory setup errors; rerunning with a workspace-local `--basetemp` passed all tests.
- At schema-parity repair time, Flutter: **22 passed, 0 failed**.
- `flutter analyze`: **no issues**.
- Migration parser: **18/18 statements accepted**.
- **CRITICAL:** Target environment and recovery status remain unknown.
- **HIGH:** The external catalog change cannot be attributed from repository evidence.
- **HIGH:** PostgreSQL write-path/backfill behavior has not been exercised in a disposable
  PostgreSQL clone; existing provenance and trip tables were empty when aggregate preconditions
  were checked.
- **MEDIUM:** Standalone SQL files still lack an ordered migration/version ledger.
- **LOW:** PostgreSQL check-expression reflection is textually different but semantically equal.

## Recommended Fixes

1. **CRITICAL:** Explicitly classify the configured database environment and record a verified
   backup/restore path before any future write probe or migration. Do not rely on `create_all` to
   upgrade existing tables.
2. **HIGH:** Add durable trip-list/resume support so the generated `trip_id` and draft are not
   lost on app restart; retain the isolated development identity until authentication is a
   separately authorized task.
3. **MEDIUM:** Define and test a non-destructive product policy for saved places when a trip's
   destination city changes; current behavior preserves potentially cross-city rows.
4. **HIGH:** Replace Ujjain-only arrival defaults with destination-aware or provider-selected
   arrival values and persist arrival coordinates.
5. **MEDIUM:** Replace the fixed August 2026 calendar with a current, navigable date range.
6. **MEDIUM:** Either implement a real hotel-specific location filter or remove the unused
   `hotelOnly` contract.
7. **MEDIUM:** Keep the current Google dependencies, but configure restricted Places and Routes
   keys in a test deployment when live-provider verification is desired.
8. **LOW:** Address the Starlette/TestClient dependency warning during the next dependency update;
   it does not block current verification.

### Final answers

**A. What currently works:** backend configuration loading, read-only startup, transactional trip
and preference creation on a fresh schema, generated `trip_id` handoff from Flutter to Place
Discovery, controlled discovery/recommendations, saved-place load/add/customize/reorder/delete
with failure reconciliation, start-location persistence for a seeded trip, route
caching/optimization/fallback, Geoapify live autocomplete,
the Ujjain FSQ importer, Flutter analysis, and all automated tests.

**B. What currently fails:** trip resume after process restart, live Google paths without keys,
configured-database write verification without a proven safe environment, the configured FSQ
default path, multi-day itinerary generation, general date selection, and destination-aware
arrival defaults/coordinates.

**C. What needs fixing immediately:** classify and protect the database environment, then add a
durable trip-list/resume path for the real ID now used by the Flutter flow.

**D. What can wait:** authentication, Google removal, provider replacement, interactive maps,
admin workflows, multi-day optimization, the TestClient deprecation, and unrelated formatting/type
debt.

**E. Ready for a complete Jaipur dataset? Not evaluated in this repair.** Current direction
explicitly excludes Jaipur/static dataset work; schema compatibility alone is not authorization
or readiness for a city-wide import.

**F. Single best next development task:** verify and harden route optimization from the normal
real-trip saved-place flow, without adding multi-day planning or changing providers.

## Weather-Aware Trip Assistance Verification

Verified: 2026-09-02 on branch `feature/weather-advisories`.

Scope:
- Provider-neutral `WeatherProvider` protocol and `OpenMeteoWeatherProvider` adapter with in-memory TTL caching.
- Itinerary-aware `WeatherAdvisoryService` detecting adverse conditions ($\ge 2$ consecutive hours) overlapping with scheduled outdoor stops.
- Deterministic `PlaceEnvironmentClassifier` identifying outdoor-exposed versus sheltered-indoor venues using categories, tags, and titles.
- `WeatherAlternativeService` ranking indoor attractions by user preferences, non-persisted day rearrangement preview, and transactional apply preserving `must_visit` and `is_locked` constraints.
- Endpoints:
  - `GET /trips/{trip_id}/weather-advisories`
  - `GET /trips/{trip_id}/weather-alternatives`
  - `POST /trips/{trip_id}/rearrange-preview`
  - `POST /trips/{trip_id}/apply-itinerary-adjustment`
  - `POST /trips/{trip_id}/ignore-weather`
- Flutter UI: `WeatherAdvisoryCard` wired into Place Discovery with default "Continue as planned", alternatives bottom sheet, rearrange dialog, and ignore action.

Automated test results:
- Backend: 145/145 pytest tests passed (including all 12 weather advisory tests).
- Flutter: 51/51 flutter tests passed (including all weather advisory models, services, and widget tests).
- Static analysis: `flutter analyze` passed with 0 issues.

## Realistic Itinerary Timing & Opening-Hours Awareness Verification

Verified: 2026-09-02 on branch `feature/time-aware-itinerary`.

Scope:
- Centralized daily planning windows (`DEFAULT_DAY_START_TIME = 09:00`, `DEFAULT_DAY_END_TIME = 19:00`, `DEFAULT_DAILY_BUDGET_MINUTES = 600`) and midday lunch breaks (`12:30–13:30`, 60 minutes) defined in `backend/app/core/itinerary_constants.py`.
- Category-based deterministic visit duration heuristics (e.g. 120m for forts/palaces, 90m for museums/malls, 60m for parks/gardens, 45m for monuments/temples/cafes, 75m fallback).
- Provider-neutral opening-hours normalization model (`PlaceOpeningHours`). Unknown opening hours remain safely unpopulated/nullable without fabricating data. When hours are provided, delay arrivals to opening time, detect early closing conflicts, and never silently drop places.
- `ItineraryTimingService` generating sequential arrival and departure timestamps, travel time insertion, midday lunch breaks, multi-day partitioning, must-visit preservation, and transactional regeneration.
- Extended `OptimizedPlaceRead` (`planned_arrival_time`, `planned_departure_time`, `visit_duration_minutes`, `is_opening_hours_known`) and `RouteOptimizationRead` (`breaks`, `conflicts`).
- Flutter UI rendering:
  - `_OptimizedRouteCard` displays formatted time windows (e.g. `09:15 – 10:00 · ~45 min visit`).
  - `_MiddayBreakCard` displays scheduled meal/rest intervals (e.g. `12:30 – 13:30 · 60 min rest & meals`).
  - `_RouteConnector` displays travel duration and distance.
  - Planning conflict banner for overflow or closing hour conflicts.
  - Footnote clarifying times are planning estimates.
- Currency removed from active roadmap.

Automated test results:
- Backend: 155/155 pytest tests passed (including all 10 itinerary timing tests in `tests/test_itinerary_timing.py`).
- Flutter: 53/53 flutter tests passed (including all time-aware model and widget tests in `test/itinerary_timing_test.dart`).
- Static analysis: `flutter analyze` passed with 0 issues.
