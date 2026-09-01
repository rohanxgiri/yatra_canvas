# YatraCanvas roadmap

Last reviewed: 2026-09-01

This roadmap is sequenced for reversible, testable changes. A phase is not complete until its
acceptance criteria pass in a local/test environment and the source-of-truth documents are
updated. It is not a release-date commitment.

## Phase 1 — Source of truth and configuration alignment

Status: `[IMPLEMENTED]` in the architecture-source-of-truth branch, pending review/merge.

Scope: document repository reality, provider responsibilities, model/migration constraints, and
the exact existing environment contract. Label old UI documentation as historical and add a
lightweight consistency test.

Acceptance criteria:

- Root `AGENTS.md` points future agents to the dated source-of-truth documents.
- Root README describes actual capabilities without presenting partial features as complete.
- Every Pydantic environment alias and Flutter's `API_BASE_URL` appears in
  `backend/.env.example` where applicable and in `docs/ENVIRONMENT_VARIABLES.md`.
- Backend/Flutter tests, analysis, secret scan, link/path check, and `git diff --check` are run or
  explicitly reported unavailable.

## Phase 2 — Versioned migrations, identity, and complete trip lifecycle

Status: `[PARTIAL]`. The current unauthenticated slices implement trip create/get/patch plus the
normal Flutter handoff into persistent saved-place list/add/update/reorder/delete operations.
The returned real `trip_id` is retained in memory and every saved-place mutation uses it.
Authentication, ownership, trip list/delete, restart persistence, and a versioned migration
runner remain planned.

Scope: adopt an ordered migration workflow; integrate Supabase Auth; add an application profile
only if product needs require it; create authenticated trip create/read/update flows; persist
dates, arrival point, purpose, and preferences. Do not enable direct Flutter database access
without tested RLS/grants.

Acceptance criteria:

- Fresh and upgraded test databases reach identical schemas through versioned migrations.
- Migrations include rollback/roll-forward notes and preserve nullable legacy Google IDs.
- FastAPI verifies Supabase JWTs and derives `user_id` rather than trusting request data.
- Trip ownership has positive/negative API tests; RLS is versioned and tested if tables are
  exposed through Supabase APIs.
- The normal Flutter create flow receives and retains a real trip ID and survives app restart.

## Phase 3 — Provider-neutral place ingestion foundation

Status: `[PARTIAL]` (`PlaceSource`, `PlaceCategory`, `PlaceImportReview`, and FSQ importer exist).

Scope: formalize ingestion-run tracking, source update/deletion behavior, canonical field
provenance/verification, and operator dry-run reports. Extend FSQ input only from the officially
documented OS schema; do not infer proprietary attributes.

Acceptance criteria:

- A bounded city extract can be imported idempotently with counts, provenance, licence ID, and
  unresolved flags retained.
- Add/update/close/merge or source-removal semantics are tested and documented.
- Ambiguous deduplication never overwrites canonical data and produces an auditable review task.
- Import-run status and failure recovery are visible without storing portal credentials in app
  configuration.

## Phase 4 — OSM/Overpass supplemental ingestion

Status: `[PARTIAL]`. A bounded, cached runtime Overpass slice now supplies normal POI
recommendations without a paid key. Extract-based ingestion, update/deletion lifecycle,
production hosting policy, and broader provenance review remain planned.

Scope: choose bounded regional extracts versus a compliant Overpass/self-hosted workflow,
normalize selected OSM tags through the same provenance boundary, and preserve ODbL attribution.
Do not use a public Overpass instance as an unbounded per-user runtime backend.

Acceptance criteria:

- A provider adapter/importer has fixtures, timeouts, rate limiting, retry/backoff, and a stable
  source/external-ID namespace.
- Host usage policy and commercial suitability are documented and approved.
- OSM attribution appears wherever OSM-derived data/maps are displayed.
- Cross-source matching routes ambiguity to review and has deletion/update semantics.

## Phase 5 — Wikimedia enrichment

Status: `[PLANNED]`.

Scope: enrich reviewed notable places with descriptions and images through a backend batch job.
Store revision/source identifiers and item-level creator/license/attribution, not merely an image
URL. Use a meaningful application User-Agent/contact.

Acceptance criteria:

- Enrichment cannot promote an unreviewed provider record to canonical without policy.
- Every displayed media item can render its required attribution and source link.
- Refresh/revision and removal behavior is tested; missing/ambiguous content is safely omitted.
- Requests follow current Wikimedia API etiquette and backoff guidance.

## Phase 6 — Geoapify completion and Google Places exit readiness

Status: `[PARTIAL]` (destination and arrival autocomplete use Geoapify; Google remains for
uncached POI discovery and legacy city endpoints; Geoapify city IDs are not persisted).

Scope: use the existing provider-neutral location boundary for city and arrival geocoding where
product tests prove parity. Build discovery from reviewed canonical ingestion rather than a new
Geoapify POI dependency. Backfill a non-Google canonical city identity strategy while preserving
legacy IDs.

Acceptance criteria:

- Destination and arrival flows work through application-owned schemas without a Google Places
  call and retain required Geoapify/OSM attribution.
- City resolution is idempotent without requiring `google_place_id`.
- Stored place coverage meets defined launch-city quality thresholds with review reports.
- Turning off Google Places in a test environment passes city/discovery tests and has a rollback
  flag/release plan.

## Phase 7 — openrouteservice and multi-day itinerary planning

Status: `[PLANNED]` road-routing adapter; current local-estimate/single-day implementation is
`[PARTIAL]` and the Google adapter is legacy only.

Scope: introduce a provider-neutral directions/matrix interface, select hosted versus self-hosted
openrouteservice, migrate cache semantics, and implement actual multi-day scheduling. Keep Google
Routes available until parity and fallback tests pass.

Acceptance criteria:

- Directions/matrix adapter fixtures cover partial elements, no-route, timeout, rate limit, and
  malformed responses without changing the public REST schema.
- Cache keys include provider/version/mode as needed; static versus volatile expiry is explicit.
- Optimizer respects trip days, locked/must-visit/priority rules, start point, and deterministic
  ordering in tests.
- A test deployment can disable Google Routes with complete cached/static fallback and explicit
  failure for missing legs.

## Phase 8 — Weather and currency

Status: `[PLANNED]`.

Scope: make a commercial-use/licensing decision for Open-Meteo before adding configuration;
implement dated forecast caching and attribution. Add Frankfurter daily reference rates with
provider/date provenance and calculate amounts in application code.

Acceptance criteria:

- Approved Open-Meteo deployment mode, terms, attribution, key/base URL, and cache policy are
  documented; a commercial app does not use the non-commercial endpoint improperly.
- Forecast responses show issue/valid time and degrade to explicitly stale data or no feature.
- Currency output shows rate date/base/quote and is described as reference information, not a
  settlement quote.
- Both adapters have timeout/error fixtures and no secret is shipped to Flutter.

## Phase 9 — Authorized admin verification tools

Status: `[PARTIAL]` schema and mock UI only.

Scope: replace hard-coded admin data with authenticated, role-authorized APIs for import review,
dedupe, corrections, source-quality decisions, and audit history.

Acceptance criteria:

- Non-admin users cannot read or mutate review/admin resources.
- Every canonical correction records actor, timestamp, before/after values, reason, and evidence.
- Merge/unmerge and destructive actions have preview, confirmation, and recovery behavior.
- Admin dashboards use real paginated data and expose ingestion/source health without secrets.

## Phase 10 — Verified Google retirement and map-rendering decision

Status: `[PLANNED]`.

Scope: retire Google Places and Routes independently after their replacements pass acceptance.
Separately choose a Flutter map renderer, tile provider, attribution, key restrictions, and
offline/cache policy. The current repo has no Google Maps SDK to migrate.

Acceptance criteria:

- Usage telemetry and code search show no call to the API being disabled; test deployment works
  without its key and a rollback release exists.
- Legacy IDs remain nullable provenance through the agreed retention period; any later deletion
  has verified backup/backfill and reversible migration review.
- Google Cloud APIs are disabled only after external deployment owners confirm no other consumer.
- The chosen map implementation renders place/route data, handles permissions and failures, and
  displays all required tile/data attribution on supported platforms.

## Cross-cutting work

Every phase must add structured, privacy-safe logging and metrics appropriate to its new paths,
keep provider payloads behind application schemas, update provider/license/environment docs, and
avoid production migrations or paid API probes during repository development. CI/deployment,
backup objectives, and production observability remain `[UNKNOWN]` until their infrastructure is
placed in scope.
