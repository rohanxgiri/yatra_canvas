# Backend cached recommendation performance

Last reviewed: 2026-09-27

## 1. Test environment

`[IMPLEMENTED]` Measurements were taken from the YatraCanvas development host against a real
FastAPI/Uvicorn process and the configured remote PostgreSQL database. HTTP checks used Jaipur with
all seven requested categories and Ziro with its persisted recommendation set. Direct service
timings, SQL statement timings, PostgreSQL `EXPLAIN (ANALYZE, BUFFERS)`, provider-outage runs, and
six-request concurrency runs were recorded. Secrets and the complete connection URL were excluded
from this report.

## 2. Database environment

`[IMPLEMENTED]` Runtime settings and SQLAlchemy used the same target, identified only by fingerprint
`a5aba9103907`: PostgreSQL through the configured Supabase regional pooler, database `postgres`,
schema `public`. The process-wide engine uses `QueuePool(pool_size=15, max_overflow=15)` and
`pool_pre_ping=True`.

A transactionally consistent pre-migration copy remains in
`migration_backup_20260927t121718z`. Both reviewed parity migrations were committed on 2026-09-27,
then verified from a fresh connection. No ordered migration ledger exists; adopting one remains
`[PLANNED]`.

## 3. Request path

`[IMPLEMENTED]` The foreground route resolves the cached city and reads persisted recommendation
data in a worker thread. It ranks and serializes those rows without awaiting Geoapify, Audiala,
Overpass, Nominatim, Wikimedia, Foursquare, or another image provider. Stale or incomplete coverage
returns usable rows and schedules durable refresh intent asynchronously. Image-cache reads reuse
the recommendation snapshot; missing or expired image IDs are background refresh candidates.

## 4. Query inventory

Before this repair, the cached path made seven foreground database round trips:

1. city lookup;
2. eligible place candidate batch;
3. place tags/categories;
4. category coverage;
5. place-source provenance;
6. redundant page-level `Place` reload for image work; and
7. image-cache metadata.

`[IMPLEMENTED]` It now makes two:

1. city plus eligible candidates, all place tags, place sources, and image-cache metadata; and
2. category coverage.

## 5. Before measurements

Warm direct-service Jaipur samples were 4.01 and 4.22 seconds. Ziro samples were 3.92-4.40
seconds. SQL accounted for about 3.17-3.51 seconds and non-SQL work for 0.75-0.89 seconds.

Connection instrumentation measured a 7.23-second cold checkout and a 0.96-second first health
query. Warm checkout was 0.35-0.41 seconds and its `SELECT 1` health check was 0.72-0.91 seconds.
The user-supplied end-to-end baselines were approximately 7.8 seconds for Jaipur and 3.5 seconds
for Ziro.

## 6. Bottleneck

`[IMPLEMENTED]` The primary cached-response bottleneck was repeated remote database round trips,
not the SQL execution plan and not a foreground provider await. The post-change combined candidate
query executed on PostgreSQL in 2.761 ms (0.778 ms planning) and the coverage query in 0.053 ms
(0.125 ms planning). Existing `ix_places_city_id` and `ix_city_category_cache_city_id` indexes were
used. The remaining request time is dominated by remote transport, connection checkout/pre-ping,
and occasional contention with background workers.

A separate responsiveness failure was caused by refresh and image helpers doing synchronous
remote-database work on the FastAPI event loop. A stale Jaipur request could therefore delay the
next cached request and even the root health endpoint despite provider work being logically
background-only.

## 7. Changes made

`[IMPLEMENTED]` The repair:

- added one persisted candidate snapshot containing the city, eligible places, all place tags,
  source provenance, cached images, and image refresh IDs;
- reused that snapshot through ranking, serialization, and image enrichment;
- removed the redundant source, page-place, and image metadata reads;
- retained one separate coverage query to avoid a large Cartesian join;
- persisted stale refresh intent off the event loop and dispatched only the required categories;
- moved complete refresh-job execution and image enrichment batches into worker threads; and
- added regressions for the two-query invariant and event-loop responsiveness.

No new index was added because measured PostgreSQL plans were already sub-millisecond to low
single-digit milliseconds and showed no missing-index bottleneck.

## 8. After measurements

Direct worker measurements were 2.02-2.33 seconds for warm Jaipur and 1.75-1.80 seconds for Ziro.
Real HTTP measurements were:

| City | Result | Timing |
| --- | --- | --- |
| Jaipur | 20 persisted rows, refresh scheduled | 3.39-second warm median; 3.27-5.10-second samples |
| Ziro | 4 persisted rows, refresh idle | 1.71-1.76-second warm samples; 2.13-second cold request |

Relative to the supplied baselines, Jaipur's warm median improved by about 56%, and Ziro improved
by about 50%. The slower Jaipur outlier coincided with remote/background contention. The cached
foreground path still awaited zero providers.

## 9. Provider-outage measurements

`[IMPLEMENTED]` A separate Uvicorn process used intentionally unreachable Geoapify and Overpass
URLs while Audiala was disabled. Ziro returned HTTP 200 with 4 rows in 2.34 seconds and Jaipur
returned HTTP 200 with 20 rows in 3.73 seconds. An immediate root request returned HTTP 200 in
34 ms, and another after eight seconds returned in 106 ms. Provider `ConnectError` failures were
contained in background jobs and did not replace or suppress cached results.

## 10. Concurrent-request measurements

`[IMPLEMENTED]` Six simultaneous Ziro requests all returned HTTP 200 in a 4.21-second batch, with
individual requests completing in 1.85-4.21 seconds. Six simultaneous Jaipur requests all returned
HTTP 200 in a 4.12-second batch, with individual requests completing in 3.48-4.12 seconds. The root
endpoint remained responsive. Database inspection found no duplicate durable refresh-job keys;
one row per versioned city/category key coalesced refresh intent.

## 11. Remaining limitations

- `[PARTIAL]` The remote database path still has high connection/transport latency. Moving the API
  closer to PostgreSQL or using an environment-appropriate connection topology should be measured
  before changing correctness-oriented `pool_pre_ping` behavior.
- `[PARTIAL]` After the successful migration, restart, API, outage, and concurrency verification,
  two later redundant startup probes saw the remote pooler close the connection during SQLAlchemy
  dialect/`create_all` startup. No migration was rolled back and no request ran in those probes;
  this is an external connection-availability limitation to monitor.
- `[PARTIAL]` Refresh delivery uses process-local tasks. Durable job rows and leases survive, but
  recovery after total process loss requires another request; an always-on external worker is not
  implemented.
- `[PARTIAL]` The database-side migration snapshot is a verified rollback point, not a provider-
  managed disaster-recovery backup or point-in-time recovery test.
- `[PLANNED]` Adopt an ordered migration runner and immutable deployment ledger.
- `[UNKNOWN]` Physical-device latency was not re-measured during this backend-only repair.
