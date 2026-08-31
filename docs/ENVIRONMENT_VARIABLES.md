# Environment variables

Last reviewed: 2026-08-31

This is the complete repository-owned configuration inventory. Names are documented; real
values are not. Backend settings load from process environment or untracked `backend/.env`.
Flutter's one setting is supplied at build/run time with `--dart-define`.

## Backend variables

| Variable | Service/provider | Required? | Owner | Purpose | Public/secret | Status and replacement note |
| --- | --- | --- | --- | --- | --- | --- |
| `DATABASE_URL` | PostgreSQL (Supabase URL supported) | Required to start | Backend/deployment | SQLAlchemy/psycopg database connection | Secret | `[IMPLEMENTED]`; remains required in target architecture |
| `GOOGLE_PLACES_API_KEY` | Google Places API (New) | Optional; required for Google-backed city and nearby discovery endpoints | Backend | Authenticates Autocomplete, Place Details, and Nearby Search | Secret | `[IMPLEMENTED]`, target `[DEPRECATED]`; retain until verified city/POI replacement and backfill |
| `GOOGLE_ROUTES_API_KEY` | Google Routes API | Optional; required to fetch missing/stale route-matrix legs | Backend | Authenticates `computeRouteMatrix` | Secret | `[IMPLEMENTED]`; planned replacement by openrouteservice after parity |
| `GEOAPIFY_API_KEY` | Geoapify | Optional; required for `/locations/autocomplete` | Backend | Authenticates runtime autocomplete/geocoding | Secret | `[IMPLEMENTED]`; intended to remain narrowly scoped |
| `GEOAPIFY_BASE_URL` | Geoapify | Optional | Backend | Provider base URL; default is the official HTTPS API host | Non-secret | `[IMPLEMENTED]`; useful for controlled testing, validate as HTTP(S) |
| `GEOAPIFY_TIMEOUT_SECONDS` | Geoapify | Optional | Backend | Outbound request timeout, default 8 seconds | Non-secret | `[IMPLEMENTED]` |
| `GEOAPIFY_AUTOCOMPLETE_CACHE_TTL_SECONDS` | Geoapify | Optional | Backend | In-process autocomplete TTL, default 300 seconds | Non-secret | `[IMPLEMENTED]`; cache is not shared/persistent |
| `FSQ_OS_PLACES_PATH` | FSQ OS Places | Optional | Backend CLI/operator | Default local CSV/JSONL/NDJSON source path | Usually private path, not a credential | `[IMPLEMENTED]`; portal access token is intentionally not accepted here |
| `FSQ_DEDUPE_DISTANCE_METERS` | FSQ importer | Optional | Backend CLI | Maximum nearby-candidate distance, default 75 m | Non-secret | `[IMPLEMENTED]`; change conservatively and test dense cities |
| `FSQ_IMPORT_BATCH_SIZE` | FSQ importer | Optional | Backend CLI | Commit batch size, default 250 | Non-secret | `[IMPLEMENTED]` |
| `ROUTE_MATRIX_TRAFFIC_TTL_MINUTES` | Route matrix | Optional | Backend | Traffic-duration freshness, default 30 minutes | Non-secret | `[IMPLEMENTED]`; retain semantics across provider migration |
| `PLACE_DISCOVERY_CACHE_TTL_HOURS` | Place discovery | Optional | Backend | City/category refresh TTL, default 24 hours | Non-secret | `[IMPLEMENTED]`; target ingestion may revise the mechanism |
| `GOOGLE_NEARBY_RADIUS_METERS` | Google Places | Optional | Backend | Nearby Search radius, default 10,000 m | Non-secret | `[IMPLEMENTED]`, target `[DEPRECATED]` with Google discovery |
| `PLACE_POPULAR_MIN_RATING` | Canonical place classification | Optional | Backend | Minimum rating for current popular flag, default 4.2 | Non-secret | `[IMPLEMENTED]`; provider-neutral meaning needs review because FSQ OS has no rating field |
| `PLACE_POPULAR_MIN_REVIEW_COUNT` | Canonical place classification | Optional | Backend | Minimum review count for current popular flag, default 100 | Non-secret | `[IMPLEMENTED]`; same provider-neutral review required |

## Flutter build-time variable

| Variable | Service/provider | Required? | Owner | Purpose | Public/secret | Status and replacement note |
| --- | --- | --- | --- | --- | --- | --- |
| `API_BASE_URL` | YatraCanvas FastAPI | Optional build override | Flutter/build | Backend origin; emulator-friendly development default is in code | Safe public configuration | `[IMPLEMENTED]`; never put provider or database credentials in `--dart-define` |

## What a developer needs today

- Always: a PostgreSQL `DATABASE_URL` for the backend environment.
- For current city autocomplete/details/resolve or Google-backed nearby refresh:
  `GOOGLE_PLACES_API_KEY` restricted to Places API (New) and the backend's allowed origins/IPs
  where feasible.
- For current route optimization when a complete matrix is not cached:
  `GOOGLE_ROUTES_API_KEY` restricted to Routes API. A separate restricted key limits blast radius.
- For current arrival/address/transport autocomplete: `GEOAPIFY_API_KEY`.
- For local FSQ import: an operator-exported file and optionally `FSQ_OS_PLACES_PATH`; the app does
  not need a proprietary Foursquare API key or an FSQ portal token.

Only `DATABASE_URL` is globally required. The three provider keys are independently optional;
request only keys for features being exercised.

## Planned providers are intentionally absent

No repository code reads a Supabase URL/public client key, Supabase service-role key,
openrouteservice key, Open-Meteo key/base URL, Frankfurter base URL, Wikimedia contact, Overpass
URL, or provider-selection flag. Those variables have **not** been added to
`backend/.env.example` because doing so would falsely imply an integration exists.

Before adding any planned variable, implement or select the adapter/configuration contract,
choose an unambiguous name, add validation and tests, update `backend/.env.example` and this file,
and document provider policy. Open-Meteo specifically requires a product/licensing decision:
its [official terms](https://open-meteo.com/en/terms) make the free API non-commercial, while
its [commercial plans](https://open-meteo.com/en/pricing) use a customer endpoint and key
(last verified: 2026-08-31).

## Secret-handling rules

- Copy `backend/.env.example` to `backend/.env`; never commit or paste the real file.
- Do not put `DATABASE_URL` or provider keys in Flutter, screenshots, HTTP responses, logs, test
  assertions, documentation, or issue descriptions.
- Restrict and rotate keys in the provider console. Do not call a paid API merely to test a key.
- A deployment secret manager may inject the same names; deployment details are currently
  `[UNKNOWN]` because no deployment configuration is tracked.
- FSQ portal tokens are operator credentials for obtaining an extract. If automated ingestion is
  later approved, define their storage and rotation separately rather than overloading
  `FSQ_OS_PLACES_PATH`.
