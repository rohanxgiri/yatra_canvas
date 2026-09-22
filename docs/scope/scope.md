# Scope: Real-World Reliability & Concurrency Repair

**Build approach:** Tracer Bullet (vertical end to end reliability slices)
**Workflow:** GA

## At a glance

| # | Feature | Phase | Status |
| --- | --- | --- | --- |
| 1 | Baseline & Environment Characterization | Phase 1 | in-progress |
| 2 | Execution Model & Resource Contention Audit | Phase 2 | planned |
| 3 | Real-World Concurrency & Failure Reproduction | Phase 3 | planned |
| 4 | Database Session Ownership & Connection Decoupling | Phase 4 | planned |
| 5 | Trip Creation Batching & Round-Trip Reduction | Phase 5 | planned |
| 6 | Recommendation Candidate Read Deduplication | Phase 6 | planned |
| 7 | Image Resolution Concurrency & Queue Decoupling | Phase 7 | planned |
| 8 | Poisoned Image Cache Selective Recovery | Phase 8 | planned |
| 9 | Local Fallback Assets & Semantic Category Mapping | Phase 9 | planned |
| 10 | Prefetch Amplification & Redundant Dispatch Control | Phase 10 | planned |
| 11 | Structured Latency & Contention Observability | Phase 11 | planned |
| 12 | End to End Real-World Verification & Multi-City Validation | Phase 12 | planned |

---

## Phase 1: Baseline & Pre-Fix Truth

### 1. Baseline & Environment Characterization · GA
Measure and record the exact pre-fix state of the repository, test counts, engine pool, WAN latency, and database cache statistics.
Done when: `docs/REAL_WORLD_RELIABILITY_BASELINE.md` records measured facts without assumptions or exposed secrets.
- [x] Record git commit, branch, test suites, engine settings, and cache distribution
- [x] Document remote database host region and WAN latency factors

---

## Phase 2: Audit & Failure Reproduction

### 2. Execution Model & Resource Contention Audit · GA
Trace the exact Flutter onboarding journey through destination selection, dates, arrival, interests, preferences, trip creation, and Discover.
Done when: Full execution graph identifies all shared resources between foreground endpoints and background workers.
- [ ] Map all foreground and background calls
- [ ] Identify shared connection pool, threadpool, and event loop bottlenecks

### 3. Real-World Concurrency & Failure Reproduction · GA
Build an automated real-world test harness simulating true Flutter concurrency without artificial waits.
Done when: New integration/stress tests fail on the current code, reproducing the 15s trip creation timeout, discover slowdown, image failures, and fallback defects before any fixes are applied.
- [ ] Build harness in `backend/tests/integration/`
- [ ] Reproduce Scenarios A through F
- [ ] Document failure evidence in `docs/REAL_WORLD_FAILURE_REPRODUCTION.md`

---

## Phase 3: Architecture & Development

### 4. Database Session Ownership & Connection Decoupling · GA
Ensure no database session remains open across external provider network calls (Overpass, Geoapify, Wikimedia, OpenMeteo).
Done when: Provider HTTP calls run strictly outside DB session boundaries, eliminating connection pool starvation.
- [ ] Refactor `DurablePlaceRefreshService`
- [ ] Refactor `CityPlacePrefetchService`
- [ ] Refactor `OpenStreetMapDiscoveryService`
- [ ] Refactor `PlaceImageResolver`

### 5. Trip Creation Batching & Round-Trip Reduction · GA
Eliminate sequential WAN round trips in `TripService.create()` and defensively expand client timeout.
Done when: Trip creation completes in < 3.0s under warm conditions and does not time out under background prefetch.
- [ ] Batch `Trip`, `TripPreference`, and `TripDay` inserts
- [ ] Eliminate unnecessary post-commit `session.refresh(trip)`
- [ ] Set defensive 30s timeout in `lib/services/trip_service.dart`

### 6. Recommendation Candidate Read Deduplication · GA
Remove the redundant second candidate read in `_recommend_in_worker()`.
Done when: `PersistedPlaceReader.read()` executes exactly once per recommendation request.
- [ ] Reuse initial candidate snapshot
- [ ] Verify ordering and pagination semantics are preserved

### 7. Image Resolution Concurrency & Queue Decoupling · GA
Decouple worker queue wait from provider execution timeout and prevent Wikimedia Semaphore(1) starvation.
Done when: Batch image resolution no longer triggers cascading 10.0s timeouts for queued places.
- [ ] Apply per-place execution budgets rather than batch-level deadlines
- [ ] Preserve rate limits without poisoning queued candidates

### 8. Poisoned Image Cache Selective Recovery · GA
Selectively reset poisoned `status='failed'` cache rows attributable to queue timeouts.
Done when: Places falsely marked failed are given a clean opportunity to resolve without clearing valid rows.
- [ ] Target `status = 'failed'` rows with `failure_reason = 'provider_error'`
- [ ] Record before and after cache statistics

### 9. Local Fallback Assets & Semantic Category Mapping · GA
Correct semantically invalid fallback assets and wire missing category fallbacks.
Done when: Food places display food imagery, hotel places display lodging imagery, and landmark/heritage/tourism places map to valid local assets.
- [ ] Replace `restaurant.webp` with authentic food imagery
- [ ] Replace `hotel.webp` with authentic lodging imagery
- [ ] Map `"landmark"`, `"heritage"`, and `"tourism"` in `lib/utils/place_image_fallbacks.dart`
- [ ] Wire `generic_place.webp` before neutral fallback

### 10. Prefetch Amplification & Redundant Dispatch Control · GA
Deduplicate prefetch triggers and prevent redundant worker thread dispatch.
Done when: Repeated prefetch calls for active or recent categories do not check out connections or spawn threads.
- [ ] Optimize prefetch trigger handling
- [ ] Verify lease checks avoid threadpool allocation

### 11. Structured Latency & Contention Observability · GA
Add lightweight structured timing logs for database checkout wait, provider duration, and trip creation stages.
Done when: Operational diagnostics surface latency hotspots without log flooding.
- [ ] Add timing events for trip creation, recommendations, and refresh
- [ ] Log pool checkout wait times

---

## Phase 4: Validation & Handoff

### 12. End to End Real-World Verification & Multi-City Validation · GA
Re-run the exact failing test harness across 10 consecutive runs and across 7 representative cities (Shillong, Manali, Rishikesh, Goa, Jaipur, Varanasi, Udaipur).
Done when: All scenarios pass, full backend and Flutter suites pass, and the implementation report is finalized.
- [ ] Run Scenarios A through F on corrected code
- [ ] Validate 10 consecutive full journeys
- [ ] Validate multi-city data
- [ ] Complete `docs/REAL_WORLD_RELIABILITY_IMPLEMENTATION_REPORT.md`
- [ ] Reconcile source-of-truth documents
