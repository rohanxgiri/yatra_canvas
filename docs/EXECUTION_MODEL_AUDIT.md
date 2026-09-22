# YatraCanvas Real-World Execution Model & Concurrency Audit

**Document Status:** `[IMPLEMENTED]`  
**Audit Date:** 2026-09-21  
**Target Repository:** YatraCanvas (Flutter client + FastAPI backend + Supabase PostgreSQL)  

---

## 1. End-to-End Flutter Journey Execution Graph

The following trace maps every user interaction from onboarding to Discover, highlighting **FOREGROUND** (blocking/user-perceived) vs. **BACKGROUND** (asynchronous/fire-and-forget) operations across the network, thread pools, and database sessions.

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Flutter as Flutter App
    participant API as FastAPI Backend
    participant Worker as Thread/Task Pool
    participant DB as Supabase PostgreSQL
    participant Ext as External Providers (OSM/Geoapify/Wikimedia)

    %% 1. Destination Selection
    Note over User, Flutter: Stage 1: Destination Selection
    User->>Flutter: Confirms Destination (e.g. Shillong)
    Flutter->>API: [BG] POST /places/prefetch (stage=destination_confirmed)
    API->>DB: [FG] Check city identity & count
    API->>DB: [FG] Request refresh: 7 sequential DB queries for jobs
    API->>Worker: [BG] Dispatch 7 thread workers (_execute_job_in_thread)
    API-->>Flutter: [FG] 202 Accepted (partially_ready / fetching)
    
    par Background Discovery Workers (7 threads)
        Worker->>DB: [BG] Acquire durable lease (UPDATE job)
        Worker->>DB: [BG] Open Session: session.get(City)
        Note over Worker, DB: LEAK: Session held open across HTTP I/O
        Worker->>Ext: [BG] Overpass HTTP (up to 25s) / Geoapify (up to 8s)
        Worker->>DB: [BG] Persist places & commit
        Worker->>DB: [BG] Release lease & close session
    and User continues onboarding
        Note over User, Flutter: Stage 2-4: Dates, Start Location, Interests
        User->>Flutter: Confirms Dates
        Flutter->>API: [BG] POST /places/prefetch (stage=dates_confirmed)
        User->>Flutter: Confirms Start Location
        Flutter->>API: [BG] POST /places/prefetch (stage=start_location_confirmed)
        User->>Flutter: Confirms Interests (heritage, food, tourism)
        Flutter->>API: [BG] POST /places/prefetch (stage=interests_confirmed)
        API->>DB: [FG] Re-query/re-enqueue refresh jobs
        User->>Flutter: Confirms Preferences -> Click "Create Trip"
    end

    %% 5. Trip Creation
    Note over User, Flutter: Stage 5: Trip Creation
    Flutter->>API: [FG] POST /trips (timeout=15.0s in Flutter)
    API->>DB: [FG] Acquire DB Connection from Pool (Timeout=30s)
    Note over API, DB: CONTENTION: Pool (max 15) saturated by 7 background workers!
    API->>DB: [FG] 1. Cold TLS / checkout wait
    API->>DB: [FG] 2. SELECT City
    API->>DB: [FG] 3. SELECT Trip (idempotency check)
    API->>DB: [FG] 4. INSERT Trip (flush)
    API->>DB: [FG] 5. INSERT TripPreferences
    API->>DB: [FG] 6. INSERT TripDays (flush)
    API->>DB: [FG] 7. COMMIT
    API->>DB: [FG] 8. SELECT Trip (refresh - redundant!)
    API-->>Flutter: [FG] 200 OK TripRead (Latency: 11.0s - 14.5s idle; >15s under load)

    %% 6. Discover Initialization
    Note over Flutter, API: Stage 6: Discover Screen Mounts
    par Discover Concurrent Foreground Requests
        Flutter->>API: [FG] GET /trips/{id}/saved-places
        Flutter->>API: [FG] GET /trips/{id}/weather-advisories
        Flutter->>API: [FG] GET /trips/{id}/days
        Flutter->>API: [FG] POST /places/recommend (10 items)
    end

    %% 7. Recommendation Processing
    rect rgb(240, 240, 255)
        Note over API, DB: Recommendation Execution in Worker Thread
        API->>DB: [FG] Acquire DB Connection
        API->>DB: [FG] Read candidate places (categories_to_retrieve)
        Note over API: In-Memory Scoring & MMR Ranking
        API->>DB: [FG] DUPLICATE: PersistedPlaceReader.read() executed a second time!
        API-->>Flutter: [FG] 200 OK Recommendations (Latency: 14.9s - 25.7s)
    end

    %% 8. Image Enrichment
    par Background Image Enrichment & Prefetch
        API->>Worker: [BG] schedule_place_image_enrichment (top 10 place IDs)
        Worker->>DB: [BG] Open Session for batch
        Note over Worker, DB: LEAK: Session held open across image resolution
        Worker->>Ext: [BG] Wikimedia / Geoapify (Semaphore(1) queue starvation)
        Worker->>DB: [BG] Commit PlaceImageCache (97% provider_error)
    and Flutter Render
        Flutter->>Flutter: Render PlaceCards with fallback assets
        Note over Flutter: restaurant.webp displays Varanasi river ghats!<br>heritage/tourism lack mapping -> fallback to neutral gray box!
    end
```

---

## 2. Operation Classification: Foreground vs. Background

| Operation | Triggering Event | Type | Execution Context | Resource Dependencies |
| --- | --- | --- | --- | --- |
| `POST /places/prefetch` | Destination/Dates/Interests confirmed | **BACKGROUND** (HTTP 202) | FastAPI event loop + DB session | Connection Pool, `PlaceRefreshJob` table |
| `_execute_job_in_thread` | Prefetch enqueue | **BACKGROUND** | Python worker thread (`to_thread`) | Thread pool, Connection Pool, Overpass/Geoapify APIs |
| `POST /trips` | Click "Create Trip" | **FOREGROUND** (User blocked) | FastAPI route handler | Connection Pool (6 sequential round trips across WAN) |
| `GET /trips/{id}/saved-places` | Discover mount | **FOREGROUND** | FastAPI route handler | Connection Pool, `SavedPlace` table |
| `GET /trips/{id}/weather-advisories`| Discover mount | **FOREGROUND** | FastAPI route handler | Connection Pool, Open-Meteo API |
| `GET /trips/{id}/days` | Discover mount | **FOREGROUND** | FastAPI route handler | Connection Pool, `TripDay` table |
| `POST /places/recommend` | Discover mount / filter change | **FOREGROUND** (User waiting) | Python worker thread (`to_thread`) | Connection Pool, `Place` table (Read TWICE) |
| `PlaceImageResolver.resolve_many` | Recommendation response hook | **BACKGROUND** | Python `asyncio.Task` | Connection Pool (held during HTTP), Wikimedia Semaphore(1) |
| Flutter `placeImagePrefetchService` | Recommendations rendered | **BACKGROUND** | Flutter image cache / HTTP | Mobile device network, CDN/Wikimedia |

---

## 3. Shared Resource Contention Points

### A. SQLAlchemy Connection Pool Saturation
- **Resource**: `QueuePool(pool_size=5, max_overflow=10)` = Maximum **15 total connections**.
- **Contention**:
  - When a user confirms a destination, `DurablePlaceRefreshService` enqueues up to 7 categories, each launching an asynchronous worker thread.
  - Each worker opens `with Session(self._engine) as session:` and holds the checked-out connection during Overpass network calls (up to 25s).
  - 7 background threads immediately occupy 7 connections.
  - When the user confirms interests or opens Discover, additional refresh checks or image enrichment workers acquire more connections.
  - The foreground `POST /trips` request arrives and blocks waiting in the QueuePool for an available connection (`pool_timeout=30s`). Because the client has a 15-second timeout (`Duration(seconds: 15)`), the Flutter app throws `Trip creation took too long` before a connection is granted.

### B. Single-Threaded Process Limiter Starvation (Image Resolver)
- **Resource**: `asyncio.Semaphore(1)` for Wikimedia in `provider_rate_control.py`.
- **Contention**:
  - `PlaceImageResolver.resolve_many` schedules batches of up to 10 places with concurrency 4 (`asyncio.Semaphore(4)`).
  - However, every Wikimedia provider request must acquire `Semaphore(1)`.
  - The per-place timeout is set to `place_image_timeout_seconds * 2` = **10.0 seconds**, covering the entire time in `resolve_one`.
  - Places 3 through 10 wait in the queue behind the semaphore. By the time their turn arrives, the 10.0s total budget has expired.
  - The resolver catches `TimeoutError`, marks `had_error = True`, and writes `status="failed"` with `failure_reason="provider_error"` and a 30-minute negative cache TTL.
  - Result: 97% of all image resolution attempts fail not because Wikimedia failed, but because they starved waiting for the lock.

### C. Redundant WAN Round Trips in Foreground Recommendation Path
- **Resource**: Network RTT between backend and Supabase PostgreSQL (Australia: ~400ms).
- **Contention**:
  - `recommendation.recommend(...)` executes `PersistedPlaceReader.read(...)` across all requested categories (~7,500 ms).
  - Immediately following ranking, `_recommend_in_worker` calls `PersistedPlaceReader.read(...)` *again* for `candidate_snapshot` (~7,500 ms).
  - Total DB time in the worker thread doubles to ~15,000 ms, holding a connection and blocking the user from viewing places.

### D. Session Leaks Across External HTTP I/O
- **Resource**: Database connections held during third-party provider latency.
- **Locations**:
  1. `backend/app/services/durable_place_refresh_service.py:212-216`: DB session is held while Overpass (up to 25s) and Geoapify (up to 8s) run.
  2. `backend/app/services/place_image_service.py:539-544`: DB session is held while Wikimedia and Geoapify image lookups run.
  3. `backend/app/services/provider_rate_control.py:109`: DB session opened inside rate limiter check.

### E. Semantic Fallback Mappings & Asset Integrity
- **Resource**: Flutter asset bundle & fallback resolver.
- **Defects**:
  1. `assets/images/place_fallbacks/restaurant.webp`: Depicts Varanasi Ganges riverfront temples and boats, causing all restaurant/dining POIs (e.g. in Shillong) to display river ghats.
  2. `assets/images/place_fallbacks/hotel.webp`: Depicts an empty wooden lake dock with rowboats.
  3. `lib/utils/place_image_fallbacks.dart`: Lacks mappings for `landmark`, `heritage`, `tourism`, and `other`, defaulting all such places to a flat neutral placeholder instead of a photographic fallback.
  4. Five existing assets in `assets/images/place_fallbacks/` (`generic_place.webp`, `art_gallery.webp`, `mountain.webp`, `shopping.webp`, `viewpoint.webp`) are orphaned and never rendered.
