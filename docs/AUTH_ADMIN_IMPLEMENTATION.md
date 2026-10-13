# Authentication and integrated admin delivery

Implementation: 2026-10-07. Final verification: 2026-10-08. Repository implementation report.

`[IMPLEMENTED]` Follow up 2026-10-12 preserves the fixed local showcase login at user request,
prevents registered-account shadowing, adds scoped Overview and online place/report workflows, validates Lab evaluation evidence,
and discloses incomplete inventories. See [the current report](ADMIN_IMPLEMENTATION_REPORT.md).

The delivery labels requested by the user are used below. `[PARTIAL]`
maps to `[PARTIAL]` in the project's architectural source documents. Implementation
does not establish production deployment or physical device acceptance.

## 1. Existing architecture found, [IMPLEMENTED]

Flutter uses StatefulWidget, ChangeNotifier, Navigator, Inter and YCStyle. Traveller
screens use `LocalFirstClient`, native SQLite packs and local trip persistence, with
HTTP fallback. Login/signup and the separate admin entry had presentation scaffolding.
FastAPI already had bcrypt/JWT accounts, USER/ADMIN roles and protected admin queries.
Trip ownership used a development UUID; signup/reset delivery and audit were absent.
Manual SQL scripts coexist with SQLModel metadata, without an ordered migration runner.
The [preimplementation inspection](specs/0001-integrated-admin/rationale.md) records evidence.

## 2. Authentication changes, [IMPLEMENTED]

Dedicated login/signup/reset screens provide validation, autofill, show/hide passwords,
keyboard scrolling, loading, disabled actions, accessible errors and existing blue tokens.
Signup creates bcrypt USER accounts. Auth UI delegates to state/repository/storage layers.
Tokens and profiles persist in native secure storage; passwords are never persisted.
Expiry, rejected tokens, logout and late request cancellation are handled centrally.
`[PARTIAL]` Reset is an honest service response, no email delivery exists.

## 3. New routes, [IMPLEMENTED]

Startup enters AuthGate, which restores a session or displays the original onboarding
before login for signed-out launches. Completing or skipping the story opens login.
Verified sessions select traveller Home or integrated AdminShell; logout returns to login.
Signup/reset are dedicated routes. Identity transitions replace the experience navigator.
Legacy account/onboarding/admin entrypoints delegate to the same gate or role guard.
The original Home and Explore visual files have no changes.

## 4. Role architecture, [IMPLEMENTED]

UserRole centrally maps USER/ADMIN and denies unknown roles. Live backend role/activity
govern every privileged request. The user retained the development principal and fixed
`admin@yatracanvas.com` / `admin` credentials for local showcases on 2026-10-12. This requires
`ENABLE_DEV_ADMIN=true` and explicit development/test classification. It cannot shadow a
registered account, and registering that email revokes existing demo sessions. Production/staging
reject development flags and insecure signing configuration. The registered account bootstrap
CLI hashes an explicitly supplied password; email alone never grants access.

## 5. Admin architecture, [IMPLEMENTED]

One application contains five admin sections with independent navigation stacks:
Dashboard, City Lab, Trips, Users and More. Mobile destinations become a desktop rail.
Reusable paginated collections, async/retry/empty views, badges and readable records connect
to an injected repository. More contains Data Quality, Research, Packs, Health, Audit,
Settings and Logout. The old mock panel and fake metrics have been removed.

## 6. City Lab integration, [PARTIAL]

City Lab is a separate desktop Flutter tool without an API. The backend reads immutable
canonical releases and matching desktop `release.json` evidence. READY/REVIEW_REQUIRED/BLOCKED
vocabulary and actual exported scores are preserved. No report means NOT_CERTIFIED and no score.
Quality filters cover actual missing fields and broken media references. Place reviews edit
supported names/aliases/classification/description/coordinates/contact/hours, keep immutable
provider provenance, and persist KEEP/NEEDS_RESEARCH/EXCLUDE/KEEP_BOTH decisions with evidence.
Existing identity conflict groups drive duplicate review. Unsupported automatic merge,
provider-ID edits, image replacement and full desktop QA scoring remain in existing tooling.
The default city view follows the bundled app's source version when available; equal manifest
timestamps are explicitly ambiguous. Every release remains accessible through City Packs.

## 7. Trip inspection, [IMPLEMENTED]

Admin search covers trip/destination/traveller names, email and IDs, with traveller and
schedule-date filters. Detail shows persisted preferences, selections, day windows, rest
days, assignment locks, visits/status, distance and travel legs. Unscheduled selections are
derived from saved-minus-itinerary records. Historical reasons and solver score breakdowns
are `[UNKNOWN]` because they were not stored. Admin reads never optimize or modify a trip.
All traveller trip resources enforce ownership; legacy records are preserved without reassignment.

## 8. User management, [IMPLEMENTED]

Paginated name/email search and role filters expose actual profile, role, active state,
creation time and trip count. Confirmed activation/role changes are server checked and
audited; self deactivation/demotion is guarded. User trip inspection uses the same trip views.
Last activity is honestly unavailable; no invented activity or aggregate preference profile.

## 9. Research/DataFactory integration, [PARTIAL]

Backend imports existing DataFactory task generation, priorities/evidence rules, identity
groups and field validators. Research acceptance is manual, requires compatible corrections
and evidence, and never publishes automatically. Accepted field reviews and approved place
reviews combine into an existing schema 1 base-bound, checksummed patch ZIP; conflicting
values/excluded targets block export. Applying a canonical patch remains the existing
reviewed DataFactory CLI workflow. Media tasks remain reviewable but media import stays in Lab.

## 10. City-pack integration, [PARTIAL]

Release versions are inspectable. Validate and Build call existing DataFactory validation
and app projection routines, producing backend artifacts outside canonical repositories.
Validation/build audit supplies real recent results. No installed app asset is modified.
Remote publish, canonical patch apply and lifecycle worker status are [PLANNED]
in this backend. Existing native offline pack search, trip creation and upgrades are retained.

## 11. System health, [PARTIAL]

SQL job states, failed jobs, cache/stale rows, image states and recorded provider cooldowns
are real. Provider summaries show configuration and explicitly say connectivity is not
probed. Raw error/lease data and keys are excluded. Monitoring, metrics/alerts, measured
provider availability and production retention remain deployment work.

## 12. Audit log, [IMPLEMENTED]

Admin SQL mutations and review/export/build/validation actions append actor/action/entity/
city/time and safe before/after evidence. SQL mutation and audit share a transaction.
Review writes reject stale release/review revisions. Paginated audit APIs support actor,
city, entity, action and date filters; UI offers these filters, search and event detail. Deployment
database grants and append-only retention controls are [PARTIAL].

## 13. Backend endpoints, [IMPLEMENTED]

See the complete method/path contract in [APIs and data sources](API_AND_DATA_SOURCES.md).
Added signup/reset, city/quality/place reviews/media/duplicates, canonical summary, research,
pack validation/build/export/download, health/jobs and audit. Extended existing user/trip/
moderation APIs with auditing, owner enforcement and meaningful trip filters.

## 14. Migrations, [IMPLEMENTED]

`backend/sql/add_admin_operations.sql` adds only audit/review tables and indexes.
`rollback_admin_operations.sql` archives all rows instead of dropping their data.
Startup schema creation is now restricted to explicit development/test.
No remote or production migration was applied. Live PostgreSQL deployment acceptance is
[PARTIAL]; disposable data-preservation and PostgreSQL syntax checks are provided.

## 15. Flutter files changed, [IMPLEMENTED]

Auth: `main.dart`, `main_admin.dart`, `models/auth_controller.dart`, `auth_session.dart`,
`yatra_session.dart`, `services/auth_repository.dart`, `authenticated_client.dart`,
`local_first_client.dart`, `screens/auth/*`, legacy onboarding entrypoints and Profile logout.
Admin: `admin_app.dart`, guarded `admin_panel_screen.dart`, `data/admin_repository.dart`,
`widgets/admin_components.dart`, collection/dashboard/shell/city/place/research/trip/user/
operational screens. Added secure storage dependency, generated Windows plugin registration
and disabled Android application backup. Home/Explore source files are unchanged.

## 16. Backend files changed, [IMPLEMENTED]

Core config/auth/dev_auth/trip_access; auth/admin/admin_operations/trips routers;
auth/admin schemas; admin_operations models and exports; admin_audit/admin_city_lab services;
TripService owner-aware replay; main router/startup; env example, optional requirements-admin,
reviewed forward/rollback scripts. Seven source documents and this report record the changes.

## 17. Tests added, [IMPLEMENTED]

`test_integrated_auth_admin.py` covers signup, no role escalation, reset honesty, opt-in/revoked
demo tokens, live roles/deactivation, every trip resource guard, stale reviews, patch integrity,
source preservation, audit and migration rollback. Opt-in `test_admin_datafactory_integration.py`
calls the actual Jaipur task generator, validator, pack builder and patch unpacker.
Flutter controller/gate tests cover roles, restart/offline/expiry/logout/races and forms.
Responsive admin tests exercise every operation at 320 px with large text and desktop.
Offline SQLite tests prove guest/account separation, no legacy reassignment and account restart.
`[IMPLEMENTED]` The 2026-10-12 guest correction supersedes compulsory traveller authentication:
onboarding opens Home and token-free trip APIs reuse the original shared guest namespace.
See [guest restoration](GUEST_MODE_RESTORATION.md) for current behavior and verification.
Legacy tests now seed the explicit development actor and assert the secured entry behavior.

## 18. Verification evidence, [PARTIAL]

The final full backend suite passed 482 tests with one optional adapter test skipped. The
configured backend pass ran 11 tests, including the real Jaipur DataFactory adapter. The full
Flutter suite passed 320 tests, including native SQLite account isolation, audit filter requests
and accessible desktop/mobile navigation. Flutter analysis reported no issues, and Ruff
passed for changed runtime files and new tests. Existing unrelated backend Ruff findings remain.
Real Jaipur task generation, release validation, app pack build and imported patch contract pass
with unchanged canonical fingerprints. PostgreSQL syntax parsing and disposable forward/archival
rollback checks pass. No live PostgreSQL deployment was performed.

Runtime verification used `http://127.0.0.1:5055` against an isolated in-memory SQL database
and the real immutable release directory. Login errors, honest reset response, direct admin
routing and Jaipur v5 selection were observed at 390 px. A canonical Albert Hall photo loaded
through authenticated media requests. At 1440 px, every sidebar destination was present in
the accessibility tree. Running Jaipur validation created a real CITY_VALIDATED audit record;
action/city filters and event detail were exercised against that record. Mobile and desktop screenshots and
command logs are saved under ignored `tmp/`. The SQL database intentionally contains no
production accounts or trips. Physical Android/iOS storage and motion measurements remain
[PARTIAL] in this host environment because no mobile device or emulator is attached.

## 19. Remaining limitations, [PARTIAL]

No reset delivery, email verification, production identity provider, remote publish, automated
canonical apply/merge, mobile image file import, historical planner score/reason persistence,
traveller history restore UI or migration runner. City Lab scores need its genuine version
matched export. Native offline SQLite is preserved; web auth is memory only and the existing
SQLite offline architecture has no web replacement. Host renders cannot prove device behavior.
The checkout lacks the requested Wanderlog screenshot directory, so existing tokens and the
supplied design direction guided the auth/admin UI.
Granular support/editor roles, unsupported-city telemetry and a full analytics pipeline are
[PLANNED]. Existing roles and reliable dashboard aggregates provide extension points.

## 20. Production-security TODOs, [PARTIAL]

Replace temporary development admin auth with managed secure identity before production.
Configure strong signing keys and explicit environment classification, managed identity/reset
delivery, rate limiting, email verification, refresh/revocation/session policy, restricted
deployment CORS, controlled migrations, database grants/retention and artifact access policy.
Physically test secure storage on supported platforms. Keep canonical imports/publish under
their reviewed release process. Supabase remains the accepted future identity direction.

## Local development setup

Use a disposable/local PostgreSQL database and `APP_ENV=development`. Register an administrator
with `python -m app.scripts.create_admin` and its secure password prompt, or opt in to the
fixed showcase identity with `ENABLE_DEV_ADMIN=true`. Keep `ALLOW_DEV_GUEST=false` for authenticated online
flows. Normal online and native offline guest planning need neither a token nor a guest flag. Set `API_BASE_URL` to that
backend. Install `backend/requirements-admin.txt` in its virtual environment, then set trusted
`DATAFACTORY_CHECKOUT`, `ADMIN_RELEASE_ROOT` and a separate `ADMIN_ARTIFACT_ROOT`.
Matching City Lab exports go under `lab_reports/<release-key>/release.json` in that artifact
root. Credentials, provider keys and runtime .env files are never committed.

See [environment inventory](ENVIRONMENT_VARIABLES.md), [architecture](ARCHITECTURE.md),
[data model and rollback notes](DATA_MODEL.md), and [ADR-028](DECISIONS.md#adr-028--integrated-local-jwt-authentication-and-operational-admin).
