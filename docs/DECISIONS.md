# Architectural decisions

Last reviewed: 2026-09-07

These records describe accepted direction without claiming all consequences are implemented.
Changing an accepted decision requires a new or amended record plus updates to architecture,
provider, environment, and data-model documentation.

## ADR-001 — PostgreSQL is canonical; Supabase Auth is the target identity layer

- **Status:** Accepted direction; `[IMPLEMENTED]` PostgreSQL, `[PLANNED]` Supabase Auth/RLS.
- **Date:** 2026-08-31.
- **Context:** FastAPI and SQLModel already read/write PostgreSQL. `Trip.user_id` is a UUID but
  has no verified identity or foreign key. Flutter has only a phone-entry UI.
- **Decision:** Keep canonical trip/place/application data in PostgreSQL. Use Supabase Auth for
  identity and verified JWTs when implemented. Keep FastAPI as the provider/orchestration and
  authorization boundary. Direct Supabase client data access is permitted only with versioned,
  tested grants and RLS.
- **Consequences:** `DATABASE_URL` remains required. Supabase URL/public/service-role variables
  are not added before an SDK/auth path exists. Auth, profiles, ownership, RLS, and migrations
  remain explicit roadmap work.
- **Evidence:** `backend/app/database.py`, `backend/app/models/entities.py`,
  `lib/screens/onboarding/login_screen.dart`; [Supabase database](https://supabase.com/docs/guides/database/overview),
  [Auth](https://supabase.com/docs/guides/auth), and
  [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), last verified
  2026-08-31.

## ADR-002 — FSQ Open Source Places is a batch dataset, not a runtime Places API

- **Status:** Accepted and `[IMPLEMENTED]` for local CSV/JSONL import; portal automation is absent.
- **Date:** 2026-08-31.
- **Context:** Launch-city POIs benefit from open bulk data, while a proprietary Foursquare API
  would add runtime key, pricing, and lock-in concerns. The official OS schema does not list
  proprietary ratings, popularity, tips, or photos.
- **Decision:** Operators obtain a bounded FSQ OS Places extract and feed the backend importer.
  Persist only documented fields with `Apache-2.0` provenance. Never fabricate premium fields or
  make the proprietary Foursquare Places API a required dependency without a new decision.
- **Consequences:** Portal access tokens remain outside current app configuration. The importer
  must track deltas/closures more fully before automation; existing canonical places remain usable
  without portal/API availability.
- **Evidence:** `backend/app/importers/fsq_os_places.py`, `backend/app/cli.py`, importer tests;
  [official access](https://docs.foursquare.com/data-products/docs/access-fsq-os-places) and
  [schema](https://docs.foursquare.com/data-products/docs/places-os-data-schema), last verified
  2026-08-31.

## ADR-003 — Geoapify has a narrow runtime autocomplete/geocoding role

- **Status:** Accepted; `[IMPLEMENTED]` for destination and arrival/location autocomplete,
  `[PARTIAL]` for durable non-Google city identity.
- **Date:** 2026-08-31.
- **Context:** A user typing an airport, station, address, or city needs current geocoding, while
  POI acquisition, routing, and map rendering have different cost, cache, and data-quality needs.
- **Decision:** Use Geoapify behind FastAPI for runtime autocomplete/geocoding. Do not expand it by
  default into POI discovery, routing, weather, or map rendering. Flutter consumes an
  application-owned response and displays required Geoapify/OSM attribution.
- **Consequences:** `GEOAPIFY_API_KEY` stays backend-only. Current in-memory caching is adequate
  only for early development. Other geographic responsibilities require their own decisions.
- **Evidence:** `backend/app/services/location_autocomplete_provider.py`,
  `backend/app/services/geoapify_service.py`, `backend/app/routers/locations.py`, Flutter location
  service/tests; [official autocomplete](https://apidocs.geoapify.com/docs/geocoding/address-autocomplete/)
  and [terms](https://www.geoapify.com/terms-and-conditions/), last verified 2026-08-31.

## ADR-004 — openrouteservice is the target routing/matrix provider

- **Status:** Superseded for the normal development path by ADR-008; openrouteservice remains a
  `[PLANNED]` production-quality routing candidate and Google Routes is legacy `[DEPRECATED]`.
- **Date:** 2026-08-31.
- **Context:** The optimizer needs distance/duration matrices. It now uses local estimates for
  keyless development; the target production architecture favors an OSM-based provider with hosted and self-hosted
  options, but those deployment modes have different limits and capabilities.
- **Decision:** Keep routing and matrix requests behind an application-owned interface and evaluate
  openrouteservice for production-grade routes. Select hosted versus self-hosted operation only
  after capacity, attribution, cost, and support evaluation. Do not make Google a normal-flow
  prerequisite.
- **Consequences:** No openrouteservice key/config is added yet. The current local estimates are
  explicitly approximate. Cache rows or keys may need a provider/version dimension through a
  reversible migration. Multi-day planning is separate and must also be completed.
- **Evidence:** `backend/app/services/google_routes_service.py`,
  `backend/app/services/route_matrix_service.py`, optimizer tests;
  [openrouteservice API docs](https://openrouteservice.org/dev/#/api-docs) and
  [endpoint reference](https://giscience.github.io/openrouteservice/api-reference/endpoints/),
  last verified 2026-08-31.

## ADR-005 — Google Places is transitional, not a target required dependency

- **Status:** `[DEPRECATED]` for normal flows; legacy adapter and endpoints remain `[IMPLEMENTED]`.
- **Date:** 2026-08-31.
- **Context:** The normal Flutter destination flow uses Geoapify and recommendations now use
  OpenStreetMap/Overpass. Google Places retains legacy city autocomplete/details and discovery
  endpoints. Durable non-Google city identity is not yet complete. Cities retain nullable
  legacy Google IDs and a uniqueness constraint.
- **Decision:** Avoid new Google Places responsibilities. Replace city resolution and discovery
  incrementally, verify launch-city coverage, retain provenance/legacy IDs, and disable Places
  only after a test deployment works without its key and a rollback release exists.
- **Consequences:** Legacy Google settings remain documented but may be empty for the normal
  journey. Current Google storage/attribution terms require review during backfill. No column or
  constraint is dropped merely because the target provider changes.
- **Evidence:** `backend/app/services/google_places_service.py`, `place_discovery_service.py`,
  `backend/app/routers/cities.py`, `City.google_place_id`, Google service tests;
  [Places API overview](https://developers.google.com/maps/documentation/places/web-service/overview),
  [Autocomplete](https://developers.google.com/maps/documentation/places/web-service/place-autocomplete),
  and [Nearby Search](https://developers.google.com/maps/documentation/places/web-service/nearby-search),
  last verified 2026-08-31.

## ADR-006 — Map rendering is evaluated independently from Places

- **Status:** Accepted; map implementation `[PLANNED]`, Google Maps SDK not present.
- **Date:** 2026-08-31.
- **Context:** Places API, Routes API, and platform map SDKs are separate products. This Flutter
  app has no map package or Android/iOS map key configuration; decorative map art and attribution
  labels do not constitute an interactive renderer.
- **Decision:** Choose the Flutter renderer, tile provider, SDK, offline/cache behavior, supported
  platforms, accessibility, and attribution as a separate architecture decision. Never remove or
  add a Maps SDK solely because the Places provider changed.
- **Consequences:** No Maps SDK key is requested today. If Google Maps or an open renderer is
  adopted, its configuration, platform manifests, restrictions, licensing, tests, and failure
  behavior must be documented independently.
- **Evidence:** `pubspec.yaml`, `android/app/src/main/AndroidManifest.xml`, Flutter screen search;
  [Google Maps Platform documentation](https://developers.google.com/maps/documentation), last
  verified 2026-08-31.

## ADR-007 — Preserve provider provenance and require explicit verification

- **Status:** Accepted and `[PARTIAL]`.
- **Date:** 2026-08-31.
- **Context:** External datasets may conflict, become stale, close, merge, use different IDs, or
  carry field-specific licenses. Current `PlaceSource`, `PlaceCategory`, and
  `PlaceImportReview` provide a foundation, but canonical fields lack full verification/audit
  history and the admin UI is a mock.
- **Decision:** Treat provider records as candidates. Retain provider namespace/ID, source URL,
  licence, fetch/provider timestamps, unresolved flags, and match evidence. Ambiguous matches go
  to review. A source must not silently overwrite curated canonical fields.
- **Consequences:** New sources need lifecycle, deletion/update, attribution, and dedupe rules.
  Human verification needs authorized APIs and actor/before/after audit history. A boolean on a
  provider response is not sufficient proof of canonical quality.
- **Evidence:** `backend/app/models/entities.py`, `backend/app/importers/fsq_os_places.py`,
  `backend/tests/test_fsq_importer.py`, and [Data model](DATA_MODEL.md).

## ADR-008 — Normal development flows must not require paid provider keys

- **Status:** Accepted and `[PARTIAL]`.
- **Date:** 2026-09-01.
- **Context:** Google-backed fakes passed tests while a keyless running app failed at destination,
  recommendation, and route-matrix boundaries. The product constraint is to avoid paid runtime
  services.
- **Decision:** The normal destination and arrival flow uses the existing Geoapify development
  key for now, POI recommendations use bounded cached OpenStreetMap/Overpass queries, and route
  ordering uses clearly labelled local coordinate estimates. Google adapters remain legacy and
  must not be dependencies of the normal Flutter journey. For production scale, use reviewed
  regional OSM extracts or a self-hosted Overpass deployment rather than assuming a public
  instance is an SLA-backed service.
- **Consequences:** POI results carry OpenStreetMap element provenance and `ODbL-1.0`; the UI
  displays attribution. Local route times are approximate and do not claim road/traffic accuracy.
  The development default uses the documented public FOSSGIS `lz4` Overpass endpoint after the
  load-balanced endpoint repeatedly returned upstream 504 responses for bounded Manali queries;
  deployments may override it with `OVERPASS_API_URL`. Geoapify remains a freemium dependency to
  remove for a strict provider-free destination flow.
- **Evidence:** `backend/app/services/openstreetmap_places_service.py`,
  `backend/app/services/openstreetmap_discovery_service.py`,
  `backend/app/services/local_routes_service.py`, related tests;
  [Overpass API](https://wiki.openstreetmap.org/wiki/Overpass_API) and
  [OpenStreetMap copyright/licence](https://www.openstreetmap.org/copyright), last verified
  2026-09-01.

## ADR-009 — Real road-route geometry via open-data routing providers (openrouteservice and OSRM)

- **Status:** Accepted and `[IMPLEMENTED]`.
- **Date:** 2026-09-02.
- **Context:** Previous map implementation displayed a placeholder noting road geometry was not yet
  available. Presenting fake straight-line routes is unacceptable under project policy. Route
  geometry requires actual road-following polylines without introducing paid proprietary dependencies
  like Google Maps Directions or SDKs.
- **Decision:** Implement a provider-neutral route geometry service (`RouteGeometryService`) with
  adapter implementations for both openrouteservice (ORS Directions v2 GeoJSON) and Open Source
  Routing Machine (OSRM driving routing). The service structures road coordinates by day based on
  persisted `TripItinerary` visit orders and `Trip.start_location`. Polylines are cached in memory
  using coordinate fingerprints (`trip_id:day_number:coords_hash`) with a configurable TTL
  (`ROUTE_GEOMETRY_CACHE_TTL_MINUTES`, default 60 min). The Flutter `TripMapScreen` renders real
  road geometry via `PolylineLayer`, updates dynamically with Day 1 / Day 2 filtering, fits camera
  bounds to route waypoints, and gracefully degrades to markers if routing services are unavailable.
- **Consequences:** No proprietary Google Maps SDK or paid routing APIs are introduced. Both hosted
  and self-hosted routing options (ORS and OSRM) are supported via environment configuration.
  `RouteMatrixCache` schema remains preserved for matrix TSP solving without modification.
- **Evidence:** `backend/app/services/route_geometry_service.py`,
  `backend/app/routers/route_geometry.py`, `lib/models/route_geometry.dart`,
  `lib/services/route_geometry_service.dart`, `lib/screens/trip_map/trip_map_screen.dart`,
  `backend/tests/test_route_geometry.py`, `test/trip_map_test.dart`,
  [openrouteservice documentation](https://openrouteservice.org/dev/#/api-docs), and
  [OSRM project](https://project-osrm.org/), verified 2026-09-02.

## ADR-010 — Google OR-Tools VRPTW Solver for Multi-Day Itinerary Optimization

- **Status:** Original OR-Tools integration `[IMPLEMENTED]`; day/window/lock/objective details superseded by ADR-015.
- **Date:** 2026-09-03.
- **Context:** Previous itinerary ordering used a greedy nearest-neighbor heuristic that lacked formal
  constraint handling. Multi-day trips with restricted venue opening hours, varying visit durations,
  lunch breaks, pinned positions, and must-visit rules require formal combinatorial optimization
  to generate feasible, realistic, and optimal travel timetables.
- **Decision:** Implement a multi-vehicle Vehicle Routing Problem with Time Windows (VRPTW) solver
  (`VrptwSolverService`) backed by Google OR-Tools (`ortools.constraint_solver`). Vehicles represent
  trip days ($1 \dots \text{days}$) operating between daily touring hours (`09:00–19:00`) starting and
  ending at the trip start depot. Time windows model opening hours and weekday closures; category heuristics
  model service durations; vehicle break intervals schedule midday lunch (`12:30–14:00`, 60 min);
  pinned slots enforce locked place positions; and disjunctions with scaled drop penalties guarantee
  must-visit place preservation and drop low-priority places first under time budget constraints.
  The optimization response automatically integrates with `RouteGeometryService` to prefetch and
  attach road-following route polylines.
- **Consequences:** `ortools>=9.9.0` is added as a backend dependency. Existing pairwise distance/duration
  estimates in `RouteMatrixCache` are fully reused without schema migration. The solver executes in
  under 100ms for typical trip sizes ($\le 24$ places) and degrades safely with descriptive validation
  errors when constraints are unsatisfiable.
- **Evidence:** `backend/app/services/vrptw_solver_service.py`, `backend/app/services/route_optimization_service.py`,
  `backend/app/routers/route_optimization.py`, `backend/app/schemas/route_optimization.py`,
  `backend/tests/test_vrptw_solver.py`, `backend/tests/test_route_optimization.py`, and
  [Google OR-Tools Routing documentation](https://developers.google.com/optimization/routing/vrptw),
  verified 2026-09-03.

## ADR-011 — Weather-Aware Trip Assistance via Open-Meteo and itinerary-aware advisory engine

- **Status:** Accepted and `[IMPLEMENTED]`.
- **Date:** 2026-09-02.
- **Context:** Travellers need awareness when adverse weather (extreme heat, heavy rain, storms, wind)
  threatens their outdoor touring plans. A generic weather forecast screen is unhelpful and clutters the UI.
  The system must never silently alter an itinerary because of weather. The default user action must
  always be "Continue as planned".
- **Decision:** Implement a provider-neutral `WeatherProvider` protocol with `OpenMeteoWeatherProvider`
  adapter fetching only required variables (temperature, apparent temperature, precipitation, precipitation
  probability, weather code, wind speed/gusts). Forecasts are cached in memory (`WEATHER_CACHE_TTL_MINUTES`,
  default 60 min) without adding database tables. The `WeatherAdvisoryService` applies centralized thresholds
  requiring adverse conditions to persist for $\ge 2$ consecutive hours during touring hours (09:00–18:00)
  and checks for overlap specifically with outdoor-exposed venues identified by a deterministic
  `PlaceEnvironmentClassifier`. Sheltered indoor venues (museums, malls) do not trigger adverse warnings.
  The `WeatherAlternativeService` scores candidate indoor venues matching user preferences, creates
  a non-persisted day rearrangement preview protecting `must_visit` and `is_locked` constraints, and
  transactionally updates the itinerary only when the user explicitly clicks "Apply changes".
  Users can suppress future weather advisories for the trip, stored in `TripPreference`.
- **Consequences:** Open-Meteo free tier has non-commercial restrictions and requires CC BY 4.0 attribution;
  commercial deployment requires a paid customer-endpoint key or self-hosted container.
  Trips outside the 16-day forecast horizon return status `no_forecast_available` without fabricating weather.
  Weather failure degrades safely (`weather_unavailable`) and never disrupts trip or map viewing.
- **Evidence:** `backend/app/core/weather_constants.py`, `backend/app/services/weather_service.py`,
  `backend/app/services/place_environment_classifier.py`, `backend/app/services/weather_advisory_service.py`,
  `backend/app/services/weather_alternative_service.py`, `backend/app/routers/weather_advisories.py`,
  `lib/models/weather_advisory.dart`, `lib/services/weather_advisory_service.dart`,
  `lib/screens/place_discovery/widgets/weather_advisory_card.dart`,
  `backend/tests/test_weather_advisories.py`, `test/weather_advisory_test.dart`,
  [Open-Meteo API docs](https://open-meteo.com/en/docs), and
  [Open-Meteo Terms](https://open-meteo.com/en/terms), verified 2026-09-02.

## ADR-012 — Canonical Multi-Source Place Identity and Provenance Resolution

- **Status:** Accepted and `[IMPLEMENTED]`.
- **Date:** 2026-09-04.
- **Context:** Multiple providers (OpenStreetMap, Audiala seed dataset, Geoapify) provide overlapping POI coverage.
  Without an explicit canonical resolution system, items from different sources duplicate or corrupt canonical fields,
  and provider provenance/licensing is lost.
- **Decision:** Implement `CanonicalPlaceService` as the authoritative resolution layer mapping provider records
  into single canonical `Place` database rows with linked `PlaceSource` provenance. Apply a 4-rule hierarchy:
  (1) Deterministic lookup by `(source, external_place_id)` for idempotency; (2) Shared global identifier (Wikidata QID)
  cross-provider matching; (3) Conservative geographic ($\le 100$m), category-compatible, and tokenized name variant
  matching with strict disqualifiers (e.g. gates, directional terms); (4) New canonical `Place` creation.
  Attribution and licensing (`ODbL-1.0` for OSM, `CC BY 4.0` for Audiala) are preserved on `PlaceSource`.
- **Consequences:** Prevents duplicate places in database while preserving provider metadata and legal attribution.
  Downstream presentation deduplication (`deduplicate_places`) handles unresolved cosmetic variations and caps multi-outlet chains.
- **Evidence:** `backend/app/services/canonical_place_service.py`, `backend/tests/test_canonical_place_service.py`,
  `docs/DATA_MODEL.md`, `docs/ARCHITECTURE.md`.

## ADR-013 — Progressive POI Prefetch and Cache-First Live Discovery Reliability

- **Status:** Accepted and `[IMPLEMENTED]`.
- **Date:** 2026-09-04.
- **Context:** Live Overpass/OSM queries on the critical discovery path frequently timed out or returned HTTP 504
  gateway errors, causing blocking error screens for users.
- **Decision:** Implement 3-tier cache semantics (`FRESH` $\le 24$h, `STALE_USABLE` $\le 168$h, `MISSING`) with
  stale-while-revalidate background refresh. Introduce non-blocking progressive prefetch: broad shallow prefetch
  (`stage=shallow`) upon destination confirmation and targeted prefetch (`stage=targeted`) upon trip purpose confirmation.
  Implement a provider hierarchy: Cached DB $\to$ `GeoapifyPlacesProvider` $\to$ `AudialaPlacesProvider` $\to$ `OpenStreetMapPlacesService`.
  Protect Overpass with an in-memory circuit breaker (`OVERPASS_CIRCUIT_BREAKER_THRESHOLD=3`, `OVERPASS_CIRCUIT_BREAKER_COOLDOWN_SECONDS=60s`).
- **Consequences:** Eliminates cold discovery loading delays. Discovery queries serve cached places in under 50ms.
  External provider failures degrade gracefully to fallback providers or stale usable cache without breaking user journeys.
- **Evidence:** `backend/app/services/city_place_prefetch_service.py`, `backend/app/services/provider_circuit_breaker.py`,
  `backend/app/services/geoapify_places_provider.py`, `backend/tests/test_live_discovery_reliability.py`,
  `docs/live_discovery_reliability.md`.

## ADR-014 — Core Trip Flow Hardening (Logical Day Invariant, Destination-Scoped Manual Search, Frame-1 Progressive Map)

- **Status:** Accepted and `[IMPLEMENTED]`.
- **Date:** 2026-09-05.
- **Context:** Real manual testing revealed three core trip flow defects: (1) Days with 0 stops disappeared in multi-day trips
  (e.g. Day 2 missing from a 3-day trip); (2) Manual place search was a placeholder stub; (3) Interactive map took seconds
  to open behind a full-screen blocking spinner while recalculating routes.
- **Decision:**
  1. **Logical Day Invariant**: Canonical logical day sequence is $\{1 \dots N\}$ derived from trip dates. `RouteOptimizationRead`
     returns explicit `total_days=trip.days`. Models normalize sparse schedules to empty lists (`[]`), rendering clear empty-day
     cards in the itinerary and non-empty day selections in map filters.
  2. **Manual Place Search**: Implement 350ms debounced destination-scoped search (`GET /cities/{city_id}/places/search`) querying
     local places and concurrent Geoapify Autocomplete within 50km destination radius, resolving candidates through `CanonicalPlaceService`
     (`POST /cities/{city_id}/places/resolve`), preventing duplicates, and marking places route-eligible.
  3. **Progressive Map Performance**: Pre-pass known trip state (`initialStartLocation`, `initialSavedPlaces`, `initialOptimizedRoute`,
     `initialRouteGeometry`, `initialDurationDays`) to `TripMapScreen`. Render base map and markers immediately on Frame 1 ($12-25\text{ ms}$).
     Fetch route geometry asynchronously in background with a non-blocking indicator, and reuse pre-calculated route state (0 network calls on open).
- **Consequences:** Trips of any duration ($1, 2, 3, 5, 7$ days) preserve full day integrity. Map opens instantly. Users can manually
  search and add attractions with guaranteed route participation.
- **Evidence:** `backend/app/services/route_optimization_service.py`, `backend/app/routers/places.py`, `lib/models/optimized_route.dart`,
  `lib/screens/place_discovery/place_discovery_screen.dart`, `lib/screens/trip_map/trip_map_screen.dart`,
  `backend/tests/test_core_trip_flow_hardening.py`, `test/core_trip_flow_hardening_test.dart`, `docs/core_trip_flow_hardening.md`.

## ADR-015 — TripDay-aware, time-feasible partial itinerary generation

- **Status:** `[IMPLEMENTED]` (planner regressions pass; unrelated repository failures documented in the implementation report).
- **Date:** 2026-09-07.
- **Decision:** Extend the existing VRPTW solver and matrix/depot architecture. Each usable
  non-REST TripDay maps to a route with its own time window and original output day number.
  Native vehicle-variable domains enforce day locks. Disjoint route time bands preserve exact
  weekday interval unions and visit completion before closing without duplicating selections.
  UNKNOWN hours remain schedulable and explicitly unverified. Preserve existing duration and
  priority models, strengthen lock retention, remove hard priority ordering and return structured
  unscheduled results rather than failing overpacked trips. Balance softly against individual
  time capacities, with no place-count quotas or automatic recommendations.
- **Consequences:** Optimization and full-trip preview load the same persisted constraints.
  Additive response/Flutter models carry unscheduled reasons; scheduled rows alone persist.
  Existing return-depot assumption (zero return leg), five-second search budget, and matrix
  caching are retained. Selection cap rises from 24 to 50. No schema migration or provider call
  is introduced for opening hours. Exact global optimality and durable result snapshots remain
  outside this phase.
- **Evidence:** `backend/tests/test_day_aware_planner.py`, route optimization integration tests,
  `test/day_aware_planner_test.dart`, [implementation report](PLANNER_IMPLEMENTATION.md), and
  [official OR-Tools routing API reference](https://or-tools.github.io/docs/python/classortools_1_1constraint__solver_1_1pywrapcp_1_1RoutingModel.html),
  verified 2026-09-07 against local OR-Tools 9.15.6755. Vehicle-domain removal avoids the
  installed Windows SetAllowedVehiclesForIndex Python span-binding error.
# ADR-016 — Core trip flow reliability and persisted map reads

- **Status:** Accepted and `[IMPLEMENTED]` in repository tests.
- **Date:** 2026-09-07.
- **Context:** Cross-layer verification found that deep map loading could regenerate an itinerary, map
  mutations did not update the parent itinerary, TripDay dates and REST exclusions were missing from the
  POI sheet, and UI status actions did not match backend move rules.
- **Decision:** Treat explicit optimization as a planning action. Map entry reads the persisted itinerary,
  POI presentation consumes existing in-memory state, TripDay data determines weekday hours and move
  targets, and map mutations publish the backend response to the parent screen. Enforce COMPLETED and
  SKIPPED as terminal statuses while permitting MISSED to become SKIPPED or move through partial replanning.
- **Consequences:** Viewing a map no longer mutates the itinerary or refreshes its matrix. UI and API
  lifecycle rules agree, REST targets are removed before interaction, and parent/map state converges on the
  same server response. Route geometry may still use its configured provider when geometry is absent.
- **Evidence:** `backend/tests/test_trip_flow_e2e.py`, `backend/tests/test_partial_replanning.py`,
  `test/trip_map_test.dart`, `test/poi_bottom_sheet_test.dart`, and
  [`CORE_TRIP_FLOW_RELIABILITY.md`](CORE_TRIP_FLOW_RELIABILITY.md).
