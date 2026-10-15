# Android deployment and validation

Verified: 2026-10-14. This document describes internal physical phone testing, not store distribution.

## Configuration and boundaries

`[IMPLEMENTED]` The public backend origin is `https://yatra-canvas.onrender.com`.
Release builds default to it, and the reproducible script passes it explicitly. The installed
APK talks directly to that HTTPS origin; USB and a local backend are not application requirements.
Debug native Android defaults to `http://10.0.2.2:8000`; desktop/web development defaults to
`http://localhost:8000`. `API_BASE_URL` overrides either mode. Use an HTTP(S) origin with no
credentials, path, query or fragment. Trailing slashes are normalized.

`[IMPLEMENTED]` Prepared Jaipur retains the existing local-first path even while online.
Its city/places, local search, selections, days, itinerary and approximate route overview use
the bundled SQLite pack and separate device trip store. Unsupported cities and server trips use
Render. No canonical pack format, provider, city identity, authentication requirement or schema
was changed. Home, Explore, onboarding, typography and admin layouts were preserved.

`[IMPLEMENTED]` Native Saved > Places in your trips (also Profile > Trip history) reads up to
100 recent local trip records from the current account file. It preserves session plans, rejects
late results after an identity change and offers storage retry. After restart, open that history
and the trip details/Continue planning/map actions to reopen the saved local itinerary.
`[PARTIAL]` Remote trip history and cross-device guest/account sync remain unavailable.

## Render setup

`[IMPLEMENTED]` Repository configuration for an existing Render Python web service:

| Setting | Value |
| --- | --- |
| Root directory | `backend` |
| Build command | `pip install -r requirements.txt` |
| Start command | `uvicorn app.main:app --host 0.0.0.0 --port $PORT` |
| Health path | `/`, a lightweight process check, not database readiness |
| Runtime | A Python version compatible with the installed requirements |

The public deployment responds; actual dashboard settings, commit and tier are `[UNKNOWN]`
without dashboard access. Do not redeploy or run SQL automatically to align them.

Required deployment names, never client values: `DATABASE_URL`, `APP_ENV` (classify as
`production`), and a private `JWT_SECRET_KEY` of at least 32 bytes. Keep `ENABLE_DEV_ADMIN`
and `ALLOW_DEV_GUEST` false. Guest planning does not require either flag. `GEOAPIFY_API_KEY`
is needed for provider autocomplete; stored cities/places and Jaipur packs do not require it.
`JWT_ALGORITHM`, `JWT_ACCESS_TOKEN_EXPIRE_MINUTES` and all optional provider/admin settings
are documented in [the environment inventory](ENVIRONMENT_VARIABLES.md) and `backend/.env.example`.
DataFactory/admin release paths are optional adapter configuration, not required for traveller startup.

The app has no database/provider secrets. Existing CORS and admin authorization were not weakened.
Android native HTTPS does not require adding a browser CORS wildcard. Production startup must use
reviewed schema deployment, not development `create_all`. Supabase Auth remains planned, separate
from the existing local JWT accounts.

Provider documentation verified 2026-10-14: [Render FastAPI](https://render.com/docs/deploy-fastapi),
[Render Free](https://render.com/docs/free), [Render logging](https://render.com/docs/logging),
[Supabase connections](https://supabase.com/docs/guides/database/connecting-to-postgres),
[Flutter Android deployment](https://docs.flutter.dev/deployment/android),
[Android app signing](https://developer.android.com/studio/publish/app-signing).

## Build and install

From the Flutter root in PowerShell:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --flavor regular --release --dart-define=API_BASE_URL=https://yatra-canvas.onrender.com
```

The preferred script preserves an existing regular release APK in a unique
`build/releases/archive/<timestamp>-<id>/` directory before building. It records origin, bytes,
SHA-256 and signing status in a companion `.build.json` file only after a successful build.
Its staging override requires HTTPS and rejects credential-bearing URLs.

```powershell
.\tools\build_android_release.ps1
# When the same revision has already passed analyze/test:
.\tools\build_android_release.ps1 -SkipValidation
# Explicit HTTPS staging origin:
.\tools\build_android_release.ps1 -ApiBaseUrl https://your-staging-origin.example
```

The manual Flutter command overwrites its output; use the script when preserving a previous APK.
For regular release, the observed output is `build/app/outputs/flutter-apk/app-regular-release.apk`.

```powershell
.\tools\install_android_release.ps1
.\tools\install_android_release.ps1 -DeviceId YOUR_ADB_DEVICE_ID
# Equivalent SDK command, retaining application data:
$androidAdb = "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe"
& $androidAdb devices -l
& $androidAdb -s YOUR_ADB_DEVICE_ID install -r build\app\outputs\flutter-apk\app-regular-release.apk
```

The install script detects authorized targets, rejects absent/ambiguous targets and uses `install -r`.
It does not uninstall, downgrade or clear data. A signing/version conflict is a reported failure;
do not resolve it by clearing data. It launches the regular package after installation.

To install on a second phone, transfer the same APK using Files, cloud storage or another transfer
method you choose. Open it on that phone and allow installation from that source if Android asks.
Alternatively enable USB debugging, select its ADB ID and run the install script again. Each
phone has independent offline trip files. No laptop address, USB reverse mapping or account is
required for guest planning. Disconnect USB after installation.

Future internal updates use the same build/install commands. Increment the `pubspec.yaml`
version/build number deliberately when managing versioned releases; the current package is
`com.yatracanvas.yatra_canvas`, version `0.1.0+1`. Keep the same signing key for upgrades.
Admin remains a separate `.admin` package/flavor, with the current shared application entry.
Its explicit build entry is `--flavor admin --target lib/main_admin.dart`.

Local development:

```powershell
flutter run --flavor regular --debug
flutter run --flavor regular --debug --dart-define=API_BASE_URL=http://YOUR_LAPTOP_LAN_IP:8000
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

The existing debug manifest allows local cleartext HTTP. The release script requires HTTPS;
release networking policy was not loosened for local HTTP overrides.

## Confirm Render and troubleshoot

Read the APK's adjacent `.build.json` origin/hash. Search for an unprepared city such as Agra or
Ziro on the phone; Jaipur intentionally comes from the pack and does not prove network access.
Match that activity with Render's service Logs view and existing path/status/timing records.
Trip/Discover requests preserve the existing non-secret `X-Request-ID`; do not paste credentials,
tokens, personal payloads or database URLs into logs or reports. No ADB reverse mapping is needed.

Canonical city search allows 65 seconds because it may wake an idle Render service. It remains
asynchronous and cancellable; an exhausted deadline shows retry instead of an empty search result.
The subsequent autocomplete budget remains 10 seconds, trip creation 30 seconds, recommendations
and optimization 45 seconds, and optional pack enrichment four seconds. Other existing deadlines
are unchanged. GETs retry at most once after one second for a connection error or
429/500/502/503/504. A longer/date-form `Retry-After` suppresses automatic retry. Writes are sent
once; a deliberate trip creation retry reuses the draft's existing request ID. JSON parse errors
remain errors, and loaded selections/cards remain available through the existing UI states.

For timeout/DNS failure, check phone internet, wait for Render startup and retry; inspect service
events/logs for suspension or restart. Compare HTTPS `/` and `/cities?limit=1`. A successful root
with failing city reads points toward the backend/database path. Invalid HTML/JSON is not an
empty result. For 429 wait for the server cooldown; for persistent 5xx inspect Render logs.
Do not disable certificate validation or increase every request deadline.

For Supabase errors, inspect the exception type in private Render logs. Check that the deployed
`DATABASE_URL` targets the intended project/database and the documented direct/pooler connection
mode, SSL and credentials. Confirm project availability and connection limits in Supabase.
Dashboard credentials and the full production catalog were unavailable to this task. Successful
public reads show a populated application database, but do not prove RLS, full schema parity,
correct project identity or every write table. If an undefined table/column appears, record its
exact name and compare `backend/sql/README.md` dependency order/model metadata in a read-only
catalog audit. Review a backup and reversible migration in staging before a separately approved
production change. Never run historical SQL scripts blindly, reseed or reset the database.

Render Free, if that is the selected tier, idles after 15 minutes and can take about one minute
to restart. Its local files are ephemeral, and usage limits can suspend the service. Process-local
caches/tasks can be lost. Supabase data and device city packs/trips have different storage lifecycles.
These limitations make this an internal testing setup; no paid service or keep-alive loop was added.

## Jaipur offline acceptance

On the regular APK, enter as guest, choose Jaipur, set dates and a confirmed hotel/station/custom
coordinate start, choose interests and create the local trip. Search bundled Jantar Mantar,
Suraj Pol Gate and Jaipur Junction. Select several places, configure days/rest days, generate
an itinerary and open the map. Then disconnect Wi-Fi/mobile data and repeat. Local trip IDs start
with `offline_`; bundled photos/fallbacks and route overview remain available. Close/relaunch,
use Saved > Places in your trips, and reopen the plan/map. No app-data clear is needed.

`[PARTIAL]` Offline geometry is an explicitly labelled coordinate overview, not road navigation.
Street tiles, live weather and external services are unavailable offline. Local scheduling uses
the existing bounded planner, not OR-Tools parity. Broader imagery/description/transport coverage
depends on the existing prepared data. Test-only media is not a certified licensed release.

## Future distribution signing

`[PARTIAL]` Release currently uses the development debug key. It is suitable for internal testing,
not production/store distribution. AAPT/apksigner verification confirmed `CN=Android Debug`.
The existing `.gitignore` excludes keystores, `key.properties` and local secrets.

For distribution, create and safely back up a private upload/release keystore outside Git, following
the official Flutter/Android guides linked above. Supply `storeFile`, `storePassword`, `keyAlias`
and `keyPassword` through an untracked `android/key.properties` or the build secret manager.
Update `android/app/build.gradle.kts` to load it into a release signing configuration, validate
missing values, select that configuration for release and verify the resulting certificate with
`apksigner verify --print-certs`. Update the build metadata's signing label at that time. Retain
the original signing identity for installed updates; switching from the debug key prevents an
in-place upgrade. Do not uninstall or erase existing test trips automatically to solve that.

## Validation record, 2026-10-14

`[IMPLEMENTED]` Initial audit: URL override and internet permission already worked; clients used
one configured origin, pack/trip storage and guest flow existed, and UI had loading/retry states.
Gaps were a local release fallback, no automatic safe-read retry, missing persisted local history
presentation and missing reproducible build/install tooling. Release signing was development only.

| Production read | Actual result |
| --- | --- |
| `GET /` | 200, `status=ok`, `service=YatraCanvas API` |
| `GET /docs` | 200, Swagger HTML |
| `GET /cities?limit=1` | 200, populated Agra row |
| `GET /cities?limit=100` | 200, 29 cities |
| `GET /cities/search?query=Jaipur` | 200, canonical Jaipur UUID and coordinates |
| `GET /cities/autocomplete?query=Ziro` | 200, provider city suggestions |
| `GET /locations/autocomplete?query=Ziro&type=city&country_code=in&limit=2` | 200, Geoapify results |
| `GET /cities/{jaipur_uuid}/places?limit=2` | 200, populated place/image/hour schema |
| `GET /cities/{jaipur_uuid}/places/search?query=Hawa&limit=2` | 200, Hawa Mahal from database with image metadata |
| `GET /places/prefetch/{jaipur_uuid}` | 200, ready, 348 eligible POIs across seven categories |
| `GET /openapi.json` | 200, existing trip/request ID/day/optimization contracts present |
| `GET /api/auth/me`, no token | 401, expected protected response |

The first city-search probe accidentally used `q` and returned 422; the correct `query` request
passed. `[PARTIAL]` Live OpenAPI lacks `/api/auth/signup`, `/api/auth/forgot-password` and newer
admin operations such as `/api/admin/city-lab/*` and `/api/admin/system-health`. This indicates
deployment contract drift, not proof of a specific missing PostgreSQL column. Newer account/admin
features require a separately validated/authorized deployment. No backend deployment was performed.

Automated validation: `flutter pub get` passed; `flutter analyze` clean; full Flutter suite
369 passed, one live test skipped by default. The same GET-only live test passed when explicitly
enabled with `flutter test test/production_api_smoke_test.dart --dart-define=RUN_PRODUCTION_READS=true`.
Backend config, database safety and trip/auth/core-flow checks passed (52 distinct tests) with
disposable SQLite and a nonproduction connection placeholder. Documentation/correlation checks
also passed (nine additional distinct tests). PowerShell syntax checks, credential-origin rejection,
and absent/multiple/unauthorized device and installation-failure fixtures passed. The actual
compile-time Render override was tested. Both regular and admin release flavors built successfully.
No production SQL test/migration ran. The two first-run environment-default failures were caused
by forcing `APP_ENV=test` in the runner; rerunning those tests without that override passed.
No unrelated test expectation was weakened and existing screen goldens remain unchanged.

## Files changed by this delivery

| Files | Change and reason |
| --- | --- |
| `lib/config/api_config.dart` | Hosted release default, preserved development/override modes, safe origin validation |
| `lib/services/backend_client.dart` | Existing HTTP retry library, GET only, bounded transient retry and cooldown handling |
| `lib/services/authenticated_client.dart`, `lib/services/auth_repository.dart`, `lib/admin/data/admin_repository.dart` | Use the safe transport by default without changing authentication/role rules |
| `lib/services/city_service.dart` | Initial canonical search cold-start deadline, cancellation, friendly network failures |
| `lib/services/local_first_client.dart` | Read recent current-account persisted local trip drafts using the unchanged SQLite format |
| `lib/models/trip_draft.dart` | Preserve persisted original creation request ID when decoding |
| `lib/screens/account/account_screens.dart` | Reuse existing Trip History, loading/retry and identity checks for restored local plans |
| `lib/screens/trip_map/trip_map_screen.dart`, `test/trip_map_test.dart` | Report tile failures once, retry only on user action, retain route/markers, and guard retry after map disposal |
| `tools/build_android_release.ps1`, `tools/install_android_release.ps1` | Reproducible hosted release, archive/hash metadata, safe target selection and data-retaining installation |
| `test/api_config_test.dart`, `test/backend_client_test.dart` | Release/development resolution, invalid config, bounded retry, cooldowns, write safety, JSON failures |
| `test/offline_trip_history_test.dart`, `test/offline_city_pack_test.dart` | Restart/history/request-ID/account isolation and existing local planning regressions |
| `test/account_screens_test.dart` | Inject an empty offline store in existing presentation tests; golden expectations unchanged |
| `test/production_api_smoke_test.dart` | Explicit opt-in live GET/model compatibility checks, skipped in ordinary regression runs |
| `backend/.env.example`, `docs/ENVIRONMENT_VARIABLES.md` | Public define/test-switch documentation only; no backend secret/config code change |
| `docs/PROJECT_CONTEXT.md`, `docs/ARCHITECTURE.md`, `docs/API_AND_DATA_SOURCES.md`, `docs/DATA_MODEL.md`, `docs/ROADMAP.md`, `docs/DECISIONS.md`, this file | Surgical source-of-truth/deployment/evidence updates |

Existing uncommitted offline-admin/authentication work was preserved. No scope row matched this
explicit deployment request; no scope/spec was advanced or replaced. No commit, push, migration,
database reset, keystore creation, provider connection or backend deployment was performed.

## Physical phone evidence

Device: Samsung Galaxy S23 (`SM_S911B`), Android 16, regular development-signed release.
ADB upgrade installation and both warm/cold launches returned success. App data was retained.
Mobile-data checks ran with `wifi_on=0`, `mobile_data=1` and no ADB reverse mappings.
The final APK also loaded canonical Ziro/provider suggestions on Wi-Fi with `wifi_on=1` and
`mobile_data=0`. Offline checks ran with both values zero. Original settings were restored:
Wi-Fi off, mobile data on and `stay_on_while_plugged_in=0`.

| Acceptance area | Actual result |
| --- | --- |
| A, launch/navigation | Passed: supported onboarding Skip, guest Home, Explore and Create Trip |
| B, destinations | Passed: live Agra search/selection and Panjim provider suggestions on mobile data; prepared Jaipur offline selection. New provider city resolution/repeated creation was not performed on production; canonical resolution regressions passed locally. |
| C, online trip | Passed: Agra, 14–15 October, city-centre start, culture/sightseeing, balanced pace. Creation handed off into Discover and subsequent UUID-typed saved-place endpoints accepted the trip. |
| D, places | Passed: live recommendations, Taj Mahal/Chini Ka Rauza saves, manual Agra Fort search/save, all three selected; Jaipur local Jantar Mantar/Suraj Pol Gate search/save with no internet. |
| E, itinerary | Passed: Agra Day 1 had Agra Fort and Chini Ka Rauza, Day 2 Taj Mahal; three selections retained. Jaipur local planner placed one selected stop on each of two days. Rest/window/lock edge cases passed automated tests; separate physical edits to those constraints were not run. |
| F, map | Passed: mobile-data OSM street tiles and road geometry; markers/route retained when data was disabled and uncached tiles could not load. The new failure notice/retry and disposal behavior passed widget tests. |
| G, offline/restart | Passed: Jaipur preparation, bundled station origin, local search/planning and explicit offline route overview. After actual force-stop/cold relaunch, Saved > Places in your trips restored Jaipur; trip details retained two selections and the persisted map reopened without internet. |

The Agra functional flow intentionally created one real guest trip, selections and itinerary in
the hosted database. These test records were left intact. Public connectivity probes themselves
were GET only. The Jaipur trip remained device-local. No production record was deleted or reseeded.
The online trip confirms database write-path connectivity for the exercised tables; full production
schema/RLS/project identity and newer admin/auth parity still require privileged read-only diagnostics.

`[PARTIAL]` A second phone, actual USB unplug/laptop shutdown, all device
permission branches, cold Render inactivity measurement and privileged admin/optional signup remain
outside the completed phone checks. The mobile-data/no-reverse result establishes direct hosted
connectivity, but does not replace those separate acceptance scenarios. Signed-out relaunch preserves
the existing onboarding behavior; Skip opens guest Home. Remote online trip history is not restored.

Screenshots and detailed test output are retained locally under ignored `scratch/phone-*.png` and
`scratch/*validation.log`; they contain app test screens, not credential/dashboard captures.
Builds printed the existing Kotlin migration warning; both flavors currently compile successfully.

## Final artifact

`[IMPLEMENTED]` Final regular output: `build/app/outputs/flutter-apk/app-regular-release.apk`,
107,559,053 bytes (102.58 MiB), SHA-256
`E96F74567C785266A2110A38BA52AA0A86F9256DF8203782873824DCB3DF9A3A`.
The final update installed successfully and cold-launched; the existing Jaipur history remained
after upgrade. Development signing was verified, not inferred from a successful build.
Package `com.yatracanvas.yatra_canvas`, minimum SDK 24 (Android 7.0), target/compile SDK 36,
ABIs arm64-v8a/armeabi-v7a/x86_64. Admin release compilation and `.admin` identification
also passed; privileged physical admin operations were not exercised.

Latest analysis is clean. After the full 369-test run, the additional late map-retry disposal
guard passed the complete seven-test map suite before the final rebuild. No current automated
test failure remains. Pending checks must not be inferred from automated passes.

Overall status: **PARTIALLY READY, REMAINING ISSUES**. The built/installed regular APK's guest
online/offline flows are usable for physical testing. Newer hosted optional auth/admin contracts,
full production catalog/security verification and the remaining device scenarios above remain open.
