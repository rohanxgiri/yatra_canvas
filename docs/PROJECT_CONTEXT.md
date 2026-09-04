# YatraCanvas project context

Last reviewed: 2026-09-04
Last verified against repository: 2026-09-04

This document is the concise, authoritative primary overview for humans and agents. Status labels mean:

- `[IMPLEMENTED]`: a working repository code path and supporting tests/evidence exist.
- `[PARTIAL]`: some code or UI exists, but an essential part of the flow is absent.
- `[PLANNED]`: intended direction with no complete implementation in this repository.
- `[DEPRECATED]`: retained temporarily but not part of the target required architecture.
- `[DEAD]`: unreferenced code retained in the repository that is not called by any active path.
- `[UNKNOWN]`: repository or official-document evidence is insufficient.

---

## 1. Product Purpose and Stage

### Product Purpose
YatraCanvas is an intelligent travel-planning application designed for Indian destinations. It guides travellers through:
1. Selecting a destination city and arrival point (airport, station, hotel, custom address);
2. Specifying trip dates, purpose, and secondary preferences;
3. Discovering relevant places via open data and curated discovery;
4. Saving, locking, prioritizing, and reordering places;
5. Generating an optimized, time-aware multi-day itinerary with lunch breaks and opening hours;
6. Visualizing the journey on an interactive map with road-following route geometry;
7. Receiving weather advisories with indoor/outdoor activity awareness.

### Current Product Stage
**Pre-alpha functional prototype for single-trip planning.**

- **What genuinely works today:**
  - Full trip creation lifecycle (`POST /trips`, `GET /trips/{trip_id}`, `PATCH /trips/{trip_id}`) with transactional persistence of destinations, dates, arrival points, trip purposes (weight 2.0/2.5), and preferences (weight 1.0);
  - City and arrival location autocomplete via Geoapify (`GET /locations/autocomplete`);
  - OpenStreetMap/Overpass bounded city-wide candidate discovery across 7 categories;
  - Multi-stage recommendation pipeline with canonical/spatial/brand deduplication, generalizable institutional/private suitability filtering, purpose/interest weighting, bounded Wikidata importance, and mixed-interest category balancing hardened across 7 benchmark cities and validated with 0 restricted POI leakage;
  - Saved places management (`UserSavedPlace`) with custom ordering, locks, must-visit flags, priorities, notes, and authoritative backend reconciliation;
  - Multi-day itinerary optimization powered by Google OR-Tools VRPTW solver with opening hours, category visit duration heuristics, midday lunch breaks, locked stops, and must-visit penalties;
  - Keyless road-following route geometry via OSRM (`GET /trips/{trip_id}/route-geometry`);
  - Interactive map in Flutter (`flutter_map` with OpenStreetMap tiles and day-filtered polylines);
  - Weather advisories via Open-Meteo with itinerary-aware threshold detection and indoor/outdoor place environment classification;
  - Smart re-planning impact analysis and atomic diff application.

- **What is partial / not yet implemented:**
  - Real authentication / session management: Phone login screen is a UI shell without backend OTP/JWT verification. The backend currently assigns a fixed server-owned development UUID `user_id`;
  - Account-level multi-trip persistence: `TripDraft` is retained in widget memory and survives screen navigation, but does not survive an app restart;
  - Versioned migration runner: Database uses `SQLModel.metadata.create_all` plus manual `.sql` scripts; no Alembic runner is configured;
  - Admin review: Admin UI shell exists with mock data; no authenticated admin APIs or review actions exist.

---

## 2. Current Technology Stack

| Layer | Technologies | Role & Key Details |
|---|---|---|
| **Client (Flutter)** | Flutter SDK (Dart `^3.13.0`), Material 3, `http`, `flutter_map: ^8.3.2`, `geolocator`, `flutter_svg` | Widget-local `StatefulWidget` state + shared in-memory `TripDraft`. No external state library (BLoC/Riverpod) or router package. |
| **Backend (FastAPI)** | Python 3.12+, FastAPI, Pydantic v2, SQLModel, SQLAlchemy, psycopg 3, httpx | Async REST API, Pydantic settings, dependency injection, safe error translation, backend secret encapsulation. |
| **Database** | PostgreSQL (local or Supabase-hosted) | 11 canonical tables (`cities`, `places`, `place_sources`, `place_categories`, `place_tags`, `city_category_cache`, `trips`, `trip_preferences`, `user_saved_places`, `route_matrix_cache`, `trip_itinerary`) + `place_import_reviews` schema. |
| **Optimization** | Google OR-Tools (`>=9.9.0`) | Multi-day Vehicle Routing Problem with Time Windows (VRPTW) solver (`VrptwSolverService`). |
| **Routing & Matrix** | Local coordinate estimates (default matrix), OSRM / openrouteservice (geometry) | Keyless Haversine distance/duration calculations for matrices; OSRM public demo / ORS for road geometry polylines. |
| **Weather** | Open-Meteo | Hourly/daily weather forecasts with in-memory TTL caching and deterministic exposure classification. |
| **Caching** | Database + In-Process Memory | DB tables for `city_category_cache` and `route_matrix_cache`; in-memory TTL caches for Geoapify autocomplete, route geometry, and weather forecasts. |

---

## 3. Current Core Flow

```text
Trip Creation (Destination & Dates → Arrival Point → Purpose & Preferences)
    ↓
POST /trips (Transactionally persists Trip + TripPreferences, returns trip_id)
    ↓
Recommendations (OSM discovery + Audiala seed → Dedup → Suitability → Scoring → Ranking)
    ↓
Saved Places (CRUD, reorder, locks, must-visit flags under trip_id)
    ↓
Route Optimization (Local matrix estimates → OR-Tools VRPTW multi-day solver → TripItinerary)
    ↓
Road Geometry (OSRM / ORS polyline generation attached to optimization response)
    ↓
Interactive Map (FlutterMap + OSM tiles + day-filtered road polylines + markers)
```

---

## 4. Current Recommendation Architecture

The recommendation engine (`RecommendationService`) executes a deterministic 5-stage pipeline:

1. **Candidate Retrieval:**
   - Queries stored database POIs for the destination city;
   - Triggers bounded OpenStreetMap/Overpass discovery across 7 categories (`tourism`, `heritage`, `religious`, `food`, `cafe`, `markets`, `nature`) with category-level TTL caching;
   - Merges secondary candidates from the local Audiala dataset (`AudialaPlacesProvider`).
2. **Canonical & Spatial Deduplication (`deduplicate_places`):**
   - Matches canonical `Place.id` and provider namespace keys (`source:external_id`);
   - Resolves spatial proximity ($\le 75$m distance threshold with normalized tokenized name similarity) to merge OSM node/way and multi-category duplicates;
   - Preserves distinct branches of the same chain at different locations as unique venues.
3. **Traveller Suitability & Access Confidence (`is_traveller_suitable`):**
   - Context-based classifier evaluating tag evidence into `PUBLIC_LIKELY`, `UNKNOWN`, `RESTRICTED_LIKELY`, and `RESTRICTED`;
   - Automatically filters out student messes, staff canteens, institutional facilities, and private venues without maintaining hardcoded institution blacklists.
4. **Scoring & Relevance:**
   - Centralized weighting: Trip Purpose matches receive $2.5\times$ weight; secondary interest matches receive $1.0\times$ weight;
   - Incorporates access confidence, verified ratings/reviews, and city-center proximity without fabricating missing data;
   - Enforces a minimum relevance score cutoff.
5. **Diversity Ranking & Explainability:**
   - Interleaves categories to prevent single-category saturation;
   - Generates transparent recommendation reasons (e.g., *"Matches your Heritage purpose"*);
   - Supports non-destructive client category filtering.

---

## 5. Current Provider Status

| Provider | Status | Role in Repository | Key / Auth Required |
|---|---|---|---|
| **OpenStreetMap / Overpass** | `[IMPLEMENTED]` | Primary runtime POI discovery across 7 categories with city-category TTL caching. | None (`OVERPASS_API_URL` defaults to public FOSSGIS endpoint). |
| **Audiala** | `[IMPLEMENTED]` | Production seed and secondary POI candidate discovery layer; reads local JSON extract and resolves into canonical places. | None (`AUDIALA_DATASET_PATH`). |
| **Geoapify** | `[IMPLEMENTED]` | Destination city and arrival location autocomplete/geocoding. | `GEOAPIFY_API_KEY` (backend-only). |
| **Open-Meteo** | `[IMPLEMENTED]` | Weather forecasts and itinerary-aware advisory engine. | None for free non-commercial endpoint (`OPEN_METEO_BASE_URL`). |
| **OSRM** | `[IMPLEMENTED]` | Default keyless road-route geometry polyline generation. | None (`OSRM_ROUTER_URL`). |
| **openrouteservice** | `[IMPLEMENTED]` (geometry), `[PLANNED]` (matrix) | Alternative road-route geometry provider. | `OPENROUTESERVICE_API_KEY` (optional). |
| **Local Coordinate Estimator** | `[IMPLEMENTED]` | Default route matrix travel distance/time calculation for optimizer. | None (application-owned calculation). |
| **Google Places API (New)** | `[DEPRECATED]` / REMOVED | Dead `place_discovery_service.py` deleted; config purged. City flow uses Geoapify. | None. |
| **Google Routes API** | `[DEPRECATED]` | Legacy route matrix adapter retained; not used by normal optimizer. | `GOOGLE_ROUTES_API_KEY` (legacy adapter only). |
| **FSQ Open Source Places** | `[IMPLEMENTED]` (batch CLI) | Operator-driven batch POI importer for open CSV/JSONL extracts. | None (offline file import). |
| **Wikidata / Audiala Importance** | `[IMPLEMENTED]` | Bounded POI prominence scoring via `PlaceImportanceScorer` using log-normalized sitelinks & PageRank. | None (`audiala_places.json` seed). |
| **FlutterMap / OSM Tiles** | `[IMPLEMENTED]` | Interactive map widget rendering in Flutter with OSM tile layer. | None. |

---

## 6. Current Development Frontier

- **Core trip → recommendation → itinerary → map flow** is operational.
- **OSM city-wide candidate discovery** is operational.
- **Audiala secondary candidate discovery** is operational and seeded.
- **Canonical multi-source Place identity and provenance resolution (`CanonicalPlaceService`)** is `[IMPLEMENTED]`:
  - Deterministic Rule 1: Existing provider identity `(source, external_place_id)` reuse.
  - Deterministic Rule 2: Shared strong global identifier (Wikidata QID) cross-provider matching.
  - Conservative Rule 3: Geographic ($\le 100$m), category-compatible, and strict name variant matching fallback.
  - Rule 4: Canonical Place creation with full `PlaceSource` provenance and licensing (CC BY 4.0 and ODbL-1.0).
- **Progressive POI Prefetch & Cache-First Live Discovery Reliability** is `[IMPLEMENTED]`:
  - 3-tier cache semantics (`FRESH` $\le 24$h, `STALE_USABLE` $\le 168$h, `MISSING`) with `DISCOVERY_MIN_USABLE_CANDIDATES_PER_CATEGORY=6`.
  - Non-blocking destination-triggered broad shallow prefetch (`POST /places/prefetch` with stage `shallow`, `DISCOVERY_SHALLOW_LIMIT=15`).
  - Non-blocking purpose/interest-triggered targeted prefetch (`POST /places/prefetch` with stage `targeted`).
  - In-memory concurrency deduplication for `(city_id, category)` background refreshes.
  - Multi-provider fallback hierarchy: Cached DB places $\to$ `GeoapifyPlacesProvider` $\to$ `AudialaPlacesProvider` $\to$ `OpenStreetMapPlacesService`.
  - Circuit breaker for Overpass OSM with consecutive failure threshold (3) and cooldown (60s).
  - Partial category provider failure tolerance returning scored usable recommendations.
- **Experiment-First Wikidata/Audiala Prominence Scoring (`PlaceImportanceScorer`)** is `[IMPLEMENTED]`:
  - Log-normalized bounded sitelinks ($\le 100$) and PageRank ($\le 25.0$).
  - Composite prominence in $[0.0, 1.0]$ blended at $60\%$ sitelinks consensus and $40\%$ PageRank network centrality.
  - Importance weight ($15.0$ pts) activates inside relevant candidates ($category\_score > 0$), protecting personalization from being overwhelmed by famous irrelevant monuments.
  - Missing Wikidata metadata is neutral ($0.0$ boost, zero penalty), preserving local-speciality dining and unindexed regional POIs.
**Next recommended engineering task:**
`supabase-auth-jwt` (Implement Supabase Auth JWT verification in FastAPI and connect Flutter session tokens to trips).

---

## 7. Authoritative Source-of-Truth Hierarchy

- **[Project context](PROJECT_CONTEXT.md)** (this file): Short authoritative overview of product state, stack, and providers.
- **[Architecture](ARCHITECTURE.md)**: Detailed technical structure, component flows, and algorithm specifications.
- **[APIs and data sources](API_AND_DATA_SOURCES.md)**: Provider ownership, policies, caching, licenses, and fallback behavior.
- **[Data model](DATA_MODEL.md)**: Database schema, entity relationships, constraints, and migration rules.
- **[Environment variables](ENVIRONMENT_VARIABLES.md)**: Complete inventory of accepted environment variables.
- **[Roadmap](ROADMAP.md)**: Phased delivery milestones and acceptance criteria.
- **[Decisions](DECISIONS.md)**: Accepted Architectural Decision Records (ADRs).
- **[Repository audit](REPOSITORY_AUDIT.md)**: Detailed September 4, 2026 audit of codebase health, tests, and branch status.
- **[Complete ChatGPT handoff](CHATGPT_PROJECT_HANDOFF.md)**: Concise onboarding document for new AI/human sessions.
