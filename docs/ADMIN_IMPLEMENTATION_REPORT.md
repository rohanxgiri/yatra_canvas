# Admin Studio audit and delivery, 2026-10-12

`[IMPLEMENTED]` Startup follow up restores the existing four-screen onboarding for signed-out
launches, with login at completion or Skip. Restored sessions and logout retain their protected
role routing. The introduction's existing visual design and animations are preserved.

`[IMPLEMENTED]` The functional admin foundation has been verified and refined on
`codex/admin-studio-quality-overhaul`. `[PARTIAL]` The complete five phase data operations
platform remains a longer delivery. This report distinguishes existing work from this refinement.

## 1. Audit summary

The main checkout began on `main` with substantial uncommitted integrated auth/admin work.
It was preserved and inspected, not replaced or blindly merged. The requested experimental
`feature/admin-phase1-live-foundation` ref was absent from local and fetched refs in all three
checkouts. No remote merge, push or production write was performed.

CityPack Lab is locally available on `main`. Its actual QA export, manual review model and
release gate were inspected. DataFactory is also on `main`, with preexisting deleted/inaccessible
release artifacts. Neither sibling repository was edited. Root instructions and the seven
source documents govern the existing Flutter/FastAPI stack and release ownership.

| Finding | Evidence and disposition |
| --- | --- |
| `[IMPLEMENTED]` Main Flutter admin already used live APIs | Current uncommitted `AdminRepository`, role gate, collection/detail screens and backend routers supersede the earlier mock dashboard |
| `[IMPLEMENTED]` Backend and legacy web admin already offered moderation/reports | Flutter had no corresponding reachable online place/report workflow; now added |
| `[PARTIAL]` Optional adapters could hide all overview data | A single `Future.wait` failed the whole page; sources now load and fail independently |
| `[PARTIAL]` Counts and activity lacked clear scope | Backend accounts/trips/catalog, canonical releases and device-only trips now have explicit boundaries |
| `[PARTIAL]` Lab evidence was trusted by city/version alone | Schema, finite scores, reviews and gate consistency are now validated; content binding remains missing |
| `[PARTIAL]` Unreadable metadata stopped release discovery | Real browser verification reproduced this; readable releases remain visible with incomplete-inventory diagnostics |
| `[PARTIAL]` Review and identity races | Report/moderation conflict checks and previous-identity response rejection added |
| `[UNKNOWN]` Visual reference assets | `design_reference/wanderlog/` is absent. Existing YatraCanvas tokens guide the UI |

## 2. Implemented improvements

`[IMPLEMENTED]` Overview uses independent bounded requests, source labels, local refresh times,
honest zero/unavailable states, explicit errors and retained successful data after refresh failure.
Real metric/activity cards open relevant users, trips, online places, reports or city details.
Unreadable release metadata is disclosed; returned counts are limited to readable sources.

`[IMPLEMENTED]` Collections keep filters, debounce search, reject stale responses, clear rows
when the query changes, and retry a failed refresh from the correct page. Navigation initializes
sections on first use instead of fetching every hidden section at startup.

## 3. UI and UX

`[IMPLEMENTED]` Flutter retains its existing typography, blue/navy accents and neutral surfaces.
Reusable `AdminMetricCard` and `AdminNotice` accompany existing cards, status badges, dialogs,
error/empty states and record sections. Metric layouts adapt to width and text scaling.

Primary navigation is Overview, City Quality, Trips, Users and Operations. Operations groups
Online Place Manager, Place Reports, Fix Center, Review Queue, City Releases, System Health,
Audit Log and Settings. Existing city selection, issue drill-down and canonical review screens
are reused. `[PLANNED]` Trip Testing has no placeholder navigation entry.

Desktop uses the existing persistent rail; phones use compact bottom navigation and readable
lists/forms. Widget checks cover 320 px with 1.6 text scaling and 1440 px. Browser checks cover
desktop, phone and tablet widths. These checks do not establish full WCAG or physical device certification.

## 4. Backend integration and sources

| Display or action | Actual source and scope |
| --- | --- |
| Registered users | `User` SQL rows, excluding the ephemeral showcase identity |
| Recorded trips and activity | `Trip` and related backend records; device-only offline trips are excluded |
| Online places and moderation | `Place`, `PlaceSource`, opening hours, tags and `PlaceReport` |
| Enabled destinations | `City.is_enabled`, separate from connected offline/canonical cities |
| Reports | Real submitted records, status/reason/text/city/place filters, live detail and audited decisions |
| Canonical places and issues | Selected immutable DataFactory releases; readable inventory only |
| Quality and readiness scores | Validated CityPack Lab schema 1 evaluation, or null with an explanation |
| Jobs and providers | Recorded job/cache/cooldown state and configuration; no dashboard connectivity probes |
| History | Existing append-only backend audit API and actor/before/after evidence |

`[IMPLEMENTED]` Added report GET detail and list search/city/place filters. Dashboard adds UTC
`refreshed_at` and recent report place IDs. Optional report `expected_updated_at` and moderation
`expected_moderation_status` reject conflicting decisions with 409. PostgreSQL row locking
serializes those checks; audit and SQL changes share a transaction. Legacy clients remain compatible.
No table, environment variable, provider or migration was added by this refinement.

## 5. City Lab integration

`[IMPLEMENTED]` Existing DataFactory task, field validation, identity, patch and app pack routines
remain the adapter boundary. No duplicate quality scoring or planner algorithm was introduced.
Canonical files are read only; review overlays and exports remain backend artifacts.

`[IMPLEMENTED]` The Lab reader checks real schema 1 fields: city/version, release source, finite
0–100 scores, manual counts/minimum, gate checks, critical blocker count and evaluation time.
A READY report contradicting its own review/check evidence is rejected. Missing, malformed or
mismatched reports produce no assumed scores. Automated/backend reviews are not counted as Lab QA.

`[PARTIAL]` The inspected Lab export has no canonical content fingerprint. `reported_gate_status`
preserves its result, while canonical READY is withheld without content binding. This does not
change Lab's scoring or release rules. It prevents a version label alone certifying different bytes.

## 6. Data accuracy and release lifecycle

`[IMPLEMENTED]` Image counts here measure local reference/file completeness, not authentic
photography, image decoding, licensing or human verification. Hours completeness is not confirmed
operating information. Zero evidence never becomes a perfect QA score. Missing evaluations show
Unavailable/Not Certified, with the source boundary visible.

Online moderation applies to the backend catalog. Report resolution records a decision; it does
not itself repair a place or publish a pack. Canonical place corrections remain reviewed overlays
until validated/exported and applied through DataFactory to a new immutable release. Lab review,
certification and explicit app synchronization remain distinct. No publication or canonical write
was performed. Bundled Jaipur database/manifest fingerprints and asset diffs remain unchanged.

`[PARTIAL]` Only Jaipur is currently listed in this app's bundled city-pack index. Udaipur, Varanasi
and Manali were not added, rebuilt or claimed available in the traveler app. The readable canonical
inventory is a separate source. Existing sibling release deletions/permissions need their own repair.

## 7. Authentication and security

`[IMPLEMENTED]` Registered accounts retain bcrypt/JWT authentication and live backend role/activity
checks. Optional sign-in selects the protected admin or traveler experience. Default traveller
onboarding opens guest Home; logout removes the prior stack and returns to guest Home. Explicit
account/admin entry retains sign-in. Native secure persistence and guest
offline behavior are reused. Admin JSON/media responses from a previous identity are rejected.

The user explicitly requested keeping fixed local showcase credentials on 2026-10-12:

| Setting | Showcase value |
| --- | --- |
| Email | `admin@yatracanvas.com` |
| Password | `admin` |
| Environment | `APP_ENV=development` or `test` |
| Opt-in flag | `ENABLE_DEV_ADMIN=true` |

`[IMPLEMENTED]` This is an ephemeral test identity, not a stored production password. It does not
shadow a registered account at that email. Disabling the flag or registering that email revokes
demo sessions. Staging/production reject development flags. Email alone never grants privileges.
Demo login and registered login were both verified through the main app/local API.

`[PARTIAL]` Managed identity, refresh/revocation policy, email verification/reset delivery, deployment
rate limiting, restricted production CORS and physical secure-storage acceptance remain open.

## 8. Tests and observed evidence

| Command | Executed result |
| --- | --- |
| `flutter analyze` | No issues; final pass after UI/filter changes |
| `flutter test` | 325 passed in the final source run; log is `tmp/admin-studio/flutter-final.log` |
| `flutter test test/admin_studio_test.dart` | 5 passed, including partial-source refresh, slow sources, identity race, report confirmation/revision and filter/retry behavior |
| `flutter test test/admin_studio_test.dart test/admin_panel_test.dart test/offline_city_pack_test.dart` | 22 passed before the final added filter regression; covers real SQLite/guest/account and responsive navigation |
| Backend `python -m pytest -q` | 491 passed, 1 skipped in 365.13 s before the final inventory/showcase refinements |
| Backend focused auth/admin/config/database suite | 53 passed after showcase restoration, registered-account precedence and evidence-type checks |
| `python -m unittest tools.test_sync_city_pack` | 1 passed using the existing DataFactory virtual environment |
| `flutter build web --dart-define=API_BASE_URL=http://127.0.0.1:5057` | Passed, including Wasm dry run; existing Cupertino font warning remains |
| Python `compileall` for touched runtime modules | Passed |
| Task-scoped `git diff --check` | Passed with CRLF accounted for |

The first city-pack unittest attempt failed because the app virtual environment lacks `pyarrow`.
It passed with the already-installed DataFactory runtime, without installing dependencies. Ruff
could not run in the app environment because its module is absent; no Ruff success is claimed.
The optional real DataFactory adapter pytest remained skipped in the full backend run. Deployment
PostgreSQL concurrency, physical phones and production publication were not exercised.

The local browser used disposable SQLite accounts and genuine read-only canonical releases, with
no production users/trips. Backend counts honestly showed the empty operational database. Warm
HTTP observations: dashboard 200 in 0.01 s, city list 200 in 0.95 s, summary 200 in 1.07 s, eight
readable selected cities and four unreadable metadata entries. These are host observations, not SLAs.
Jaipur v5 selection, Albert Hall search and authenticated image loading, unknown evaluation evidence,
Operations navigation, wrong-password rejection, demo login and logout were observed.

Screenshots: [desktop](screenshots/admin-studio-20261012-desktop.jpg),
[phone city quality](screenshots/admin-studio-20261012-mobile.jpg),
[tablet](screenshots/admin-studio-20261012-tablet.jpg).
Local command logs and pack fingerprints are under ignored `tmp/admin-studio/`.

## 9. Important files

Backend: `core/auth.py`, `core/dev_auth.py`, `routers/auth.py`, `routers/admin.py`,
`routers/admin_operations.py`, `schemas/admin.py`, `services/admin_city_lab.py`,
`tests/test_integrated_auth_admin.py` and the environment example.

Flutter: `admin/data/admin_repository.dart`, `admin/widgets/admin_components.dart`,
`admin/screens/admin_dashboard_screen.dart`, `admin_shell.dart`, `admin_collection_screen.dart`,
`catalog_screens.dart`, `city_lab_screens.dart`, `test/admin_studio_test.dart` and responsive tests.
The seven source documents, existing admin guides, README and this report record the changes.
Existing uncommitted user work remains in place. No commit or push was requested/performed.

## 10. Remaining work, in priority order

1. `[PARTIAL]` Bind genuine Lab evaluation/certification to the exact canonical release and media
   inventory, with explicit reviewed import. Repair inaccessible/deleted sibling artifacts separately.
2. `[PARTIAL]` Complete global Fix Center severity/ownership/history workflows and structured
   correction publication tracking. Current per-city issue/research/review flows are reused.
3. `[PLANNED]` Reproducible admin Trip Testing using the actual local/server planner and recorded
   inputs/results. Existing read-only trip inspection remains available; no replacement planner exists.
4. `[PARTIAL]` Desktop media ingestion and canonical patch/app-pack validation need the configured
   DataFactory dependencies. This backend environment currently lacks `pyarrow`.
5. `[PARTIAL]` Production identity, controlled migration deployment, physical device verification,
   broader pack bundling, detailed media/hash validation and measured scale benchmarks.

## 11. How to run locally

Use a disposable/local PostgreSQL database configured in untracked `backend/.env` with the
reviewed schema. No command below authorizes a production migration. From the repository root:

```powershell
.\venv\Scripts\Activate.ps1
Set-Location backend
$env:APP_ENV='development'
$env:ENABLE_DEV_ADMIN='true'
$env:ALLOW_DEV_GUEST='false'
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

In a second repository terminal:

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Sign in with the fixed showcase credentials above when no registered account uses that email.
For normal registered admin setup, disable `ENABLE_DEV_ADMIN` and run
`python -m app.scripts.create_admin --email admin@yatracanvas.com` from `backend/`; use its secure
password prompt. A registered account always uses its own password and backend role.

Optional curation uses the already documented `ADMIN_RELEASE_ROOT`, `DATAFACTORY_CHECKOUT` and
separate `ADMIN_ARTIFACT_ROOT`, plus `backend/requirements-admin.txt` installed in the backend
runtime. Matching genuine Lab exports belong under `lab_reports/<release-key>/release.json`.
No scores, users or trip histories are fabricated when these sources are absent.

## 12. Delivery boundary

`[IMPLEMENTED]` Functional foundation/refinement and the verified review/evidence safeguards are
delivered locally. `[PARTIAL]` The complete Travel Data Operations and Quality Management System
is not declared finished. The existing integrated-admin spec remains In Progress for its physical
device/production requirements; no roadmap milestone was marked complete from host tests alone.
