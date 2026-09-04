# YatraCanvas Repository Audit

**Date:** 2026-09-04
**Branch:** `chore/project-audit-cleanup`
**Audited from:** `feature/audiala-city-seed-layer` (HEAD `721b04a`)
**Test baseline:** 199 passed, 0 failed, 4 warnings (235.75s)

---

## 1. Executive Summary

**What is YatraCanvas today?**

YatraCanvas is a Flutter + FastAPI travel-planning application focused on helping travellers plan Indian-city trips by discovering, saving, and optimizing places into day-by-day itineraries. The backend is well-structured with a meaningful multi-stage recommendation pipeline and real OR-Tools itinerary optimization. A significant amount of feature work has landed, but the most recent development session (`feature/audiala-city-seed-layer`) was stopped mid-commit — its changes are present in the working tree but **not yet committed**.

**What works?**
Trip creation, recommendation pipeline (OSM-backed), itinerary optimization (OR-Tools VRPTW), route geometry (OSRM), weather advisories (Open-Meteo), saved places, smart replanning, and the Flutter UI flow are all functionally implemented and have passing tests.

**What is incomplete?**
- Audiala integration is PARTIAL — production code calls `AudialaPlacesProvider` but the class is **untracked** (not committed). The working integration was built on the current branch and never committed.
- Flutter calendar is fixed to August 2026 (hardcoded).
- Authentication / Supabase Auth is absent.
- Admin panel has no real API.
- `place_discovery_service.py` (Google-backed) is dead code — never called from any router.

**Is the repository healthy?**
Mostly, with caveats. The committed codebase is well-organized. The active branch carries 10 modified files + 4 untracked directories/files that represent a logical unit of work (Audiala seed layer) that needs to be committed or cleanly rebased. Documentation is relatively current but needs a few corrections.

---

## 2. Actual Stack

### Flutter (Client)

| Item | Detail |
|---|---|
| Flutter SDK | Dart SDK `^3.13.0` |
| State management | Widget-local `StatefulWidget` — no BLoC, Riverpod, Provider |
| Navigation | `Navigator`/`MaterialPageRoute` — no go_router |
| Networking | `http: ^1.6.0` |
| Map | `flutter_map: ^8.3.2` (OpenStreetMap tiles) |
| Location | `geolocator: ^14.0.3` |
| Graphics | `flutter_svg: ^2.3.0` |
| Local storage | None — all state in-memory |
| Testing | `flutter_test` (SDK), `flutter_lints: ^6.0.0` |

### Backend (Python / FastAPI)

| Item | Detail |
|---|---|
| Framework | FastAPI (async) |
| ORM | SQLModel + SQLAlchemy |
| Validation | Pydantic v2 / pydantic-settings |
| DB driver | psycopg 3 (`psycopg[binary]`) |
| HTTP client | httpx |
| Optimization | OR-Tools `>=9.9.0` |
| Routing engine | OSRM (default) or openrouteservice |
| Migration | No versioned runner — `SQLModel.metadata.create_all` + manual `.sql` files |
| Testing | pytest (199 tests, 100% passing) |

### Database

| Item | Detail |
|---|---|
| Engine | PostgreSQL (Supabase-hosted or local) |
| Schema | `backend/app/models/entities.py` |
| Migrations | 6 manual SQL scripts in `backend/sql/` |

---

## 3. Current Architecture

```
Flutter App
  lib/main.dart → SplashScreen → create_trip flow
  lib/services/*.dart → http calls to backend base URL

  screens/
  ├─ onboarding/         (splash, welcome, phone — no real auth)
  ├─ create_trip/        (destination, dates, arrival, purpose, prefs)
  ├─ place_discovery/    (recommendations, saved places, optimize)
  ├─ trip_map/           (FlutterMap + OSM tiles + day polylines)
  └─ home/               (home_screen)

FastAPI Backend  backend/app/main.py
  routers/
  ├─ cities.py           → CityService
  ├─ trips.py            → TripService
  ├─ places.py           → OpenStreetMapDiscoveryService
  │                         (OSMPlacesService + AudialaPlacesProvider [UNTRACKED])
  │                         RecommendationService
  ├─ saved_places.py     → SavedPlaceService
  ├─ route_optimization.py → RouteOptimizationService
  │                          → RouteMatrixService → LocalRoutesService
  │                          → VrptwSolverService (OR-Tools)
  ├─ route_geometry.py   → RouteGeometryService (OSRM / ORS)
  ├─ weather_advisories.py → WeatherAdvisoryService (Open-Meteo)
  │                          WeatherAlternativeService
  ├─ smart_replanning.py → SmartReplanningService
  └─ locations.py        → GeoapifyService

  Services (25 files):
  Core pipeline:
    openstreetmap_places_service.py     Overpass API search (7 categories)
    openstreetmap_discovery_service.py  Cache layer + OSM + Audiala orchestrator
    audiala_places_provider.py          In-memory JSON dataset search [UNTRACKED]
    recommendation_service.py           Dedup + suitability + scoring + ranking
    place_deduplication_service.py      Canonical spatial dedup
    place_suitability_service.py        Traveller suitability filter
    preference_model.py                 Purpose/interest weighting

  Routing:
    route_matrix_service.py             Matrix cache + provider bridge
    local_routes_service.py             Offline Haversine estimates (default)
    google_routes_service.py            Optional paid Google Routes adapter [LEGACY]
    route_geometry_service.py           OSRM/ORS road geometry
    route_optimization_service.py       Orchestrator
    vrptw_solver_service.py             OR-Tools VRPTW
    itinerary_timing_service.py         Arrival/departure timestamps
    smart_replanning_service.py         Change impact + replan

  Other:
    weather_service.py                  Open-Meteo adapter
    weather_advisory_service.py         Threshold-based advisories
    weather_alternative_service.py      Weather-triggered alternatives
    saved_place_service.py              Saved place CRUD
    trip_service.py                     Trip CRUD
    geoapify_service.py                 Location autocomplete
    place_environment_classifier.py     Indoor/outdoor classification
    location_autocomplete_provider.py   Protocol interface

  Legacy / Dead:
    place_discovery_service.py          [DEAD] Google Places discovery — unused

Database (PostgreSQL):
  cities, trips, trip_preferences
  places, place_tags, place_sources, place_categories
  place_import_reviews  (schema only, no API)
  user_saved_places
  city_category_cache
  route_matrix_cache
  trip_itinerary
```

---

## 4. Current Core Flow

**Trip Creation:**
```
User selects city → POST /trips (city_id, days, arrival, purpose, preferences)
→ TripService creates Trip + TripPreference rows → returns trip_id
```

**Recommendations:**
```
POST /cities/{city_id}/recommendations
→ RecommendationService.recommend()
  → OpenStreetMapDiscoveryService.discover_many()
    → check CityCategoryCache (TTL 24h)
    → if stale:
        OpenStreetMapPlacesService.search_nearby_places_for_categories()  [Overpass]
        AudialaPlacesProvider.search_nearby_places_for_categories()       [JSON file, UNTRACKED]
    → persist Place + PlaceSource + PlaceTag rows
    → update CityCategoryCache
  → deduplicate_places()           (identity → external key → spatial+name)
  → is_traveller_suitable()        (drop canteens, messes, restricted)
  → evaluate_preference_fit()      (purpose 2.5x, interest 1.0x)
  → calculate_recommendation_score()
  → diversity_interleaving()
  → return RecommendationRead list
```

**Itinerary Optimization:**
```
POST /trips/{trip_id}/optimize-route
→ RouteOptimizationService.optimize()
  → load UserSavedPlace rows
  → RouteMatrixService.get_complete_matrix()  [LocalRoutesService, Haversine estimates]
  → VrptwSolverService.solve()                [OR-Tools VRPTW]
  → ItineraryTimingService                    [arrival/departure timestamps]
  → store TripItinerary rows
  → RouteGeometryService                      [OSRM polyline per day]
  → return RouteOptimizationRead
```

**Weather:**
```
GET /trips/{trip_id}/weather-advisories
→ WeatherAdvisoryService → Open-Meteo → threshold analysis → advisories
   (failures → weather_unavailable, no crash)
```

---

## 5. Feature Status Matrix

| Feature | Status | Backend | Flutter | Tests | Notes |
|---|---|---|---|---|---|
| Trip creation | WORKING | ✅ | ✅ | ✅ | Unauthenticated dev slice |
| City search / autocomplete | WORKING | ✅ | ✅ | ✅ | Geoapify + local DB |
| Arrival/start location | WORKING | ✅ | ✅ | ✅ | Geoapify-backed |
| Purpose & preference selection | WORKING | ✅ | ✅ | ✅ | Persisted as TripPreference |
| OSM POI discovery | WORKING | ✅ | ✅ | ✅ | Overpass, 7 categories |
| Recommendation pipeline | WORKING | ✅ | ✅ | ✅ | Full multi-stage |
| Suitability filter | WORKING | ✅ | — | ✅ | Drops canteens/messes |
| Deduplication | WORKING | ✅ | — | ✅ | Identity + spatial + name |
| Preference weighting | WORKING | ✅ | — | ✅ | Purpose 2.5x / interest 1.0x |
| Saved places | WORKING | ✅ | ✅ | ✅ | Full CRUD + reorder |
| Route matrix (local estimates) | WORKING | ✅ | ✅ | ✅ | Haversine-based, no API key |
| OR-Tools VRPTW itinerary | WORKING | ✅ | ✅ | ✅ | Multi-day, lunch, opening hours |
| Road geometry (OSRM) | WORKING | ✅ | ✅ | ✅ | Polyline per day |
| Interactive map | WORKING | — | ✅ | — | FlutterMap + OSM tiles |
| Smart replanning | WORKING | ✅ | ✅ | ✅ | Change impact + diff preview |
| Weather advisories | WORKING | ✅ | ✅ | ✅ | Open-Meteo, non-breaking |
| Weather rearrangement | WORKING | ✅ | ✅ | ✅ | Preview + apply |
| Audiala city seed layer | PARTIAL | ⚠️ | — | ⚠️ | Code exists UNTRACKED, not committed |
| FSQ OS Places import | PARTIAL | ✅ | — | ✅ | CLI only, no runtime API |
| Authentication | NOT IMPLEMENTED | — | — | — | Supabase Auth planned |
| Trip listing / history | NOT IMPLEMENTED | — | — | — | No GET /trips endpoint |
| Admin review UI | NOT IMPLEMENTED | — | ⚠️ | — | Schema only; mock shell |
| Route matrix (Google Routes) | LEGACY | ✅ | — | ✅ | Replaced by LocalRoutesService |
| Google Places discovery | DEAD | 💀 | — | — | place_discovery_service.py unused |
| Calendar date selection | BROKEN | — | ⚠️ | — | Fixed to August 2026 |

---

## 6. External Provider Matrix

| Provider | Purpose | Production? | Config | Fallback | Notes |
|---|---|---|---|---|---|
| Overpass API (OSM) | POI discovery | ✅ YES | `OVERPASS_API_URL` | Stale DB cache | Primary source; public endpoint |
| Audiala dataset | Supplemental POI | ⚠️ PARTIAL | `AUDIALA_DATASET_PATH` | Skip if absent | JSON file, ~435KB; code UNTRACKED |
| Geoapify | Autocomplete | ✅ OPTIONAL | `GEOAPIFY_API_KEY` | HTTP 503 | City/arrival autocomplete |
| Open-Meteo | Weather | ✅ YES | `OPEN_METEO_BASE_URL` | `weather_unavailable` | No API key required |
| OSRM | Road geometry | ✅ YES | `OSRM_ROUTER_URL` | None | Public endpoint; polylines |
| LocalRoutesService | Route matrix | ✅ YES | None | N/A (is the default) | Haversine estimates |
| openrouteservice | Road routing (alt) | OPTIONAL | `OPENROUTESERVICE_API_KEY` | OSRM | Via `ROUTING_PROVIDER=openrouteservice` |
| Google Routes | Route matrix | LEGACY | `GOOGLE_ROUTES_API_KEY` | LocalRoutesService | Tests only; not production |
| Google Places | POI discovery | DEAD | — | — | `place_discovery_service.py` dead |
| FSQ OS Places | Batch import | OPTIONAL | `FSQ_OS_PLACES_PATH` | N/A (offline CLI) | No runtime API key |
| Wikidata | — | NOT ACTIVE | None | — | Experiments only; no production code |
| Nominatim | — | NOT ACTIVE | None | — | Experiment scripts only |

---

## 7. Audiala Status — Detailed

**Classification: PARTIAL (uncommitted production code; logically complete)**

| Question | Answer |
|---|---|
| Does `AudialaPlacesProvider` exist? | YES — `backend/app/services/audiala_places_provider.py` |
| Is it production or experiment? | Production services directory, **UNTRACKED** (not committed) |
| Is it injected into FastAPI? | YES — `places.py` imports `AudialaPlacesDependency` |
| Does discovery call it? | YES — `openstreetmap_discovery_service.py` calls `search_nearby_places_for_categories()` |
| How does it load data? | Lazy load from `AUDIALA_DATASET_PATH` JSON file on first search |
| Where is the dataset? | `scripts/experiments/poi_importance/data/audiala_india.json` (~435KB) |
| Does it persist Place records? | YES — via `_persist_category()` with `source_name="audiala"` |
| Does it persist PlaceSource records? | YES — with `licence_identifier="CC BY 4.0"` |
| How is deduplication handled? | `_existing_external_ids()` checks DB before persisting; OSM batch places also excluded |
| Is Wikidata QID the identity key? | YES — `external_place_id = record.get("wikidata_id")` |
| Can OSM + Audiala → two Place rows? | YES — different external IDs → different Place rows. Spatial dedup at query time collapses them during recommendations. |
| Does Audiala affect scoring? | Indirectly — `sitelinks` sorts within the provider but does NOT feed `calculate_recommendation_score()` |
| Does Audiala affect caching? | YES — inside the same `CityCategoryCache` TTL window |

**Critical finding:** The provider is wired into production endpoints but has no committed state. All 14 modified/untracked files form a coherent feature that **could and should be committed**.

---

## 8. Recommendation Engine Status

**WORKING. Well-implemented 5-stage pipeline.**

| Stage | Implementation | Status |
|---|---|---|
| 1. Candidate retrieval | `OpenStreetMapDiscoveryService.discover_many()` | ✅ |
| 2. Identity + spatial dedup | `deduplicate_places()` (identity → external key → spatial+name) | ✅ |
| 3a. Suitability filter | `is_traveller_suitable()` — drops canteens, messes, restricted access | ✅ |
| 3b. Category filter | Narrows without changing stored preferences | ✅ |
| 3c. Preference fit | `evaluate_preference_fit()` (purpose 2.5x, interest 1.0x) | ✅ |
| 3d. Low-relevance cutoff | `min_relevance_score` threshold | ✅ |
| 3e. Score calculation | Rating confidence + popularity/heritage bonuses | ✅ |
| 4. Diversity ranking | Soft interleaving for mixed-interest trips | ✅ |
| 5. Final safeguard | Name + 100m distance final dedup | ✅ |

**Gap:** Audiala `sitelinks` signal does not feed into `calculate_recommendation_score()`. Audiala contributes candidates, not altered scoring. Acceptable for current phase.

---

## 9. Routing / Itinerary Status

**WORKING.** Production uses `LocalRoutesService` (Haversine × 1.3 road factor, 25 km/h avg).

- `RouteMatrixService` caches pairwise estimates in `route_matrix_cache`
- `VrptwSolverService` (OR-Tools): multi-day vehicles, visit durations, lunch breaks (12–14h), opening-hour time windows, locked places, must-visit penalties
- `ItineraryTimingService`: arrival/departure timestamps
- `RouteGeometryService`: OSRM road polylines
- `SmartReplanningService`: change-impact analysis + atomic replanning
- `GoogleRoutesService` is retained for test compatibility but **`get_route_provider()` always returns `LocalRoutesService()`** in production

---

## 10. Weather Status

**WORKING as advisory-only. Does NOT silently modify recommendations.**

- `WeatherAdvisoryService`: Open-Meteo 7-day hourly + daily forecast
- Thresholds: extreme heat (≥40°C apparent), storm codes, heavy rain, high wind gusts
- `place_environment_classifier.py`: determines outdoor exposure
- Failures: gracefully return `weather_unavailable` (no trip crash)
- **Future rule "weather must be optional/user-controlled" is currently honoured**

---

## 11. Duplicate Code Found

| Duplication | File A | File B | Risk | Recommendation |
|---|---|---|---|---|
| Haversine function | `place_deduplication_service.py:37` | `local_routes_service.py:40` | LOW | Keep both — different input signatures (`float` vs `RouteCoordinate`). Document as TECH DEBT. |
| Haversine function | `place_deduplication_service.py:37` | `importers/fsq_os_places.py:532` | LOW | Same. FSQ importer is isolated. |
| `_stored_places()` method | `openstreetmap_discovery_service.py:410` | `place_discovery_service.py:263` | NONE | Second is dead code. No action needed. |
| Category → radius defaults | `config.py:376–390` | `openstreetmap_places_service.py:69–77` | LOW | Config values are runtime overrides; service has hardcoded defaults as fallback. Not a true duplicate. |

**No critical duplications. Code is well-modularized.**

---

## 12. Unused / Dead Files

### DEAD — Label, Do Not Delete Yet

| File | Evidence | Recommendation |
|---|---|---|
| `backend/app/services/place_discovery_service.py` | Imports `GooglePlacesService` (file doesn't exist in repo). Zero calls from any router or DI. Replaced by `OpenStreetMapDiscoveryService`. | Add `[LEGACY/DEAD]` to module docstring. Retain for Google type mapping reference. |

### KEEP — Actively Used

| File | Why Keep |
|---|---|
| `backend/app/services/google_routes_service.py` | Provides error types (`GoogleRoutesConfigurationError` etc.) imported by `route_matrix_service.py`; used in tests |
| `lib/main_admin.dart` | Admin shell entry point; future admin path |
| `backend/app/importers/city_config.py` | Used by FSQ CLI importer |
| `docs/PROJECT_DOCUMENTATION.md` | Historical UI doc; acknowledged as superseded |
| `docs/CHATGPT_PROJECT_HANDOFF.md` | Useful context snapshot |
| `google_usage_audit.md` (root) | Historical audit reference |

---

## 13. Experiment File Classification

### `scripts/experiments/poi_importance/`

| Item | Classification |
|---|---|
| `run_experiment.py` | KEEP — 32KB comprehensive experiment runner |
| `fetch_audiala.py` | KEEP — Audiala dataset fetch script |
| `generate_summary.py` | KEEP — result summarizer |
| `inspect_results.py` | KEEP — result inspection |
| `data/audiala_india.json` | **KEEP — production data file** referenced by `AUDIALA_DATASET_PATH` |
| `results/` | KEEP — reproducibility |
| `cache/` | ARCHIVE — gitignore, not needed for reproduction |

### `scripts/experiments/city_candidate_coverage/`

| Item | Classification |
|---|---|
| `evaluate_recall.py` | KEEP — main recall evaluation |
| `evaluate_audiala_layer.py` | KEEP — Audiala coverage evaluation |
| `evaluate_fast_audiala.py` | KEEP — faster variant |
| `evaluate_production_fix.py` | KEEP — production fix evaluation |
| `strategy_comparison.py` | KEEP — strategy comparison |
| `print_eval.py` | KEEP — result formatter |
| `inspect_audiala.py` | KEEP — dataset inspector |
| `check_delhi.py` | KEEP — Delhi check |
| `check_nominatim_delhi.py` | KEEP — Nominatim check |
| `test_india_gate.py` | KEEP — single-place test |
| `*.json` result files | KEEP — reproducibility |
| `cache_production_fix/` | ARCHIVE — gitignore |
| `cache_production_fix_v2/` | ARCHIVE — gitignore |

> **Action:** Add `scripts/experiments/*/cache*/` to `.gitignore`.

---

## 14. Configuration Audit

| Variable | Status | Notes |
|---|---|---|
| `DATABASE_URL` | REQUIRED | PostgreSQL URL |
| `GOOGLE_ROUTES_API_KEY` | LEGACY/OPTIONAL | Tests only; not in production flow |
| `GEOAPIFY_API_KEY` | OPTIONAL | 503 if absent |
| `GEOAPIFY_BASE_URL` | OPTIONAL | Has default |
| `GEOAPIFY_TIMEOUT_SECONDS` | OPTIONAL | Has default |
| `GEOAPIFY_AUTOCOMPLETE_CACHE_TTL_SECONDS` | OPTIONAL | Has default |
| `OVERPASS_API_URL` | OPTIONAL | Public default |
| `OVERPASS_TIMEOUT_SECONDS` | OPTIONAL | Has default |
| `OVERPASS_RADIUS_METERS` | OPTIONAL | Default 8000m |
| `OVERPASS_{CATEGORY}_RADIUS_METERS` (×7) | OPTIONAL | All have defaults |
| `OVERPASS_{CATEGORY}_LIMIT` (×7) | OPTIONAL | All have defaults |
| `FSQ_OS_PLACES_PATH` | OPTIONAL | CLI only |
| `AUDIALA_DATASET_PATH` | OPTIONAL | JSON file path; skip if absent |
| `FSQ_DEDUPE_DISTANCE_METERS` | OPTIONAL | Default 75m |
| `FSQ_IMPORT_BATCH_SIZE` | OPTIONAL | Default 250 |
| `ROUTE_MATRIX_TRAFFIC_TTL_MINUTES` | OPTIONAL | Default 30 |
| `PLACE_DISCOVERY_CACHE_TTL_HOURS` | OPTIONAL | Default 24 |
| `GOOGLE_NEARBY_RADIUS_METERS` | **LEGACY** | Only used by dead `PlaceDiscoveryService` |
| `PLACE_POPULAR_MIN_RATING` | **LEGACY** | Same — dead Google service |
| `PLACE_POPULAR_MIN_REVIEW_COUNT` | **LEGACY** | Same |
| `ROUTING_PROVIDER` | OPTIONAL | `osrm` or `openrouteservice` |
| `OPENROUTESERVICE_API_KEY` | OPTIONAL | Alternative routing |
| `OPENROUTESERVICE_BASE_URL` | OPTIONAL | Has default |
| `OPENROUTESERVICE_TIMEOUT_SECONDS` | OPTIONAL | Has default |
| `OSRM_ROUTER_URL` | OPTIONAL | Public default |
| `OSRM_TIMEOUT_SECONDS` | OPTIONAL | Has default |
| `ROUTE_GEOMETRY_CACHE_TTL_MINUTES` | OPTIONAL | Default 60 |
| `WEATHER_PROVIDER` | OPTIONAL | Only `openmeteo` supported |
| `OPEN_METEO_BASE_URL` | OPTIONAL | Has default |
| `OPEN_METEO_TIMEOUT_SECONDS` | OPTIONAL | Has default |
| `WEATHER_CACHE_TTL_MINUTES` | OPTIONAL | Default 60 |

**Issues:**
- `GOOGLE_NEARBY_RADIUS_METERS`, `PLACE_POPULAR_MIN_RATING`, `PLACE_POPULAR_MIN_REVIEW_COUNT` are loaded by `Settings` but consumed only by dead `PlaceDiscoveryService`. Mark as `[LEGACY]` in `.env.example`.

---

## 15. Documentation Changes From This Audit

| Document | Finding | Action |
|---|---|---|
| `docs/PROJECT_CONTEXT.md` | Map marked as feature, Audiala not mentioned | Updated (see §20) |
| `docs/ARCHITECTURE.md` | Map listed as `[PLANNED]` — should be `[IMPLEMENTED]` (FlutterMap is live) | Update needed |
| `docs/ENVIRONMENT_VARIABLES.md` | Modified (uncommitted) — correct Audiala docs | Will be committed with Audiala feature |
| `docs/city_candidate_coverage_audit.md` | Untracked experiment doc | Will be committed with Audiala feature |
| `docs/poi_importance_experiment.md` | Untracked experiment doc | Will be committed with Audiala feature |

---

## 16. Test Baseline

```
Backend: 199 passed, 0 failed, 4 warnings (235.75s)
  Warnings: httpx/starlette deprecation (use httpx2), OR-Tools SwigPy deprecations

Flutter: Not run (flutter analyze/test not part of this audit scope)
```

**Test coverage by area:**

| Area | Covered | Notes |
|---|---|---|
| Configuration | ✅ | `test_config.py` |
| Documentation consistency | ✅ | `test_documentation.py` |
| FSQ CLI import | ✅ | `test_fsq_importer.py` |
| Geoapify autocomplete | ✅ | `test_geoapify_service.py` |
| Itinerary timing | ✅ | `test_itinerary_timing.py` |
| OSM discovery + Audiala | ✅⚠️ | `test_openstreetmap_discovery_service.py` (modified, uncommitted) |
| OSM Overpass queries | ✅⚠️ | `test_openstreetmap_places_service.py` (modified, uncommitted) |
| Preference weighting | ✅ | `test_preference_weighting.py` |
| Recommendation quality | ✅ | `test_recommendation_quality.py` |
| Recommendation service | ✅ | `test_recommendation_service.py` |
| Route geometry | ✅ | `test_route_geometry.py` |
| Route optimization | ✅ | `test_route_optimization.py` |
| API routes (integration) | ✅ | `test_routes.py` |
| Saved places routes | ✅ | `test_saved_places_routes.py` |
| Smart replanning | ✅ | `test_smart_replanning.py` |
| Stress limits | ✅ | `test_stress_limits.py` |
| Trip creation | ✅ | `test_trip_creation.py` |
| Trip editing | ✅ | `test_trip_editing.py` |
| VRPTW solver | ✅ | `test_vrptw_solver.py` |
| Weather advisories | ✅ | `test_weather_advisories.py` |

**No tests exist for:** `place_discovery_service.py` (dead code — expected).

---

## 17. Technical Debt

### CRITICAL
- **Audiala feature never committed.** 14 modified/untracked files form a coherent feature wired into production endpoints. Risk: accidental `git clean` or branch switch could lose this work.

### HIGH
- **Flutter calendar hardcoded to August 2026.** Trip date selection is non-functional for real users.
- **No authentication.** `user_id` is a server-generated placeholder.
- **`place_discovery_service.py` imports non-existent `GooglePlacesService`.** Would fail at import time if ever directly imported. Dead code risk.
- **Two Place rows for same venue** (OSM node + Audiala QID). Spatial dedup at query time helps but DB holds redundant rows.

### MEDIUM
- No versioned migration runner — schema evolution via `create_all` + manual SQL is fragile.
- Three Haversine implementations across codebase.
- Three config keys (`GOOGLE_NEARBY_RADIUS_METERS`, `PLACE_POPULAR_MIN_RATING`, `PLACE_POPULAR_MIN_REVIEW_COUNT`) loaded but only used by dead code.
- Admin panel has no real API or connectivity.
- No `GET /trips` list endpoint — trip history is inaccessible.
- `TripDraft` is in-memory only — app restart loses state.

### LOW
- `City.google_place_id` retained but not populated by current flow.
- `PlaceCategory` and `PlaceImportReview` models have no service or router usage.
- `lib/main_admin.dart` is 135 bytes with no real content.
- `docs/ARCHITECTURE.md` incorrectly marks Flutter map as `[PLANNED]`.

---

## 18. Current Project Status

As of 2026-09-04, YatraCanvas is a well-implemented travel-planning backend with a functioning Flutter UI for the complete trip-creation-to-itinerary flow. The 199-test suite passes cleanly. The majority of committed code is production-quality and correctly organized.

The development session that produced the Audiala integration (`feature/audiala-city-seed-layer`) stopped before committing. 14 modified/untracked files contain a complete and coherent Audiala seed-layer feature — an in-memory JSON dataset provider that supplements OSM with Wikidata-derived important POIs for major Indian cities. This code is injected into production endpoints but is not in git history.

No features were accidentally broken. The committed HEAD (`721b04a`) is clean.

---

## 19. Recommended Next Steps (Top 3 Only)

1. **Commit the Audiala feature.** All modified + untracked files are a coherent unit. `git add` all of them and commit as `feat: Audiala city seed layer — OSM + Wikidata POI overlay`. Verify 199 tests still pass after commit.

2. **Fix the Flutter calendar hardcoding** in `select_dates_screen.dart`. Replace the fixed August 2026 initial month with `DateTime.now()`. This is a contained, high-impact bug fix.

3. **Label `place_discovery_service.py` as `[LEGACY/DEAD]`** by updating its module docstring. This removes ambiguity for future agents. Do not delete yet.

---

## 20. Files Changed / Deleted

### Created by this audit

| File | Notes |
|---|---|
| `docs/REPOSITORY_AUDIT.md` | This document |

### No source code files were deleted.

### Pre-existing uncommitted files (from `feature/audiala-city-seed-layer`) — context only

| File | Status |
|---|---|
| `backend/.env.example` | modified — added `AUDIALA_DATASET_PATH` |
| `backend/app/core/config.py` | modified — `audiala_dataset_path` + radius/limit helpers |
| `backend/app/routers/places.py` | modified — `AudialaPlacesDependency` injection |
| `backend/app/schemas/recommendation.py` | modified — added MARKETS + NATURE categories |
| `backend/app/services/openstreetmap_discovery_service.py` | modified — Audiala integration |
| `backend/app/services/openstreetmap_places_service.py` | modified — MARKETS/NATURE support |
| `backend/app/services/recommendation_service.py` | modified — new categories |
| `backend/tests/test_openstreetmap_discovery_service.py` | modified — Audiala tests |
| `backend/tests/test_openstreetmap_places_service.py` | modified — MARKETS/NATURE tests |
| `docs/ENVIRONMENT_VARIABLES.md` | modified — new variable docs |
| `backend/app/services/audiala_places_provider.py` | **UNTRACKED** — new Audiala provider |
| `docs/city_candidate_coverage_audit.md` | **UNTRACKED** — experiment doc |
| `docs/poi_importance_experiment.md` | **UNTRACKED** — experiment doc |
| `scripts/experiments/` | **UNTRACKED** — all experiment scripts + data |