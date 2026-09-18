# Environment variables

Last reviewed: 2026-09-18

This is the complete repository-owned configuration inventory. Names are documented; real
values are not. Backend settings load from process environment or untracked `backend/.env`.
Flutter's one setting is supplied at build/run time with `--dart-define`.

## Backend variables

| Variable | Service/provider | Required? | Owner | Purpose | Public/secret | Status and replacement note |
| --- | --- | --- | --- | --- | --- | --- |
| `APP_ENV` | Backend runtime classification | Optional for normal startup; required for diagnostic writes | Backend/deployment | Explicitly classifies `development`, `test`, `staging`, or `production`; never inferred from a database URL | Non-secret | `[IMPLEMENTED]`; database write-test utilities fail closed unless explicitly `development` or `test` |
| `DATABASE_URL` | PostgreSQL (Supabase URL supported) | Required to start | Backend/deployment | SQLAlchemy/psycopg database connection | Secret | `[IMPLEMENTED]`; remains required in target architecture |
| `JWT_SECRET_KEY` | Authentication / JWT | Optional; dev fallback provided | Backend | Cryptographic secret for signing and verifying JWT authentication tokens | Secret | `[IMPLEMENTED]`; rotate and provide strong secret in production |
| `JWT_ALGORITHM` | Authentication / JWT | Optional | Backend | JWT token signing algorithm, default `HS256` | Non-secret | `[IMPLEMENTED]` |
| `JWT_ACCESS_TOKEN_EXPIRE_MINUTES` | Authentication / JWT | Optional | Backend | Token validity duration, default 1440 minutes (24 hours) | Non-secret | `[IMPLEMENTED]` |
| `ADMIN_EMAIL` | Admin bootstrap CLI/service | Optional | Backend CLI | Default email address for initial administrator creation | Safe configuration | `[IMPLEMENTED]`; default `admin@yatracanvas.com` |
| `ADMIN_PASSWORD` | Admin bootstrap CLI/service | Optional | Backend CLI | Bootstrap password for initial administrator creation; prompt used if omitted | Secret | `[IMPLEMENTED]`; never commit |
| `GOOGLE_PLACES_API_KEY` | Google Places API (New) | Optional; legacy endpoints only, not the normal destination/recommendation flow | Backend | Authenticates retained Autocomplete, Place Details, and Nearby Search adapters | Secret | `[DEPRECATED]`; normal Flutter flow does not require it |
| `GOOGLE_ROUTES_API_KEY` | Google Routes API | Optional; not used by the normal optimizer | Backend | Authenticates the retained legacy adapter | Secret | `[DEPRECATED]`; normal optimization uses local estimates |
| `GEOAPIFY_API_KEY` | Geoapify | Optional; required for new destination and arrival suggestions through `/locations/autocomplete` | Backend | Authenticates runtime autocomplete/geocoding | Secret | `[IMPLEMENTED]`; intended to remain narrowly scoped |
| `GEOAPIFY_BASE_URL` | Geoapify | Optional | Backend | Provider base URL; default is the official HTTPS API host | Non-secret | `[IMPLEMENTED]`; useful for controlled testing, validate as HTTP(S) |
| `GEOAPIFY_TIMEOUT_SECONDS` | Geoapify | Optional | Backend | Outbound request timeout, default 8 seconds | Non-secret | `[IMPLEMENTED]` |
| `GEOAPIFY_AUTOCOMPLETE_CACHE_TTL_SECONDS` | Geoapify | Optional | Backend | In-process autocomplete TTL, default 300 seconds | Non-secret | `[IMPLEMENTED]`; cache is not shared/persistent |
| `FOURSQUARE_API_KEY` | Foursquare Places API | Optional | Backend | Enables conservative venue-match photo enrichment only; never sent to Flutter | Secret | `[IMPLEMENTED]`; empty disables this adapter without breaking place responses |
| `FOURSQUARE_BASE_URL` | Foursquare Places API | Optional | Backend | Provider base URL, default `https://places-api.foursquare.com` | Non-secret | `[IMPLEMENTED]`; validate as HTTP(S) |
| `PLACE_IMAGE_TIMEOUT_SECONDS` | Place image providers | Optional | Backend | Per-request provider timeout, default 5 seconds | Non-secret | `[IMPLEMENTED]`; work is outside the foreground response path |
| `PLACE_IMAGE_CONCURRENCY` | Place image providers | Optional | Backend | Maximum places enriched concurrently per batch, default 4 | Non-secret | `[IMPLEMENTED]` |
| `PLACE_IMAGE_CACHE_TTL_HOURS` | Place image cache | Optional | Backend | Successful image cache TTL, default 720 hours | Non-secret | `[IMPLEMENTED]` |
| `PLACE_IMAGE_NEGATIVE_TTL_HOURS` | Place image cache | Optional | Backend | Not-found cache TTL, default 24 hours | Non-secret | `[IMPLEMENTED]` |
| `PLACE_IMAGE_FAILED_TTL_MINUTES` | Place image cache | Optional | Backend | Provider-failure cache TTL, default 30 minutes | Non-secret | `[IMPLEMENTED]` |
| `OVERPASS_API_URL` | OpenStreetMap / Overpass | Optional | Backend | Bounded runtime POI query endpoint; defaults to the public FOSSGIS `lz4` endpoint and may point to a self-hosted instance | Non-secret | `[IMPLEMENTED]` for development/small-scale discovery; public service has no production SLA |
| `OVERPASS_TIMEOUT_SECONDS` | OpenStreetMap / Overpass | Optional | Backend | Outbound and query timeout, default 25 seconds | Non-secret | `[IMPLEMENTED]` |
| `OVERPASS_RADIUS_METERS` | OpenStreetMap / Overpass | Optional | Backend | Default half-width of bounded POI discovery box, default 8,000 m | Non-secret | `[IMPLEMENTED]` |
| `OVERPASS_TOURISM_RADIUS_METERS` | OpenStreetMap / Overpass | Optional | Backend | Search radius for tourism and major attractions discovery, default 15,000 m | Non-secret | `[IMPLEMENTED]` |
| `OVERPASS_HERITAGE_RADIUS_METERS` | OpenStreetMap / Overpass | Optional | Backend | Search radius for historic and heritage POI discovery, default 15,000 m | Non-secret | `[IMPLEMENTED]` |
| `OVERPASS_RELIGIOUS_RADIUS_METERS` | OpenStreetMap / Overpass | Optional | Backend | Search radius for places of worship discovery, default 10,000 m | Non-secret | `[IMPLEMENTED]` |
| `OVERPASS_FOOD_RADIUS_METERS` | OpenStreetMap / Overpass | Optional | Backend | Search radius for food and restaurant discovery, default 8,000 m | Non-secret | `[IMPLEMENTED]` |
| `OVERPASS_CAFE_RADIUS_METERS` | OpenStreetMap / Overpass | Optional | Backend | Search radius for cafe discovery, default 8,000 m | Non-secret | `[IMPLEMENTED]` |
| `OVERPASS_MARKETS_RADIUS_METERS` | OpenStreetMap / Overpass | Optional | Backend | Search radius for market and bazaar discovery, default 10,000 m | Non-secret | `[IMPLEMENTED]` |
| `OVERPASS_NATURE_RADIUS_METERS` | OpenStreetMap / Overpass | Optional | Backend | Search radius for nature and park discovery, default 25,000 m | Non-secret | `[IMPLEMENTED]` |
| `OVERPASS_TOURISM_LIMIT` | OpenStreetMap / Overpass | Optional | Backend | Candidate discovery limit for tourism category, default 60 | Non-secret | `[IMPLEMENTED]` |
| `OVERPASS_HERITAGE_LIMIT` | OpenStreetMap / Overpass | Optional | Backend | Candidate discovery limit for heritage category, default 60 | Non-secret | `[IMPLEMENTED]` |
| `OVERPASS_RELIGIOUS_LIMIT` | OpenStreetMap / Overpass | Optional | Backend | Candidate discovery limit for religious category, default 40 | Non-secret | `[IMPLEMENTED]` |
| `OVERPASS_FOOD_LIMIT` | OpenStreetMap / Overpass | Optional | Backend | Candidate discovery limit for food category, default 50 | Non-secret | `[IMPLEMENTED]` |
| `OVERPASS_CAFE_LIMIT` | OpenStreetMap / Overpass | Optional | Backend | Candidate discovery limit for cafes category, default 40 | Non-secret | `[IMPLEMENTED]` |
| `OVERPASS_MARKETS_LIMIT` | OpenStreetMap / Overpass | Optional | Backend | Candidate discovery limit for markets category, default 40 | Non-secret | `[IMPLEMENTED]` |
| `OVERPASS_NATURE_LIMIT` | OpenStreetMap / Overpass | Optional | Backend | Candidate discovery limit for nature category, default 40 | Non-secret | `[IMPLEMENTED]` |
| `OVERPASS_CIRCUIT_BREAKER_THRESHOLD` | OpenStreetMap / Overpass | Optional | Backend | Consecutive failure count before circuit trips to open, default 3 | Non-secret | `[IMPLEMENTED]` |
| `OVERPASS_CIRCUIT_BREAKER_COOLDOWN_SECONDS` | OpenStreetMap / Overpass | Optional | Backend | Cooldown duration while circuit is open, default 60 seconds | Non-secret | `[IMPLEMENTED]` |
| `FSQ_OS_PLACES_PATH` | FSQ OS Places | Optional | Backend CLI/operator | Default local CSV/JSONL/NDJSON source path | Usually private path, not a credential | `[IMPLEMENTED]`; portal access token is intentionally not accepted here |
| `AUDIALA_DATASET_PATH` | Audiala | Optional | Backend | Default local JSON file path for Audiala dataset (`backend/app/data/audiala_places.json`) | Usually private path, not a credential | `[IMPLEMENTED]`; secondary seed layer for POI discovery and canonical multi-source identity |
| `FSQ_DEDUPE_DISTANCE_METERS` | FSQ importer | Optional | Backend CLI | Maximum nearby-candidate distance, default 75 m | Non-secret | `[IMPLEMENTED]`; change conservatively and test dense cities |
| `FSQ_IMPORT_BATCH_SIZE` | FSQ importer | Optional | Backend CLI | Commit batch size, default 250 | Non-secret | `[IMPLEMENTED]` |
| `ROUTE_MATRIX_TRAFFIC_TTL_MINUTES` | Route matrix | Optional | Backend | Traffic-duration freshness, default 30 minutes | Non-secret | `[IMPLEMENTED]`; retain semantics across provider migration |
| `PLACE_DISCOVERY_CACHE_TTL_HOURS` | Place discovery | Optional | Backend | City/category refresh TTL, default 24 hours | Non-secret | `[IMPLEMENTED]`; target ingestion may revise the mechanism |
| `PLACE_DISCOVERY_CACHE_VERSION` | Place discovery | Optional | Backend | Version namespace for city/category cache keys, default 1; increment after incompatible provider/query strategy changes | Non-secret | `[IMPLEMENTED]`; version 1 preserves existing keys |
| `DISCOVERY_INTERACTIVE_TIMEOUT_SECONDS` | Place discovery | Optional | Backend | Maximum interactive wait budget for foreground recommendation queries, default 12 seconds | Non-secret | `[IMPLEMENTED]` |
| `DISCOVERY_SHALLOW_LIMIT` | Place discovery | Optional | Backend | Candidate limit per category during broad shallow prefetch, default 15 | Non-secret | `[IMPLEMENTED]` |
| `DISCOVERY_STALE_USABLE_HOURS` | Place discovery | Optional | Backend | Grace period for stale-while-revalidate POI serving, default 168 hours (7 days) | Non-secret | `[IMPLEMENTED]` |
| `DISCOVERY_MIN_USABLE_CANDIDATES_PER_CATEGORY` | Place discovery | Optional | Backend | Minimum usable candidates to treat category cache as sufficient, default 6 | Non-secret | `[IMPLEMENTED]` |
| `ROUTING_PROVIDER` | Routing provider selection | Optional | Backend | Routing geometry provider, default `osrm` (or `openrouteservice`) | Non-secret | `[IMPLEMENTED]`; provider-neutral routing selection |
| `OPENROUTESERVICE_API_KEY` | openrouteservice | Optional | Backend | API token for hosted openrouteservice directions v2 | Secret | `[IMPLEMENTED]`; optional when using self-hosted ORS or OSRM |
| `OPENROUTESERVICE_BASE_URL` | openrouteservice | Optional | Backend | openrouteservice base URL, default `https://api.openrouteservice.org` | Non-secret | `[IMPLEMENTED]` |
| `OPENROUTESERVICE_TIMEOUT_SECONDS` | openrouteservice | Optional | Backend | Outbound directions request timeout, default 10 seconds | Non-secret | `[IMPLEMENTED]` |
| `OSRM_ROUTER_URL` | OSRM | Optional | Backend | OSRM routing endpoint for keyless open-data road geometry, default `https://router.project-osrm.org` | Non-secret | `[IMPLEMENTED]` |
| `OSRM_TIMEOUT_SECONDS` | OSRM | Optional | Backend | OSRM request timeout, default 10 seconds | Non-secret | `[IMPLEMENTED]` |
| `ROUTE_GEOMETRY_CACHE_TTL_MINUTES` | Route geometry cache | Optional | Backend | In-memory TTL for cached route geometry linestrings, default 60 minutes | Non-secret | `[IMPLEMENTED]` |
| `WEATHER_PROVIDER` | Weather provider | Optional | Backend | Selected weather provider, default `openmeteo` | Non-secret | `[IMPLEMENTED]` |
| `OPEN_METEO_BASE_URL` | Open-Meteo | Optional | Backend | Open-Meteo API base URL, default `https://api.open-meteo.com` | Non-secret | `[IMPLEMENTED]`; free hosted endpoint has non-commercial restriction |
| `OPEN_METEO_TIMEOUT_SECONDS` | Open-Meteo | Optional | Backend | Open-Meteo request timeout, default 10 seconds | Non-secret | `[IMPLEMENTED]` |
| `WEATHER_CACHE_TTL_MINUTES` | Weather forecast cache | Optional | Backend | In-memory TTL for cached weather forecasts, default 60 minutes | Non-secret | `[IMPLEMENTED]` |

## Flutter build-time variable

| Variable | Service/provider | Required? | Owner | Purpose | Public/secret | Status and replacement note |
| --- | --- | --- | --- | --- | --- | --- |
| `API_BASE_URL` | YatraCanvas FastAPI | Optional build override | Flutter/build | Backend origin; emulator-friendly development default is in code | Safe public configuration | `[IMPLEMENTED]`; never put provider or database credentials in `--dart-define` |

## What a developer needs today

- Always: a PostgreSQL `DATABASE_URL` for the backend environment.
- For any mutation-oriented database diagnostic: an explicit `APP_ENV=development` or
  `APP_ENV=test`. Missing, staging, and production classifications are rejected. Runtime startup
  remains backward-compatible when `APP_ENV` is absent.
- For the normal destination and arrival autocomplete flow: `GEOAPIFY_API_KEY`.
- For POI recommendations: no key; the backend uses the configured public or self-hosted
  `OVERPASS_API_URL` and persists ODbL provenance. Images still render from local fallbacks;
  `FOURSQUARE_API_KEY` is optional enrichment, never a recommendation prerequisite.
- For route optimization: no key; the current normal path uses clearly labelled local estimates.
- For local FSQ import: an operator-exported file and optionally `FSQ_OS_PLACES_PATH`; the importer
  does not use `FOURSQUARE_API_KEY` or an FSQ portal token.

Only `DATABASE_URL` is globally required for normal backend startup. `APP_ENV` is additionally
required before a guarded diagnostic can perform test writes. Provider keys are independently
optional; request only keys for features being exercised.

## Planned providers are intentionally absent

No repository code reads a Supabase URL/public client key, Supabase service-role key,
Frankfurter base URL, or Wikimedia contact. Those variables have **not**
been added to `backend/.env.example` because doing so would falsely imply an integration exists.

Before adding any planned variable, implement or select the adapter/configuration contract,
choose an unambiguous name, add validation and tests, update `backend/.env.example` and this file,
and document provider policy. Open-Meteo specifically requires a product/licensing decision:
its [official terms](https://open-meteo.com/en/terms) make the free API non-commercial, while
its [commercial plans](https://open-meteo.com/en/pricing) use a customer endpoint and key
(last verified: 2026-08-31).

## Removed dead variables

The following variables were removed from `Settings` and `backend/.env.example` during repository stabilization:
- `GOOGLE_NEARBY_RADIUS_METERS`, `PLACE_POPULAR_MIN_RATING`, `PLACE_POPULAR_MIN_REVIEW_COUNT`: Consumed solely by the dead `PlaceDiscoveryService` (deleted).

## Secret-handling rules

- Copy `backend/.env.example` to `backend/.env`; never commit or paste the real file.
- Keep database dumps and backups outside the repository. Common local database and backup
  extensions, plus `backups/` directories, are ignored as a second line of defense.
- Do not put `DATABASE_URL` or provider keys in Flutter, screenshots, HTTP responses, logs, test
  assertions, documentation, or issue descriptions.
- Restrict and rotate keys in the provider console. Do not call a paid API merely to test a key.
- A deployment secret manager may inject the same names; deployment details are currently
  `[UNKNOWN]` because no deployment configuration is tracked.
- FSQ portal tokens are operator credentials for obtaining an extract. If automated ingestion is
  later approved, define their storage and rotation separately rather than overloading
  `FSQ_OS_PLACES_PATH`.
