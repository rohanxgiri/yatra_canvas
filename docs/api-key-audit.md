# YatraCanvas API key and environment audit

Audit date: 2026-08-31; provider responsibilities updated 2026-09-01

Branch: `chore/api-key-configuration-audit`

This report covers the tracked Flutter, Android, web, Windows, FastAPI,
SQLModel, tests, SQL, dependency manifests, documentation, ignore rules, and
Git history. The local `backend/.env` was parsed by name only: it contains only
`DATABASE_URL`, is ignored by Git, and was not changed. No iOS, Docker,
deployment, or CI/CD configuration exists in this revision.

Classification is based on executable references, not provider names. In the
tables below, **required** means required for the backend as a whole to start;
provider keys are **optional** because only their corresponding implemented
feature stops when the key is absent.

## Required now

| Variable | Provider | Required/Optional/Unused | Location | Backend/Client | Secret? | Used by | Missing behaviour | Recommended action |
| -------- | -------- | ------------------------ | -------- | -------------- | ------- | ------- | ----------------- | ------------------ |
| `DATABASE_URL` | PostgreSQL (Supabase PostgreSQL is supported) | Required | `backend/app/core/config.py`, `backend/app/database.py`, `backend/.env.example` | Backend only | Yes; normally embeds a password | SQLModel engine, API startup, FSQ importer | Settings validation fails and the backend cannot initialize its database | Set in `backend/.env` or the deployment secret store; never put it in Flutter |

There is no globally required third-party **API key**. `DATABASE_URL` is the
only required secret configuration value.

## Optional

| Variable | Provider | Required/Optional/Unused | Location | Backend/Client | Secret? | Used by | Missing behaviour | Recommended action |
| -------- | -------- | ------------------------ | -------- | -------------- | ------- | ------- | ----------------- | ------------------ |
| `GOOGLE_PLACES_API_KEY` | Google Places API (New) | Optional legacy integration, `[DEPRECATED]` for normal flows | `backend/app/core/config.py`, legacy city/discovery routers and services, `backend/.env.example` | Backend only | Yes | Explicit legacy autocomplete/details/discovery endpoints | Legacy calls return a safe `503`; normal Geoapify destinations and OSM recommendations continue | Leave empty unless deliberately testing legacy endpoints |
| `GOOGLE_ROUTES_API_KEY` | Google Routes API | Optional legacy integration, `[DEPRECATED]` for normal flows | `backend/app/core/config.py`, `backend/app/services/google_routes_service.py`, `backend/.env.example` | Backend only | Yes | Retained adapter only | Normal optimizer continues with local estimates | Leave empty unless deliberately testing the legacy adapter |
| `GEOAPIFY_API_KEY` | Geoapify | Optional implemented integration | `backend/app/core/config.py`, `backend/app/routers/locations.py`, `backend/app/services/geoapify_service.py`, `backend/.env.example` | Backend only | Yes | `/locations/autocomplete` for location autocomplete/geocoding | Endpoint returns a safe `503`; unrelated features continue | Add only for location autocomplete; keep it server-side |
| `GEOAPIFY_BASE_URL` | Geoapify | Optional override; safe default exists | `backend/app/core/config.py`, `backend/app/routers/locations.py`, `backend/.env.example` | Backend | No | Geoapify client base URL | Defaults to `https://api.geoapify.com` | Keep the default unless using a controlled compatible endpoint |
| `GEOAPIFY_TIMEOUT_SECONDS` | Geoapify | Optional tuning; safe default exists | Same Geoapify settings and router files | Backend | No | Outbound autocomplete timeout | Defaults to `8` seconds | Keep the documented default unless measured behaviour requires a change |
| `GEOAPIFY_AUTOCOMPLETE_CACHE_TTL_SECONDS` | Geoapify | Optional tuning; safe default exists | Same Geoapify settings and router files | Backend | No | In-memory autocomplete cache | Defaults to `300` seconds | Keep the default or tune within validation bounds |
| `OVERPASS_API_URL` | OpenStreetMap/Overpass | Optional override; safe public default exists | OSM services, settings, and `.env.example` | Backend | No | Normal bounded POI recommendations | Defaults to the documented public endpoint | Treat public service as best-effort; evaluate self-hosting/extracts for production |
| `OVERPASS_TIMEOUT_SECONDS` | OpenStreetMap/Overpass | Optional tuning; safe default exists | OSM services, settings, and `.env.example` | Backend | No | Outbound query timeout | Defaults to `25` seconds | Keep within validated bounds |
| `OVERPASS_RADIUS_METERS` | OpenStreetMap/Overpass | Optional tuning; safe default exists | OSM services, settings, and `.env.example` | Backend | No | Bounded city POI area | Defaults to `8000` metres | Keep bounded to limit public-instance load |
| `FSQ_OS_PLACES_PATH` | Foursquare Open Source Places | Optional local path | `backend/app/core/config.py`, `backend/app/cli.py`, `backend/.env.example` | Backend/CLI | No credential; local path may be operationally sensitive | Default input path for `import-fsq-places` | Import requires an explicit `--source` instead | Set only for local/import environments; do not add a Foursquare API token |
| `FSQ_DEDUPE_DISTANCE_METERS` | Foursquare Open Source Places importer | Optional tuning; safe default exists | `backend/app/core/config.py`, `backend/app/cli.py`, `backend/.env.example` | Backend/CLI | No | Importer candidate matching radius | Defaults to `75` metres | Keep or tune conservatively per city density |
| `FSQ_IMPORT_BATCH_SIZE` | Foursquare Open Source Places importer | Optional tuning; safe default exists | `backend/app/core/config.py`, `backend/app/cli.py`, `backend/.env.example` | Backend/CLI | No | Import commit batching | Defaults to `250` | Keep unless import testing justifies another value |
| `ROUTE_MATRIX_TRAFFIC_TTL_MINUTES` | Application / Google Routes cache | Optional tuning; safe default exists | `backend/app/core/config.py`, `backend/app/routers/route_optimization.py`, `backend/.env.example` | Backend | No | Traffic-aware route cache freshness | Defaults to `30` minutes | Keep or tune within validation bounds |
| `PLACE_DISCOVERY_CACHE_TTL_HOURS` | Application / Google Places cache | Optional tuning; safe default exists | `backend/app/core/config.py`, `backend/app/services/place_discovery_service.py`, `backend/.env.example` | Backend | No | POI discovery cache freshness | Defaults to `24` hours | Keep or tune within validation bounds |
| `GOOGLE_NEARBY_RADIUS_METERS` | Google Places | Optional tuning; safe default exists | `backend/app/core/config.py`, `backend/app/services/place_discovery_service.py`, `backend/.env.example` | Backend | No | Nearby POI search radius | Defaults to `10000` metres | Keep or tune within the validated Google limit |
| `PLACE_POPULAR_MIN_RATING` | Application | Optional tuning; safe default exists | `backend/app/core/config.py`, `backend/app/services/place_discovery_service.py`, `backend/.env.example` | Backend | No | Popular-place classification | Defaults to `4.2` | Keep unless product requirements change |
| `PLACE_POPULAR_MIN_REVIEW_COUNT` | Application | Optional tuning; safe default exists | `backend/app/core/config.py`, `backend/app/services/place_discovery_service.py`, `backend/.env.example` | Backend | No | Popular-place classification | Defaults to `100` | Keep unless product requirements change |
| `API_BASE_URL` | YatraCanvas API | Optional client build setting; safe development default exists | `lib/config/api_config.dart` | Flutter client | No | All Flutter HTTP services | Defaults to Android-emulator host `http://10.0.2.2:8000`; another device or deployment will not reach the backend unless overridden | Supply with `--dart-define` per build environment; it is not an API key |

All backend setting names are centralized in `Settings`. Every name in
`backend/.env.example` maps to a settings field, and every settings alias is in
that example file.

## Planned but not implemented

No environment variable is currently declared for these intended providers.
Do not add the suggested names until working code and deployment ownership
exist.

| Variable | Provider | Required/Optional/Unused | Location | Backend/Client | Secret? | Used by | Missing behaviour | Recommended action |
| -------- | -------- | ------------------------ | -------- | -------------- | ------- | ------- | ----------------- | ------------------ |
| No variable declared | Supabase Auth/client | Planned, not implemented | Intended architecture and backend documentation only | Undecided; no client SDK or auth code | Depends on future key type | Nothing in current code | No authentication functionality exists | Design Auth and Row Level Security first; never place a future service-role key in Flutter |
| No variable declared | Wikidata/Wikipedia | Planned, not implemented | Backend provider table only | Likely backend | Normally no runtime key | Nothing in current code | No notable-place enrichment | Add no key placeholder now |
| No variable declared | openrouteservice | Planned, not implemented; Google Routes is the actual provider | Intended architecture only | Likely backend | A future key would be secret | Nothing in current code | Routing continues to use Google Routes | Provider replacement is outside this audit; add configuration only with implementation |
| No variable declared | Open-Meteo | Planned, not implemented | Intended architecture only | Likely backend | Normally no key for the selected public endpoint | Nothing in current code | No weather feature | Add no key placeholder now |
| No variable declared | Frankfurter | Planned, not implemented | Intended architecture only | Likely backend | Normally no key | Nothing in current code | No currency conversion | Add no key placeholder now |

The repository calls PostgreSQL through SQLAlchemy/psycopg. It does not contain
`SUPABASE_URL`, a Supabase anonymous key, a service-role key, a Supabase SDK, or
an Auth/RLS configuration. Therefore this audit makes no claim that the future
Supabase client architecture is secure.

## Duplicate or inconsistently named

None found. `GOOGLE_PLACES_API_KEY` and `GOOGLE_ROUTES_API_KEY` are intentionally
separate because they authorize different implemented APIs. They are not
duplicate names for a Google Maps SDK key.

The one non-secret inconsistency found was the Flutter `API_BASE_URL` default
using port `8001` while the documented `uvicorn` command uses port `8000`; the
client default and example were normalized to `8000`.

## Verified unused

The following candidate names were checked across current source,
configuration, platform files, dependencies, tests, deployment/CI locations,
and tracked history. They have no executable or build reference (their
appearance in this report is documentation only).

| Variable | Provider | Required/Optional/Unused | Location | Backend/Client | Secret? | Used by | Missing behaviour | Recommended action |
| -------- | -------- | ------------------------ | -------- | -------------- | ------- | ------- | ----------------- | ------------------ |
| `GOOGLE_MAPS_API_KEY` | Google Maps SDK | Verified unused / not declared | No Maps SDK dependency, manifest metadata, or source configuration | Neither | Yes if one existed | Nothing; the destination UI attributes its active Geoapify/OSM source and does not initialize a map SDK | None | Do not add it; manually remove it from local environments if present and not used by external infrastructure |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` | Supabase client/Auth | Verified unused / not declared | No SDK, source, platform, deployment, or CI reference | Neither | URL: no; anon key: public credential; service role: highly secret | Nothing | No current change because Auth/client functionality is absent | Do not add now; a service-role key must never enter Flutter |
| `FOURSQUARE_API_KEY`, `FOURSQUARE_API_TOKEN` | Proprietary Foursquare Places API | Verified unused / not declared | Local FSQ OS importer only | Neither | Yes | Nothing | Local FSQ import remains available from a file | Do not add; a portal download token is outside application runtime configuration |
| `OPENROUTESERVICE_API_KEY` | openrouteservice | Verified unused / not declared | No client or dependency | Neither | Yes | Nothing | Google Routes remains the implemented router | Do not add until an approved provider migration is implemented |
| `OPEN_METEO_API_KEY`, `FRANKFURTER_API_KEY`, `WIKIDATA_API_KEY`, `WIKIPEDIA_API_KEY`, `OVERPASS_API_KEY` | Intended no-key providers | Verified unused / not declared | No client, dependency, build, or deployment reference | Neither | Not expected for the selected public implementations | Nothing | Corresponding features are not implemented | Do not add placeholders |
| Firebase/OAuth client secrets | Firebase, Google Sign-In, Apple Sign-In | Verified unused / not declared | Login buttons are UI-only; no SDK or platform configuration | Neither | Depends on credential type | Nothing | Login remains a mock UI flow | Do not add until authentication is implemented and reviewed |

## Unknown

None. Every environment variable currently declared by the repository has a
confirmed reader and use. No unexplained variable name was found in the local
`backend/.env` name-only inspection.

## No-key services

| Variable | Provider | Required/Optional/Unused | Location | Backend/Client | Secret? | Used by | Missing behaviour | Recommended action |
| -------- | -------- | ------------------------ | -------- | -------------- | ------- | ------- | ----------------- | ------------------ |
| `FSQ_OS_PLACES_PATH` or CLI `--source` (path, not key) | Foursquare Open Source Places | Optional implemented local import | `backend/app/importers/fsq_os_places.py`, `backend/app/cli.py` | Backend/CLI | No runtime credential | CSV/JSONL/NDJSON import | No import occurs without a local file | Keep the importer keyless; portal access used to obtain a file must remain outside app runtime |
| `OVERPASS_API_URL` (URL, not key) | OpenStreetMap/Overpass | Implemented normal recommendations | OSM discovery services and Flutter attribution | Backend / client attribution | No | Bounded cached POI refresh | Retryable 429/503/504 on public-instance failure | Preserve attribution and use responsible caching; no API key exists |
| No variable | Wikidata/Wikipedia | Planned only | Intended architecture | Backend when implemented | No | Nothing currently | No enrichment | Add no key unless a future selected service explicitly requires one |
| No variable | Open-Meteo | Planned only | Intended architecture | Backend when implemented | No for the selected public endpoint | Nothing currently | No weather | Add no key now |
| No variable | Frankfurter | Planned only | Intended architecture | Backend when implemented | No | Nothing currently | No currency conversion | Add no key now |

## Actual provider architecture versus intended architecture

| Capability | Intended provider | Actual repository state |
| --- | --- | --- |
| Database | Supabase/PostgreSQL | PostgreSQL via SQLModel/psycopg; Supabase connection URLs work, but no Supabase SDK/Auth/RLS configuration is present |
| Authentication | Supabase Auth | Not implemented; login controls are mock UI |
| Open POI import | FSQ OS Places | Implemented as a local file importer with no runtime token |
| Additional POIs | OpenStreetMap/Overpass | No live client; only OSM-related provenance/attribution is present |
| Notable-place enrichment | Wikidata/Wikipedia | Not implemented |
| Autocomplete/geocoding | Geoapify | Implemented through the backend |
| Directions/matrices | openrouteservice | Not implemented; Google Routes is currently used instead |
| Weather | Open-Meteo | Not implemented |
| Currency | Frankfurter | Not implemented |
| City and nearby-place discovery | Not listed in intended target | Google Places API (New) is implemented and actively used |

## Secret placement review

- Flutter contains only the non-secret `API_BASE_URL`. No backend credential
  name or value is compiled into Dart.
- Android has Internet and location permissions but no Google Maps/Firebase
  metadata, Google Services plugin, or secret Gradle property. There is no iOS
  directory or `Info.plist` in this revision.
- `backend/.env` and root `.env*` files are ignored, with an explicit exception
  only for `.env.example`. No real environment file is tracked.
- No Dockerfile, deployment manifest, CI workflow, committed JSON credential,
  keystore, or project private key is present in the current tree.
- Provider exceptions and API responses use stable messages and do not include
  keys or raw upstream response bodies. Existing tests cover safe Geoapify
  failures; added tests cover missing Google keys and redacted settings.
- Google keys are sent in `X-Goog-Api-Key` headers. Geoapify requires its key in
  the outbound query string, so production HTTP client/proxy debug logging must
  keep query-string redaction enabled. The repository does not enable such
  outbound debug logging.
- Database and provider secrets now use Pydantic `SecretStr`; settings `str` and
  `repr` output redacts them. Plain values are revealed only at the database or
  provider construction boundary.
- The tracked README PostgreSQL URL is a named placeholder, not a credential.
  Test keys/passwords are explicit synthetic fixtures.
- The generated DOCX/PDF documentation contains no credential variable name or
  targeted live-key pattern. Those artifacts predate the backend and are stale
  for configuration guidance; `backend/README.md` and this report are the
  current sources.

## Secret scan findings

No current tracked file matches the targeted Google, GitHub, AWS, Slack, or
private-key credential shapes. No real `.env` was ever found in tracked history;
only `backend/.env.example` appears there.

One history-only path matched a private-key header:
`tmp/codex_flutter_build_support/flutter_tools/test/data/asset_test/tls_cert/dummy-key.pem`
(provider: test TLS fixture; variable/name: `dummy-key.pem`). The path and name
identify it as a Flutter tooling test fixture, it is absent from the current
tree, and there is no evidence that it was a deployable YatraCanvas credential;
rotation is not indicated.

No repository secret-scanner executable was installed, so the audit used
path-only, value-suppressing targeted scans of both the current tree and Git
history. No credential value was printed into this report.

## Environment guidance

For the current local `backend/.env`:

- Keep `DATABASE_URL`; it is required.
- Add `GOOGLE_PLACES_API_KEY` only for city search/details and Google nearby POI
  discovery.
- Add `GOOGLE_ROUTES_API_KEY` only for uncached route optimization.
- Add `GEOAPIFY_API_KEY` only for location autocomplete/geocoding.
- Add `FSQ_OS_PLACES_PATH` only if the CLI should have a default local import
  path; `--source` is an alternative.
- The remaining non-secret tuning variables may be omitted because validated
  defaults exist.
- No inspected local variable is safe to remove: the name-only inspection found
  only required `DATABASE_URL`.

Never place `DATABASE_URL`, `GOOGLE_PLACES_API_KEY`,
`GOOGLE_ROUTES_API_KEY`, `GEOAPIFY_API_KEY`, or any future Supabase
service-role key in Flutter, Dart defines, Android/iOS metadata, or client-side
assets.
