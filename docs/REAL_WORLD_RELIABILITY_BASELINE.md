# Real-World Reliability & Concurrency Baseline

**Document status:** `[IMPLEMENTED]`
**Recorded on:** 2026-09-21
**Commit baseline:** `785d787975603323ec4d252a22245d5cfc082297`
**Git Branch:** `main`

---

## 1. Repository State

- **HEAD Commit**: `785d787` (`chore(observability): trace discover and refresh pipeline`)
- **Branch**: `main`
- **Working Tree Status**:
  - Modified: `AGENTS.md`, `docs/PROJECT_CONTEXT.md`
  - Untracked: `.agents/skills/*`, `docs/AGENT_WORKFLOW.md`, `docs/POST_REFACTOR_DISCOVER_PERFORMANCE_IMAGE_AUDIT.md`, `docs/scope/`

---

## 2. Test Suites & Analysis Baseline

| Suite / Check | Command | Result | Execution Time |
| --- | --- | --- | --- |
| Backend Pytest Suite | `python -m pytest tests -q --basetemp ../.pytest_tmp_baseline -p no:cacheprovider` | **462 passed, 4 warnings** | 524.27s (~8m 44s) |
| Flutter Discover/Flow Tests | `flutter test test/place_discovery_test.dart test/recommendation_cache_test.dart test/prefetch_live_discovery_test.dart test/place_image_test.dart test/place_discovery_progressive_state_test.dart test/trip_creation_test.dart` | **54 passed, 0 failed** | 8.2s |
| Flutter Static Analysis | `flutter analyze` | **No issues found!** | 80.3s |

---

## 3. Database & Engine Configuration

- **Dialect / Driver**: `postgresql+psycopg` (Psycopg 3)
- **Host Region**: `ap-southeast-2` (Sydney, Australia: `aws-0-ap-southeast-2.pooler.supabase.com:5432`)
- **Engine Setup**: `create_engine(settings.sqlalchemy_database_url, pool_pre_ping=True)` (`backend/app/database.py:17`)
- **SQLAlchemy QueuePool Configuration**:
  - `pool_size`: **5** (default)
  - `max_overflow`: **10** (default)
  - `pool_timeout`: **30.0s** (default)
  - Total Maximum Connections: **15**
- **Observed Network Latency**: ~350ms – 500ms round-trip time between local client in India and database in Australia.
- **Cold Connection Acquisition / TLS Handshake**: **6,658 ms**

---

## 4. Operational Timeouts & Limits Baseline

| Parameter | Configuration Location | Configured Value |
| --- | --- | --- |
| Flutter Trip Creation Timeout | `lib/services/trip_service.dart:19` | **15.0 seconds** (`Duration(seconds: 15)`) |
| Flutter Prefetch Timeout | `lib/services/place_prefetch_service.dart:34` | **15.0 seconds** |
| Geoapify Request Timeout | `backend/app/core/config.py:68` | **8.0 seconds** |
| Overpass Request Timeout | `backend/app/core/config.py:122` | **25.0 seconds** |
| Interactive Discovery Timeout | `backend/app/core/config.py:268` | **12.0 seconds** |
| Route Geometry (OSRM) Timeout | `backend/app/core/config.py:314` | **10.0 seconds** |
| Weather Provider Timeout | `backend/app/core/config.py:334` | **10.0 seconds** |
| Image Resolver Timeout | `backend/app/core/config.py:88` | **5.0 seconds** |
| Image Resolution Item Budget | `backend/app/services/place_image_service.py:220` | **10.0 seconds** (`place_image_timeout_seconds * 2`) |
| Image Batch Schedule Limit | `backend/app/services/place_image_service.py:47` | **20 places** (in 10-item waves) |
| Image Provider Concurrency | `backend/app/core/config.py:94` | **4 concurrent workers** (`asyncio.Semaphore(4)`) |
| Wikimedia Process Limiter | `backend/app/services/provider_rate_control.py:231` | **1 concurrent worker** (`asyncio.Semaphore(1)`) |
| Refresh Worker Concurrency | `backend/app/services/city_place_prefetch_service.py:39` | **Up to 7 concurrent threads** (`asyncio.to_thread`) |

---

## 5. Image Cache State Baseline (`place_image_cache`)

Measured from active database query on 2026-09-21:

| Metric | Measured Value | Percentage |
| --- | --- | --- |
| **Total Cached Place Rows** | **337** | 100.0% |
| **`status = 'failed'`** | **216** | **64.1%** |
| **`status = 'not_found'`** | **111** | **32.9%** |
| **`status = 'resolved'`** | **10** | **3.0%** |
| **Failure Reasons** | `provider_error`: **216** | 100% of failed |
| **Providers for Resolved Rows** | `wikimedia`: **10**, `geoapify`: **0**, `foursquare`: **0** | |
| **Shillong Cached Rows** | **64** (38 failed, 26 not_found, **0 resolved**) | **0% resolved** |

---

## 6. Runtime Performance Baseline (Measured)

| Operation | Baseline Measured Duration | Underlying Bottleneck |
| --- | --- | --- |
| **Trip Creation (In-Process `create()`)** | **12,681.41 ms** | Cold TLS handshake (6.6s) + 6 sequential DB operations (6.0s) |
| **Trip Creation (HTTP `POST /trips`)** | **11,016.91 ms** (idle) / **>15,000 ms (timeout)** under prefetch | QueuePool contention with 7 background prefetch threads |
| **Discover Recommendations (HTTP)** | **Run 1 (queued refresh): 14,906 ms**<br>**Run 2 (active refresh): 25,773 ms**<br>**Run 3 (idle): 6,476 ms** | Double candidate read + connection starvation during Overpass/Geoapify queries |
| **DB Candidate Query (`PersistedPlaceReader.read()`)** | **7,519.25 ms** | Executed TWICE in `_recommend_in_worker()` |
| **Image Resolution Batch (10 items)** | **>10,000 ms** (timed out on queued items) | Wikimedia `Semaphore(1)` forces queued items to exceed 10.0s deadline |
