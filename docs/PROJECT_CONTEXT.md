# YatraCanvas project context

Last reviewed: 2026-09-21
Last verified against repository: 2026-09-21

`[IMPLEMENTED]` Discover Places now uses a foreground/background split: recommendation reads never
join provider prefetch tasks, Flutter renders a versioned SQLite city/profile snapshot first, and
10-item cursor pages merge progressively. Flutter models usable data (`cold`, `cached`, `partial`,
`complete`) independently from refresh work (`idle`, `queued`, `refreshing`, `refreshFailed`), so
any non-empty snapshot exits the full skeleton and refresh failure cannot remove visible cards. An
empty response with active refresh work uses bounded, lifecycle-aware polling and an explicit retry
instead of a false terminal timeout. Pixel 10 emulator verification covered the Jaipur trip flow
from the initial skeleton to 10 rendered cards; configured-PostgreSQL timings and physical-device
verification remain `[PARTIAL]`. See
[Discover Places data loading](DISCOVER_PLACES_DATA_LOADING.md).

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
  - Provider-neutral, cache-first place imagery with background Geoapify/Wikimedia/optional Foursquare resolution, item attribution metadata, negative/failure TTLs, URL validation, durable Wikimedia 429 cooldowns, semantically matched bundled category assets, and a guaranteed neutral non-photographic fallback that never blocks place or itinerary responses;
  - Saved places management (`UserSavedPlace`) with custom ordering, locks, must-visit flags, priorities, notes, and authoritative backend reconciliation;
  - Multi-day itinerary optimization powered by Google OR-Tools VRPTW solver with opening hours, category visit duration heuristics, normalized day-load balancing, bounded empty/under-filled-day repair, midday lunch breaks, locked stops, and must-visit penalties;
  - Keyless road-following route geometry via OSRM (`GET /trips/{trip_id}/route-geometry`);
  - Interactive map in Flutter (`flutter_map` with OpenStreetMap tiles and day-filtered polylines);
  - Weather advisories via Open-Meteo with itinerary-aware threshold detection and indoor/outdoor place environment classification;
  - Smart re-planning impact analysis and atomic diff application;
  - Role-based backend authentication and authorization (`POST /api/auth/login`, `GET /api/auth/me`) with bcrypt password hashing and JWT bearer tokens (`USER` and `ADMIN` roles);
  - Dedicated Admin API suite (`/api/admin/*`) guarded by `require_admin` dependency for operational metrics, user management (with self-deactivation guard), destination management, POI moderation, read-only trip inspection, place report triage, and provider diagnostics;
  - Centralized POI moderation statuses (`ACTIVE`, `HIDDEN`, `RESTRICTED`, `DUPLICATE`, `INVALID`) filtering candidate discovery, recommendation scoring, and manual search;
  - Responsive Web Admin Dashboard served by FastAPI at `/admin` (HTML5, Vanilla CSS, reactive Vanilla JS).

- **What is partial / not yet implemented:**
  - Traveler account binding in Flutter: Traveler app still uses guest session flow and server-owned default UUID `user_id`; multi-trip persistence under authenticated traveler accounts is planned;
  - Account-level multi-trip persistence: `TripDraft` and successful-save snapshots in `YatraSession` survive screen navigation during a session, but not an app restart; the new account/history screens do not add authenticated ownership or a trip-list endpoint;
  - Versioned migration runner: Database uses `SQLModel.metadata.create_all` plus manual `.sql` scripts; no Alembic runner is configured.

---

## 2. Current Technology Stack

| Layer | Technologies | Role & Key Details |
|---|---|---|
| **Client (Flutter)** | Flutter SDK (Dart `^3.13.0`), Material 3, `http`, `flutter_map: ^8.3.2`, `geolocator`, `flutter_svg`, `cached_network_image`, `sqflite` | Widget-local `StatefulWidget` state + shared in-memory `TripDraft`; durable versioned SQLite recommendation snapshots. No external state library (BLoC/Riverpod) or router package. |
| **Admin Web App** | HTML5, Vanilla CSS, Vanilla JavaScript (ES6+), Fetch API | Responsive, information-dense operational dashboard served by FastAPI at `/admin` with JWT bearer authentication. |
| **Backend (FastAPI)** | Python 3.12+, FastAPI, Pydantic v2, SQLModel, SQLAlchemy, psycopg 3, httpx, bcrypt, pyjwt | Async REST API, Pydantic settings, dependency injection, safe error translation, backend secret encapsulation, JWT auth, admin suite. |
| **Database** | PostgreSQL (local or Supabase-hosted) | Canonical/supporting tables include places and provenance, `place_refresh_jobs`, `place_image_cache`, `provider_cooldowns`, users/reports, trips/days/preferences/saved places, route/itinerary caches, and import reviews. Existing deployments require reviewed manual SQL because no ordered migration runner exists. |
| **Optimization** | Google OR-Tools (`>=9.9.0`) | Multi-day Vehicle Routing Problem with Time Windows (VRPTW) solver (`VrptwSolverService`). |
| **Routing & Matrix** | Local coordinate estimates (default matrix), OSRM / openrouteservice (geometry) | Keyless Haversine distance/duration calculations for matrices; OSRM public demo / ORS for road geometry polylines. |
| **Weather** | Open-Meteo | Hourly/daily weather forecasts with in-memory TTL caching and deterministic exposure classification. |
| **Caching** | Database + In-Process Memory | DB tables for `city_category_cache`, `route_matrix_cache`, and positive/negative/failed `place_image_cache`; in-memory TTL caches for Geoapify autocomplete, route geometry, and weather forecasts. |

---

## 3. Current Core Flow

```text
Trip Creation (Destination & Dates → Arrival Point → Purpose & Preferences)
    ↓
POST /trips (Transactionally persists Trip + TripPreferences, returns trip_id)
    ↓
Recommendations & Manual Search:
  - Cache-first POI recommendations (OSM + Audiala + Geoapify fallback)
  - Debounced manual search (Geoapify 50km destination radius + local DB)
  - Canonical place resolution via CanonicalPlaceService
  - Cached image metadata returned immediately; missing images enriched in background
    ↓
Saved Places (CRUD, reorder, locks, must-visit flags under trip_id)
    ↓
Route Optimization (Local matrix estimates → OR-Tools VRPTW multi-day solver → TripItinerary)
    ↓
Road Geometry (OSRM / ORS polyline generation attached to optimization response)
    ↓
Interactive Map (Progressive Frame 1 FlutterMap + OSM tiles + non-blocking polylines + markers)
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
| **Geoapify** | `[IMPLEMENTED]` | Destination/arrival autocomplete, POI fallback, and existing-payload-first place image metadata/details. | `GEOAPIFY_API_KEY` (backend-only). |
| **Wikimedia / Wikipedia / Wikidata** | `[IMPLEMENTED]` images/prominence/rate control; `[PLANNED]` descriptions | Direct-identifier-first notable-place images with source/author/license metadata, conservative contextual fallback, process-shared serialization, and durable 429 cooldown. | None; backend supplies a meaningful User-Agent. |
| **Foursquare Places API** | `[IMPLEMENTED]` optional image enrichment | Conservative venue match and photo selection only; never creates or ranks canonical POIs. | `FOURSQUARE_API_KEY` optional and backend-only. |
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
- **Progressive POI Prefetch & Cache-First Live Discovery Reliability** is `[IMPLEMENTED]` with `[PARTIAL]` deployment/job delivery:
  - 3-tier cache semantics (`FRESH` $\le 24$h, `STALE_USABLE` $\le 168$h, `MISSING`) with `DISCOVERY_MIN_USABLE_CANDIDATES_PER_CATEGORY=6`.
  - Destination, dates, interests, and start-location stages enqueue or record work without blocking Flutter navigation. HTTP 202 is returned before provider work; `GET /places/prefetch/{city_id}` exposes coarse state.
  - Foreground recommendations read persisted eligible POIs only; cache age schedules refresh but never removes otherwise displayable rows.
  - Prefetch and Discover persist one `place_refresh_jobs` lease per `(city_id, versioned_category)`. Atomic acquisition, lease expiry, and recorded outcomes coalesce provider execution across backend workers. Local task delivery still depends on a live process; a later request recovers queued or expired work.
  - Multi-provider fallback hierarchy: Cached DB places $\to$ `GeoapifyPlacesProvider` $\to$ `AudialaPlacesProvider` $\to$ `OpenStreetMapPlacesService`.
  - Circuit breaker for Overpass OSM with consecutive failure threshold (3) and cooldown (60s).
  - Partial category provider failure tolerance returning scored usable recommendations.
  - Flutter consumes the additive refresh-state headers independently from data availability,
    retains non-empty local/server cards during refresh or failure, writes snapshots only for
    non-empty server results, and bounds empty-active polling to three lifecycle-aware attempts.
- **Experiment-First Wikidata/Audiala Prominence Scoring (`PlaceImportanceScorer`)** is `[IMPLEMENTED]`:
  - Log-normalized bounded sitelinks ($\le 100$) and PageRank ($\le 25.0$).
  - Composite prominence in $[0.0, 1.0]$ blended at $60\%$ sitelinks consensus and $40\%$ PageRank network centrality.
  - Importance weight ($15.0$ pts) activates inside relevant candidates ($category\_score > 0$), protecting personalization from being overwhelmed by famous irrelevant monuments.
  - Missing Wikidata metadata is neutral ($0.0$ boost, zero penalty), preserving local-speciality dining and unindexed regional POIs.
- **Core Trip Flow Hardening (Multi-Day Integrity + Manual Search + Interactive Map Performance)** is `[IMPLEMENTED]`:
  - Multi-day day-sequence invariant: optimization outputs include `total_days=trip.days` (`RouteOptimizationRead`), normalizing all logical days $\{1 \dots N\}$ so days with 0 stops never disappear.
  - Manual place search: 350ms debounced destination-scoped search (`GET /cities/{city_id}/places/search`) using Geoapify autocomplete + local DB, canonical resolution (`POST /cities/{city_id}/places/resolve`) via `CanonicalPlaceService`, duplicate prevention, and route eligibility.
  - Interactive map progressive rendering: pre-passes trip state from `PlaceDiscoveryScreen`, rendering base map and markers on Frame 1 ($12-25\text{ ms}$) without blocking on route recalculation; non-blocking asynchronous route polyline loading with status indicator.
- **Home UI Refinement & Explore Screen** is `[IMPLEMENTED]`:
  - Figma-aligned home screen with custom glassmorphism navigation bar (`YatraBottomNavigation`) and refractive glass shader (`yatra_refractive_glass.frag`).
  - Featured destination cards, continuing trip planning card, and interactive discovery triggers.
  - Dedicated Explore page (`ExplorePage`) with curated destination browsing, category filtering, and direct trip creation entry points.
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

## Day-aware planner update — 2026-09-07

`[IMPLEMENTED]` Verified planner slice: the existing OR-Tools planner consumes actual
TripDay windows, native assigned-day locks and normalized weekday opening intervals. It returns
scheduled plus structured unscheduled places, keeps UNKNOWN hours unverified, and accepts
underfilled trips and up to 50 selections. Full-trip previews use the same inputs. See
[implementation report](PLANNER_IMPLEMENTATION.md) for exact behavior and measured solve times.
# Core trip flow reliability status (2026-09-07)

`[IMPLEMENTED]` The repository now has deterministic end-to-end coverage from trip creation through
TripDay configuration, selection, assignment, planning, map viewing, execution status, and partial
replanning. See [`CORE_TRIP_FLOW_RELIABILITY.md`](CORE_TRIP_FLOW_RELIABILITY.md). No new product feature
or provider was introduced.
