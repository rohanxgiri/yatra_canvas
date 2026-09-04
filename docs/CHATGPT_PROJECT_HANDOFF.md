# YatraCanvas Complete ChatGPT Project Handoff

Last reviewed: 2026-09-04
LAST VERIFIED AGAINST REPOSITORY: 2026-09-04

> **Status Notice:** This handoff summarizes the state of YatraCanvas as of September 4, 2026.
> The primary provider stack is 100% provider-neutral: OpenStreetMap/Overpass for place discovery,
> Audiala as a secondary seed layer, Geoapify for autocomplete, local coordinate estimates for route
> matrices, Google OR-Tools for multi-day VRPTW scheduling, OSRM for road geometry, FlutterMap for
> map display, and Open-Meteo for weather advisories. Google Places and Routes are legacy `[DEPRECATED]`
> adapters not required by normal flows.
> 
> When working in the codebase, the modular documents under `docs/` are authoritative.

---

## How to Use This File

Upload this file to a new ChatGPT or AI assistant conversation to provide a self-contained, accurate snapshot of the product, architecture, data model, configuration, testing state, and roadmap.

Use this prompt when onboarding an AI assistant:

```text
You are helping me continue the YatraCanvas project. Read the complete attached handoff before
suggesting or changing anything.

Rules:
1. Use the status labels IMPLEMENTED, PARTIAL, PLANNED, DEPRECATED, DEAD, and UNKNOWN exactly as
   defined in the handoff.
2. Do not describe a partial or planned feature as complete.
3. Base project claims on the handoff or inspected repository code.
4. Do not invent API fields, provider capabilities, environment variables, quotas, or schemas.
5. Keep API and database secrets out of Flutter, logs, source control, examples, and responses.
6. Preserve legacy identifiers and data through reversible migrations.
7. Do not introduce or change a provider without explaining licensing, attribution, provenance,
   caching, fallback, configuration, and tests.

First:
- summarize the current project stage;
- identify the single best next milestone;
- list the decisions I need to make before implementation;
- produce a small, ordered implementation plan with acceptance criteria;
- identify files likely to change, migrations required, API keys required, risks, and tests;
- stop for my approval before performing destructive database or production actions.
```

---

## 1. Status Vocabulary

- `[IMPLEMENTED]`: A working code path exists in the repository with supporting evidence and passing tests.
- `[PARTIAL]`: Code or UI exists, but an essential part of the real flow is missing.
- `[PLANNED]`: Intended direction without a complete repository implementation.
- `[DEPRECATED]`: Retained temporarily or explicitly avoided in the target architecture.
- `[DEAD]`: Unreferenced code retained in the repository that is not called by any active router/flow.
- `[UNKNOWN]`: The repository and verified documentation do not provide enough evidence.

---

## 2. Product Purpose and Target Users

YatraCanvas is a travel-planning application designed for Indian destinations. It helps travellers:
1. Select a destination city and arrival point (airport, railway station, bus stand, hotel, address);
2. Choose trip dates, trip purpose (e.g., Heritage, Food, Relaxation), and secondary interests;
3. Discover attractions and venues via open geographic data (OpenStreetMap) and curated seeds (Audiala);
4. Save, lock, prioritize, annotate, and reorder places;
5. Generate an optimized multi-day itinerary with realistic travel times, category visit durations, midday lunch breaks, opening hours, and locked stops;
6. View the itinerary and road-following route polylines on an interactive map;
7. Receive weather advisories with indoor/outdoor activity awareness;
8. Benefit from smart re-planning when modifying saved places or trip parameters.

**Target users:** Independent travellers and small travel groups. Data reviewers/administrators are a secondary user group. Commercial bookings, ticketing, payments, and social networking are non-goals.

---

## 3. Current Product Readiness Verdict

**Stage: Pre-alpha functional prototype for single-trip planning.**

### What Genuinely Works Today:
- `[IMPLEMENTED]` **Trip Creation Lifecycle:** `POST /trips` persists destination, dates, arrival points, trip purposes (weight 2.0/2.5), and preferences (weight 1.0) transactionally. `GET /trips/{trip_id}` and `PATCH /trips/{trip_id}` support full roundtrip editing and cache invalidation.
- `[IMPLEMENTED]` **Destination & Arrival Autocomplete:** `GET /locations/autocomplete` via Geoapify with coordinate extraction and client-side draft integration.
- `[IMPLEMENTED]` **Place Discovery:** Bounded OpenStreetMap/Overpass candidate retrieval across 7 categories (`tourism`, `heritage`, `religious`, `food`, `cafe`, `markets`, `nature`) with city-category caching.
- `[IMPLEMENTED]` **Recommendation Pipeline:** Canonical and spatial deduplication ($\le 75$m distance threshold), traveller suitability / access confidence filtering (excluding student messes/staff canteens), purpose/interest scoring, category filtering, and diversity ranking with explainable reasons.
- `[IMPLEMENTED]` **Saved Places:** `UserSavedPlace` CRUD with custom ordering, locks, must-visit flags, priorities, notes, and authoritative backend reconciliation.
- `[IMPLEMENTED]` **Multi-Day Itinerary Optimization:** Google OR-Tools VRPTW solver with daily touring budgets (`09:00–19:00`), category visit duration heuristics, lunch breaks (`12:30–14:00`), opening hours, locked stops, and must-visit penalties.
- `[IMPLEMENTED]` **Road-Following Route Geometry:** `GET /trips/{trip_id}/route-geometry` using keyless OSRM (or openrouteservice) with in-memory caching.
- `[IMPLEMENTED]` **Interactive Map:** `FlutterMap` widget in Flutter with OpenStreetMap tiles, start/place markers, and day-filtered road polylines.
- `[IMPLEMENTED]` **Weather Advisories:** `WeatherAdvisoryService` via Open-Meteo with itinerary-aware threshold detection (heat, rain, storms, wind) and deterministic indoor/outdoor place environment classification.
- `[IMPLEMENTED]` **Smart Re-planning:** Impact analysis on trip/place mutations, selective cache invalidation, non-destructive diff preview, and atomic apply.

### Launch Blockers & Remaining Gaps:
- `[PARTIAL]` **Authentication & Session Management:** Phone login screen does not authenticate anyone; backend assigns a fixed development placeholder `user_id`. Supabase Auth JWT verification is planned.
- `[PARTIAL]` **Multi-Trip / Account Persistence:** `TripDraft` is stored in Flutter memory and survives navigation, but does not survive an app restart. Multi-trip listing/history is not implemented.
- `[PARTIAL]` **Versioned Database Migrations:** Database relies on `SQLModel.metadata.create_all` plus manual `.sql` scripts; no Alembic runner is configured.
- `[PARTIAL]` **Admin API:** Admin shell in Flutter uses mock values; no authorized backend admin APIs exist.
- `[PARTIAL]` **Audiala Integration:** Audiala secondary POI discovery layer is present in working tree (`audiala_places_provider.py` and `audiala_places.json`) but uncommitted.
- `[PARTIAL]` **Flutter Calendar:** Date picker in trip creation is currently locked to August 2026.

---

## 4. Current Stack & Architecture

```mermaid
flowchart TB
    Traveller[Traveller] --> Flutter[Flutter Client (Material 3 + flutter_map)]
    Flutter -->|REST JSON via API_BASE_URL| FastAPI[FastAPI Backend]
    
    FastAPI --> DB[(PostgreSQL Canonical Database)]
    FastAPI --> Geoapify[Geoapify Autocomplete / Geocoding]
    FastAPI --> OSM[OpenStreetMap / Overpass POI Discovery]
    FastAPI --> Audiala[Audiala Local Seed POIs]
    FastAPI --> ORTools[Google OR-Tools VRPTW Solver]
    FastAPI --> OSRM[OSRM / ORS Route Geometry]
    FastAPI --> OpenMeteo[Open-Meteo Weather Forecasts]
    
    FSQ[FSQ OS Places Extracts] -.->|Batch CLI Importer| DB
```

### Stack Summary:
- **Client:** Flutter (Dart `^3.13.0`), `flutter_map: ^8.3.2`, `http`, `geolocator`, `flutter_svg`. State: `StatefulWidget` + `TripDraft`.
- **Backend:** FastAPI (Python 3.12+), SQLModel, SQLAlchemy, Pydantic v2, psycopg 3, httpx.
- **Optimization:** Google OR-Tools (`>=9.9.0`) VRPTW solver.
- **Database:** PostgreSQL (local or Supabase-hosted), 11 canonical tables + 1 review table.
- **Routing & Maps:** Local coordinate estimates (matrix) + OSRM / openrouteservice (road polylines) + OpenStreetMap tiles.
- **Weather:** Open-Meteo API with in-memory TTL caching.

---

## 5. Current Provider Matrix

| Provider | Status | Role in Repository | Runtime Key Needed? |
|---|---|---|---|
| **PostgreSQL / Supabase** | `[IMPLEMENTED]` | Canonical data storage (local or Supabase connection) | `DATABASE_URL` required |
| **OpenStreetMap / Overpass** | `[IMPLEMENTED]` | Runtime city POI candidate discovery across 7 categories | No key (configured endpoint) |
| **Audiala** | `[PARTIAL]` | Secondary POI candidate discovery from local dataset | No key (`AUDIALA_DATASET_PATH`) |
| **Geoapify** | `[IMPLEMENTED]` | Destination and arrival location autocomplete | `GEOAPIFY_API_KEY` optional/feature |
| **Open-Meteo** | `[IMPLEMENTED]` | Weather forecasts and itinerary advisory engine | No key for free endpoint |
| **OSRM** | `[IMPLEMENTED]` | Keyless road-route geometry polyline generation | No key (`OSRM_ROUTER_URL`) |
| **openrouteservice** | `[IMPLEMENTED]` (geom) | Alternative road-route geometry provider | `OPENROUTESERVICE_API_KEY` optional |
| **Local Estimator** | `[IMPLEMENTED]` | Route matrix distance/duration calculation | No key (app-owned) |
| **Google Places (New)** | `[DEPRECATED]`, `[DEAD]` file | Legacy adapter retained; `place_discovery_service.py` dead | `GOOGLE_PLACES_API_KEY` (legacy only) |
| **Google Routes** | `[DEPRECATED]` | Legacy route matrix adapter; not used by optimizer | `GOOGLE_ROUTES_API_KEY` (legacy only) |
| **FSQ OS Places** | `[IMPLEMENTED]` (batch CLI) | Operator-driven batch POI importer for open datasets | No runtime key |
| **Wikidata / Wikimedia** | `[PLANNED]` / Experimental | Validated experimentally; not production code | None |

---

## 6. Current Database Schema

Source of truth: `backend/app/models/entities.py`.

| Table | Entity | Purpose |
|---|---|---|
| `cities` | `City` | Canonical destination name, state, country, coordinates, nullable legacy `google_place_id`. |
| `places` | `Place` | Canonical POI with category, coordinates, rating, review count, feature flags. |
| `place_sources` | `PlaceSource` | Provider provenance (source namespace, external ID, URL, license, contact, flags). |
| `place_categories` | `PlaceCategory` | Provider category ID/label attached to place. |
| `place_tags` | `PlaceTag` | Application tags unique per place. |
| `city_category_cache` | `CityCategoryCache` | City/category discovery freshness and expiry tracking. |
| `trips` | `Trip` | User UUID, city, name, dates/days, arrival/start coordinates and provider IDs. |
| `trip_preferences` | `TripPreference` | Weighted trip preferences (purpose: 2.0/2.5, interest: 1.0) and weather ignore flags. |
| `user_saved_places` | `UserSavedPlace` | Selected trip places with order, priority, lock, must-visit, and notes. |
| `route_matrix_cache` | `RouteMatrixCache` | Pairwise distance and static/traffic duration cache per trip/mode. |
| `trip_itinerary` | `TripItinerary` | Multi-day schedule: day number, visit order, arrival/departure timestamps, duration. |
| `place_import_reviews` | `PlaceImportReview` | Schema for ambiguous import candidates (pending/resolved/ignored). |

---

## 7. Testing Baseline

- **Backend (pytest):** **199 tests** collected across 20 test files.
  - Baseline: 199 tests pass (100%).
  - Working tree note: 197 pass, 2 fail in `test_routes.py` solely because unmocked Audiala seed data injects Ujjain POIs into route smoke test assertions.
- **Flutter (flutter_test):** **49 test definitions** across 7 test files.
  - 45 tests pass.
  - Working tree note: 4 test files fail to compile due to an uncommitted syntax typo in `lib/screens/home/home_screen.dart:313:1`.

---

## 8. Current Development Frontier

1. **OSM Candidate Discovery:** Fully functional and cached across 7 categories.
2. **Audiala Candidate Discovery:** Fully operational production seed provider using `backend/app/data/audiala_places.json`.
3. **Canonical Place Identity & Multi-Source Provenance:** Implemented via `CanonicalPlaceService` (Rule 1: Provider ID, Rule 2: Shared Wikidata QID, Rule 3: Conservative Fallback, Rule 4: Canonical Place creation) with complete provenance and licensing retention (`ODbL-1.0` and `CC BY 4.0`).
4. **Wikidata/Wikimedia Enrichment:** Validated in research experiments (`docs/poi_importance_experiment.md`), sitelinks/PageRank scoring integration planned as the next milestone.

---

## 9. Recommended Next Milestones

1. **Repository Stabilization & Cleanup:**
   - Commit or cleanly stage Audiala provider (`audiala_places_provider.py` and data file);
   - Fix syntax typo in `home_screen.dart` to restore 100% Flutter test compilation;
   - Update `test_routes.py` test fixtures to mock or accommodate Audiala discovery;
   - Delete dead `place_discovery_service.py` file.
2. **Authentication & Multi-Trip Persistence:**
   - Implement Supabase Auth JWT verification in FastAPI;
   - Connect Flutter login screen to real session tokens;
   - Persist and list trips per authenticated user.
3. **Versioned Database Migrations:**
   - Initialize Alembic migration baseline.
4. **Dynamic Calendar & UI Polish:**
   - Unfreeze Flutter date picker from August 2026.

---

## 10. Modular Source of Truth

Read these modular documents for specific subsystems:

- [Project context](PROJECT_CONTEXT.md): Short authoritative overview.
- [Architecture](ARCHITECTURE.md): Full component flows, VRPTW solver specs, and smart replanning rules.
- [APIs and data sources](API_AND_DATA_SOURCES.md): Provider policies, caching, licenses, and fallback.
- [Data model](DATA_MODEL.md): Database models and provenance rules.
- [Environment variables](ENVIRONMENT_VARIABLES.md): Complete configuration reference.
- [Roadmap](ROADMAP.md): Phased roadmap milestones.
- [Decisions](DECISIONS.md): Accepted Architectural Decision Records.
- [Repository audit](REPOSITORY_AUDIT.md): Comprehensive September 4, 2026 repository audit.
