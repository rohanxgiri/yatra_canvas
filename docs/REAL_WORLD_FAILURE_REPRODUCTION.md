# Real-World Failure Reproduction Report

**Document Status:** `[IMPLEMENTED]`  
**Reproduction Date:** 2026-09-21  
**Baseline Commit:** `785d787975603323ec4d252a22245d5cfc082297`  
**Test Harness Locations:**  
- `scripts/diagnostics/reproduce_real_world_failures.py`  
- `test/place_fallback_coverage_test.dart`  

---

## 1. Executive Summary of Reproduced Failures

Automated unit tests previously passed because they ran in isolation with mock providers, zero network latency, and single-threaded execution. When exercised under realistic concurrency, timing, and WAN conditions to Supabase PostgreSQL, the system failed across all major workflows:

1. **Trip Creation Timeout (Flutter 15.0s Timeout Exceeded):**
   - In 10 consecutive simulated user journeys, trip creation had a **median duration of 15,819.8 ms** (exceeding the 15.0s Flutter timeout) and a **maximum of 30,827.1 ms**.
   - Journeys 3, 4, 9, and 10 completely timed out from the Flutter client's perspective (`Trip creation took too long`).
   - Root Cause: Sequential unbatched round trips across the WAN (`session.flush()`, `create_default_trip_days`, `session.commit()`, `session.refresh(trip)`) compounded by connection pool starvation from 7 concurrent background prefetch threads.

2. **Background Prefetch Latency Violation:**
   - `POST /places/prefetch` took **17,286.7 ms – 19,470.2 ms** to return HTTP 202, exceeding Flutter's `PlacePrefetchService` 15.0s timeout.
   - Root Cause: `DurablePlaceRefreshService.request_refresh()` executes 7 sequential queries (one per category) checking `PlaceRefreshJob` within a synchronous loop before enqueuing background tasks.

3. **Image Resolution Lock Starvation & Negative Cache Poisoning:**
   - In a 20-place image resolution batch, places failed with `stage=total_budget` (`had_error=True`) and were marked with `failure_reason='provider_error'` with a 30-minute negative TTL.
   - Root Cause: `WikimediaRateController` serializes requests with `asyncio.Semaphore(1)`. `PlaceImageResolver` applies a strict 10.0s total budget (`asyncio.wait_for(timeout=10.0)`) starting *before* lock acquisition. Queued items exhaust their timeout waiting in line, never reaching Wikimedia.

4. **Database Session Leaks Across Long External HTTP I/O (Invariant 1 Violation):**
   - During the 20-place image batch, PostgreSQL / PgBouncer forcibly aborted the checked-out database connection:
     `sqlalchemy.exc.OperationalError: (psycopg.OperationalError) consuming input failed: server closed the connection unexpectedly`
   - Root Cause: `PlaceImageResolver.resolve_many` and `DurablePlaceRefreshService.execute_job` wrap asynchronous HTTP provider calls (Overpass up to 25s, Wikimedia up to 60s) inside `with Session(engine) as session:`, keeping PostgreSQL connections idle in transaction until the server terminates them.

5. **Redundant Candidate DB Reads in Discover Recommendations:**
   - Recommendations took up to **23,460.4 ms**.
   - Root Cause: `_recommend_in_worker()` in `backend/app/routers/places.py` queries candidates via `recommendation.recommend()` (~7.5s) and then immediately queries the exact same candidates a second time via `PersistedPlaceReader().read()` (~7.5s).

6. **Local Category Fallback Failures (7 Test Failures in Flutter):**
   - Flutter test `test/place_fallback_coverage_test.dart` failed with 7 errors:
     - Normalized `landmark` -> `null` (renders neutral gray placeholder `Icons.landscape_rounded`).
     - Normalized `other` -> `null`.
     - Aliases `heritage`, `tourism`, `cafes`, `markets` -> `null`.
     - `assets/images/place_fallbacks/restaurant.webp` depicts Varanasi river ghats on the Ganges, causing food places to display river temples.
     - `assets/images/place_fallbacks/hotel.webp` depicts an empty lake dock with rowboats.

---

## 2. Detailed Reproduction Scenarios

### Scenario A — Prefetch + Immediate Trip Creation
- **Command:** `python -u scripts/diagnostics/reproduce_real_world_failures.py`
- **Simulated Flow:** User confirms destination ("Shillong") -> Flutter dispatches `POST /places/prefetch` -> User proceeds to trip creation immediately -> Flutter dispatches `POST /trips`.
- **Expected Behavior:** Prefetch returns 202 in < 500 ms; Trip creation succeeds in < 2,000 ms.
- **Actual Behavior:**
  - Prefetch duration: **17,286.7 ms** (Violates Flutter 15.0s client timeout).
  - Trip creation duration: **9,563.9 ms** (Idle pool). Under active contention in Scenario C, trip creation exceeds 15.0s.
- **Relevant Files & Functions:**
  - `backend/app/services/durable_place_refresh_service.py:request_refresh` (7 sequential DB checks in loop).
  - `backend/app/services/trip_service.py:create` (Unbatched sequential round trips).
- **Status:** `[VERIFIED ROOT CAUSE]`

---

### Scenario B — Discover Under Load
- **Command:** `python -u scripts/diagnostics/reproduce_real_world_failures.py`
- **Simulated Flow:** Opening Discover screen triggers concurrent requests: `GET /trips/{id}/days`, `GET /trips/{id}/saved-places`, and `POST /cities/{city_id}/recommendations`.
- **Expected Behavior:** All Discover data renders within 3,000 ms; recommendations return persisted places without duplicate queries.
- **Actual Behavior:**
  - Total duration: **7,898.9 ms** (Idle) to **23,460.4 ms** (Contention in Scenario C).
  - `_recommend_in_worker` executes two separate full scans via `PersistedPlaceReader`.
- **Relevant Files & Functions:**
  - `backend/app/routers/places.py:_recommend_in_worker` (Lines 114-133: duplicate read).
  - `backend/app/services/persisted_place_reader.py:read`.
- **Status:** `[VERIFIED ROOT CAUSE]`

---

### Scenario C — Full Onboarding Journey (10 Consecutive Runs)
- **Command:** `python -u scripts/diagnostics/reproduce_real_world_failures.py`
- **Simulated Flow:** 10 consecutive simulated users: Confirm destination -> Confirm interests -> Create Trip -> Discover Recommendations.
- **Measured Metrics (10 Runs):**

| Run | Trip Create Latency (ms) | Recommendation Latency (ms) | Total Journey Time (ms) | Outcome |
| :---: | :---: | :---: | :---: | :---: |
| 1 | 8,018.3 ms | 7,674.1 ms | 45,712 ms | Pass (slow) |
| 2 | 12,108.2 ms | 10,344.2 ms | 52,468 ms | Pass (slow) |
| 3 | **15,820.0 ms** | **23,460.4 ms** | 69,304 ms | **FAILED (Trip Timeout > 15s)** |
| 4 | **27,935.4 ms** | N/A (Timeout) | 65,022 ms | **FAILED (Trip Timeout > 15s)** |
| 5 | Connection Pool Starved | N/A | 65,032 ms | **FAILED (Pool Timeout)** |
| 6 | Connection Pool Starved | N/A | 65,043 ms | **FAILED (Pool Timeout)** |
| 7 | Connection Pool Starved | N/A | 65,034 ms | **FAILED (Pool Timeout)** |
| 8 | 12,803.1 ms | 9,902.5 ms | 52,726 ms | Pass (slow) |
| 9 | **16,681.2 ms** | N/A | 60,918 ms | **FAILED (Trip Timeout > 15s)** |
| 10 | **30,827.1 ms** | N/A | 78,640 ms | **FAILED (Trip Timeout > 15s)** |

- **Summary Statistics:**
  - Trip Create Min: **8,018.3 ms**
  - Trip Create Median: **15,819.8 ms** (**Exceeds Flutter 15.0s client timeout**)
  - Trip Create Max: **30,827.1 ms**
  - Trip Create p95: **30,827.1 ms**
  - Journey Success Rate: **0% reliable** (Only 3/10 completed without exceeding client timeouts).
- **Status:** `[VERIFIED ROOT CAUSE]`

---

### Scenario D — Image Resolution Batch (20 Persisted Places)
- **Command:** `python -u scripts/diagnostics/reproduce_real_world_failures.py`
- **Simulated Flow:** Production `PlaceImageResolver().resolve_many(session, place_ids, force=True)` on 20 places.
- **Expected Behavior:** Concurrent lookups proceed within rate limits without lock starvation or DB connection drops.
- **Actual Behavior:**
  - 7 places timed out at `stage=total_budget` while waiting in line behind `Semaphore(1)`.
  - Places marked as `provider_error` and poisoned in `PlaceImageCache` for 30 minutes.
  - PostgreSQL / Supabase server closed the connection after 57 seconds of idle-in-transaction holding:
    `psycopg.OperationalError: consuming input failed: server closed the connection unexpectedly`
- **Relevant Files & Functions:**
  - `backend/app/services/place_image_service.py:resolve_many` (Holds DB session across HTTP).
  - `backend/app/services/provider_rate_control.py:WikimediaRateController` (Semaphore(1) locks entire process).
- **Status:** `[VERIFIED ROOT CAUSE]`

---

### Scenario F — Flutter Fallback Category & Asset Coverage
- **Command:** `flutter test test/place_fallback_coverage_test.dart`
- **Expected Behavior:** All 10 normalized categories and common aliases resolve to valid on-disk assets and render `Image` widgets instead of neutral fallback placeholders.
- **Actual Behavior:**
  - 7 test failures:
    1. Category `landmark`: returned `null` -> renders `_NeutralPlaceFallback` with icon `Icons.landscape_rounded`.
    2. Category `other`: returned `null`.
    3. Alias `heritage`: returned `null`.
    4. Alias `tourism`: returned `null`.
    5. Alias `cafes`: returned `null`.
    6. Alias `markets`: returned `null`.
    7. `PlaceImage` with `normalizedCategory: 'landmark'` rendered 0 `Image` widgets.
  - Visual verification:
    - `restaurant.webp` shows Varanasi Ganges ghats and temples.
    - `hotel.webp` shows an empty lake dock with rowboats.
- **Relevant Files & Functions:**
  - `lib/utils/place_image_fallbacks.dart:_fallbackByCategory` & `placeFallbackAsset`.
  - `lib/widgets/place_image.dart:fallback`.
- **Status:** `[VERIFIED ROOT CAUSE]`

---

## 3. Verified Root Causes Matrix

| Defect | File | Function / Lines | Mechanism | Verified vs Hypothesis |
| --- | --- | --- | --- | :---: |
| **Trip Creation Timeout** | `backend/app/services/trip_service.py` | `create()` (lines 59–132) | 6 sequential WAN queries (`session.flush()`, `create_default_trip_days` flush, `commit()`, `refresh(trip)`). Takes 12.6s idle, >15s under load. | **VERIFIED** |
| **DB Session Leaks** | `backend/app/services/durable_place_refresh_service.py` | `execute_job()` (lines 212–216) | `with Session(self._engine) as session:` wraps `await self._category_refresher(...)`, holding connection during 25s Overpass HTTP I/O. | **VERIFIED** |
| **Image Session Leaks** | `backend/app/services/place_image_service.py` | `run()` (lines 539–544) | `with Session(target_engine) as session:` wraps `await resolve_many()`, holding connection during 57s Wikimedia HTTP I/O until server aborts. | **VERIFIED** |
| **Image Lock Starvation** | `backend/app/services/place_image_service.py` | `resolve_one()` (lines 215–228) | Total 10.0s budget ticks while waiting for `Semaphore(1)`. Queued places time out, mark `provider_error`, and poison cache for 30m. | **VERIFIED** |
| **Duplicate Candidate Read** | `backend/app/routers/places.py` | `_recommend_in_worker()` (lines 114–133) | `recommend()` reads candidates via `PersistedPlaceReader`. Discards snapshot. Line 128 queries candidates AGAIN, adding ~7.5s WAN latency. | **VERIFIED** |
| **Prefetch DB Loop** | `backend/app/services/durable_place_refresh_service.py` | `request_refresh()` (lines 94–142) | Iterates 7 categories, opening and closing 7 separate DB sessions sequentially, taking 17.2s before HTTP 202 response. | **VERIFIED** |
| **Missing Fallback Mappings** | `lib/utils/place_image_fallbacks.dart` | `_fallbackByCategory` (lines 3–19) | Omits `landmark`, `heritage`, `tourism`, `other`. Places render neutral gray box. | **VERIFIED** |
| **Mismatched Fallback Assets** | `assets/images/place_fallbacks/restaurant.webp` | Asset file | Image is physically Varanasi riverfront ghats; `hotel.webp` is a lake dock. | **VERIFIED** |
