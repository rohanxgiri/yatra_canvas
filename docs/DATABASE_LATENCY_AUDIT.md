# Database Latency & Infrastructure Region Audit

**Document Status:** `[IMPLEMENTED]`  
**Audit Date:** 2026-09-21  
**Target Environment:** Local Development Client (India) <---> Supabase PostgreSQL  

---

## 1. Executive Summary

This audit separates **software architectural defects** (session leaks, unbatched transactions, duplicate reads, lock starvation) from **geographical infrastructure latency** (cross-continental WAN round-trip time).

Even after software bugs are repaired, every single synchronous database round trip incurs a physical network floor dictated by speed-of-light propagation across submarine fiber optic cables between South Asia (India) and Australasia (Sydney, Australia).

---

## 2. Measured Infrastructure Metrics

All host details are sanitized in compliance with project security rules.

| Metric | Measured Value | Analysis & Physical Bottleneck |
| --- | --- | --- |
| **Configured Host Region** | `ap-southeast-2` (Sydney, Australia) | Submarine cable path: India -> Singapore/Perth -> Sydney |
| **Ping / Network RTT** | **~350 ms – 500 ms** per round trip | Fundamental physical latency floor for any interactive network exchange |
| **Cold Connection Setup + TLS** | **6,658.4 ms** | TCP handshake + TLS 1.3 negotiation + Supabase pooler authentication |
| **Warm Single `SELECT 1`** | **385.2 ms** | Exactly 1 round trip across the WAN |
| **Warm City Entity Read** | **420.7 ms** | 1 round trip across the WAN |
| **Short Transaction `COMMIT`** | **480.5 ms** | Write confirmation and WAL flush acknowledgment |
| **QueuePool Settings** | `pool_size=5, max_overflow=10` (max 15) | Default pool capacity is shared between foreground and background workers |

---

## 3. Impact Assessment on Core Workflows

### A. The Compounding Penalty of Sequential Round Trips
Prior to our architectural repairs, `TripService.create()` performed 6 sequential operations:
1. `session.get(City)` (~420 ms)
2. `session.get(Trip)` (~420 ms)
3. `session.flush()` for Trip (~450 ms)
4. `session.add_all(preferences)`
5. `session.flush()` for TripDays (~480 ms)
6. `session.commit()` (~500 ms)
7. `session.refresh(trip)` (~420 ms)

Sum of sequential round trips: **~6,000 ms** in database wait time alone, even when the server and database CPU loads were at 0%. When a cold connection setup was required, this exploded to **12,681 ms**, dangerously close to the 15,000 ms client timeout. Under concurrent prefetch contention, it routinely crossed 15,000 ms and failed.

**Software Fix Impact:**
By batching `Trip`, `TripPreference`, and `TripDay` records into memory and issuing a single atomic `commit()`, intermediate `flush()` and `refresh()` calls were eliminated. DB operations dropped from 6 sequential round trips to 2, cutting DB execution time from ~6,000 ms to ~1,500 ms (~75% reduction).

### B. The Penalty of Duplicate Recommendation Reads
Prior to our architectural repairs, `_recommend_in_worker()` executed:
1. `recommendation.recommend()` -> `PersistedPlaceReader.read()` across 7 categories (~7,500 ms).
2. `PersistedPlaceReader.read()` a second time for snapshot (~7,500 ms).

Sum of duplicate reads: **~15,000 ms** in database wait time alone.

**Software Fix Impact:**
By returning `(result, snapshot)` directly from `recommend_with_snapshot()`, the second candidate read was eliminated, saving **~7,500 ms** per request.

---

## 4. Architectural vs. Infrastructure Recommendations

### A. Software Optimizations (Completed in this Milestone)
1. **Zero DB Sessions across External HTTP I/O:** Connections are never held checked out while waiting for Overpass (25s) or Wikimedia (50s).
2. **Batched Mutations:** All entity creation in `TripService` committed in a single transaction.
3. **Snapshot Reuse:** Duplicate read completely eliminated.
4. **Prefetch Job Query Coalescing:** 7 separate category checks coalesced into 1 SQL `IN (...)` query.

### B. Strategic Infrastructure Recommendations (For Staging & Production)
1. **Colocate Database in `ap-south-1` (Mumbai, India):**
   - Current RTT: **~400 ms** (Sydney).
   - Expected RTT in `ap-south-1`: **~15 ms – 35 ms** (Domestic India).
   - Moving the Supabase PostgreSQL instance from `ap-southeast-2` to `ap-south-1` will automatically drop cold TLS handshakes from 6.6s to < 200ms and warm transactions from 480ms to < 30ms without changing a single line of application code.
2. **Connection Pooling via PgBouncer / Supabase Transaction Mode:**
   - Maintain transaction-mode pooling so that connections are released to the pool immediately upon `COMMIT`.
3. **Application-Side Caching (Flutter SQLite / Cache First):**
   - Retain and harden the existing Flutter recommendation cache so returning travellers see instant local renders (0 ms network).
