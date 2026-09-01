# YatraCanvas Backend

This folder contains the FastAPI and PostgreSQL backend for YatraCanvas. It
provides city and place storage, server-side city discovery, runtime location
autocomplete, recommendations, saved places, and route optimization.

At startup, SQLModel creates missing tables defined in `app/models`. It does
not alter an existing database to match changed models. Existing schema changes
currently rely on reviewed scripts in `sql/`; adopting an ordered migration
workflow is still planned.

For the evidence-backed project overview and target direction, start with
[`docs/PROJECT_CONTEXT.md`](../docs/PROJECT_CONTEXT.md), then see the
[architecture](../docs/ARCHITECTURE.md),
[provider matrix](../docs/API_AND_DATA_SOURCES.md), and
[environment inventory](../docs/ENVIRONMENT_VARIABLES.md).

Python 3.10 or newer is required.

## 1. Create and activate a virtual environment

From the repository root:

```powershell
cd backend
py -m venv .venv
.\.venv\Scripts\Activate.ps1
```

On macOS or Linux, activate it with:

```bash
source .venv/bin/activate
```

## 2. Install dependencies

```powershell
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

## 3. Configure the backend

Copy the example file:

```powershell
Copy-Item .env.example .env
```

`DATABASE_URL` is the only setting required for the backend to start. Paste a
PostgreSQL connection string after `DATABASE_URL=`; a Supabase PostgreSQL URL is
supported, but the repository does not currently use the Supabase client SDK or
Supabase Auth.

```dotenv
DATABASE_URL=postgresql://YOUR_DATABASE_USER:YOUR_URL_ENCODED_PASSWORD@YOUR_DATABASE_HOST:5432/postgres
```

Do not add quotes and do not commit `.env`. The repository's root `.gitignore`
already excludes it. If the database password contains URL-reserved characters
such as `@`, `:`, `/`, `#`, or `%`, URL-encode the password before using it in
the connection string.

No Google key is required for normal recommendations or route optimization. The
following keys are optional and should be added only for the flows that need them:

```dotenv
GOOGLE_PLACES_API_KEY=
GOOGLE_ROUTES_API_KEY=
GEOAPIFY_API_KEY=
```

- `GOOGLE_PLACES_API_KEY` enables legacy Places API (New) city
  autocomplete/details and the legacy discovery endpoint. Normal Flutter
  recommendations do not use it. It is not a Google Maps SDK key; this project
  has no Google Maps SDK or Android maps metadata.
- `GOOGLE_ROUTES_API_KEY` is retained for the legacy Google Routes adapter.
  Normal itinerary optimization uses local coordinate estimates and does not
  call Google.
- `GEOAPIFY_API_KEY` enables destination and arrival autocomplete/geocoding.

Keep keys only in `backend/.env`; they must never be added to Flutter or
committed. OpenStreetMap recommendations use the keyless, configurable Overpass
endpoint shown in `.env.example`; public endpoints are best-effort services.

The backend keeps `trips.user_id` as a UUID but does not create or reference
Supabase's `auth.users` table. Authentication is **not implemented**. `POST /trips`
temporarily assigns a fixed, server-owned development identity and rejects a
client-provided `user_id`; replace that isolated dependency with authenticated
identity before multi-user deployment.

## 4. Run the API

Run this command while your terminal is in the `backend` folder:

```powershell
uvicorn app.main:app --reload
```

The API will be available at `http://127.0.0.1:8000`. Open the interactive
Swagger documentation at:

```text
http://127.0.0.1:8000/docs
```

## Initial endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/` | Backend status |
| `POST` | `/cities` | Create a city |
| `GET` | `/cities` | List cities |
| `POST` | `/cities/resolve` | Return or create a normalized provider city |
| `GET` | `/cities/search?query=` | Search stored cities by name or state |
| `GET` | `/cities/autocomplete?query=` | Search Google for India city predictions |
| `GET` | `/cities/place-details/{google_place_id}` | Normalize Google city details |
| `GET` | `/locations/autocomplete?query=` | Search Geoapify for normalized India destinations and arrival locations |
| `GET` | `/cities/{city_id}` | Get a city |
| `POST` | `/trips` | Create a trip and its preferences; return a real `trip_id` |
| `POST` | `/places` | Create a place |
| `GET` | `/cities/{city_id}/places` | List a city's places |

List endpoints accept optional `offset` and `limit` query parameters. `limit`
defaults to 100 and cannot exceed 500.

### Create a trip

`POST /trips` accepts only application-owned draft fields. The city must exist,
dates must define the supplied inclusive `days`, coordinate values must be
complete latitude/longitude pairs within valid ranges, and a non-arrival start
location requires a name and coordinates. Unknown fields such as `trip_id`,
`user_id`, or `created_at` are rejected.

```json
{
  "city_id": "11111111-1111-4111-8111-111111111111",
  "start_date": "2026-09-10",
  "end_date": "2026-09-12",
  "days": 3,
  "arrival_place": "Ujjain Railway Station",
  "arrival_latitude": 23.1793,
  "arrival_longitude": 75.7849,
  "start_location_type": "arrival",
  "purposes": ["Religious / Spiritual"],
  "preferences": ["Balanced", "Chill", "Walking"]
}
```

A successful `201` response includes the generated `trip_id`, normalized trip
fields, stored preference values, and the server timestamp. Trip and preference
rows are committed in one transaction; a related-row failure rolls back both.

## POI and location-provider architecture

YatraCanvas keeps canonical places in PostgreSQL and records every external
identity separately. Provider responsibilities are intentionally narrow:

| Provider | Responsibility |
| --- | --- |
| FSQ Open Source Places and existing OSM sources | Offline candidate POI import |
| Wikidata/Wikipedia | Future notable-place enrichment |
| PostgreSQL/Supabase | Canonical verified place storage |
| Geoapify | User-driven runtime autocomplete and geocoding only |
| OpenStreetMap/Overpass | Normal bounded, cached POI recommendations; no key required |
| Local coordinate estimator | Normal approximate route ordering; no key required |
| Google Places | Retained legacy city and discovery endpoints only |
| Google Routes | Retained legacy matrix adapter only |
| Open-Meteo | Intended weather provider; not implemented |
| Frankfurter | Intended currency provider; not implemented |

The Flutter client reads POIs from YatraCanvas; the backend refreshes a bounded
city/category cache from Overpass when needed. Flutter does not query Overpass,
FSQ, or Geoapify whenever a city opens.

### OpenStreetMap recommendations

Normal recommendations require no provider key. The backend queries a bounded
Overpass area, persists source element provenance, and caches each city/category
result. The UI shows the required OpenStreetMap attribution. The optional
settings are:

```dotenv
OVERPASS_API_URL=https://overpass-api.de/api/interpreter
OVERPASS_TIMEOUT_SECONDS=25
OVERPASS_RADIUS_METERS=8000
```

Public Overpass instances are best-effort and may occasionally time out or rate
limit. Retry the request during development. A production deployment should
evaluate regional OSM extracts or a self-hosted instance rather than treating a
public endpoint as an SLA-backed service.

### Geoapify configuration

Create a project and API key in the
[Geoapify dashboard](https://myprojects.geoapify.com/), then configure only the
backend:

```dotenv
GEOAPIFY_API_KEY=
GEOAPIFY_BASE_URL=https://api.geoapify.com
GEOAPIFY_TIMEOUT_SECONDS=8
GEOAPIFY_AUTOCOMPLETE_CACHE_TTL_SECONDS=300
```

`GET /locations/autocomplete` requires at least three non-whitespace
characters, defaults to country code `in`, accepts an optional documented
Geoapify `type`, and accepts `latitude` plus `longitude` together as a proximity
bias. Results use an application-owned schema and include the provider ID,
formatted label, and coordinates. The key is never returned to Flutter.

To disable Geoapify, leave `GEOAPIFY_API_KEY` empty and restart the backend.
The endpoint will return a safe `503`; stored places, Google city discovery,
and routing remain available when separately configured. The UI shows a
recoverable error instead of exposing provider details.

Geoapify uses a freemium credit model; plans, quotas, and terms are volatile and
must be re-checked in the official documentation before launch. Autocomplete is
debounced in Flutter and cached briefly in the backend to control usage.
Whenever suggestions are displayed, the UI shows `Powered by Geoapify` and
`© OpenStreetMap contributors`; existing OSM attribution must also remain on
maps and other OSM-derived displays.

### FSQ Open Source Places local import

Only the free FSQ Open Source Places dataset is accepted. Ratings, popularity,
tips, photos, and proprietary Foursquare Places API data are intentionally not
imported or invented. FSQ source records retain the `Apache-2.0` provenance
identifier, source URL, lifecycle dates, contacts, social identifiers,
categories, and unresolved flags.

Foursquare currently distributes OS Places through the
[Foursquare Places Portal](https://places.foursquare.com/) using an
Iceberg-based catalog. Create a portal account, generate an access token, and
use one of the portal's DuckDB/Spark/PyIceberg connection snippets to query only
the needed city and export it locally. Do not download or load the worldwide
dataset into Supabase. The importer itself does not require portal credentials
and never calls the proprietary Places API.

Export the filtered rows as UTF-8 CSV, JSONL, or NDJSON. JSON arrays are
accepted for `fsq_category_ids`, optional `fsq_category_labels`, and
`unresolved_flags`; CSV list values may also use `|` or `;`. CSV/JSONL support
keeps the backend dependency set small. Configure a default path if useful:

```dotenv
FSQ_OS_PLACES_PATH=
FSQ_DEDUPE_DISTANCE_METERS=75
FSQ_IMPORT_BATCH_SIZE=250
```

Dry-run Ujjain without any database changes:

```powershell
cd backend
python -m app.cli import-fsq-places --city ujjain --source C:\data\ujjain-fsq.jsonl --dry-run --limit 1000
```

Run the real local/test import after reviewing the summary:

```powershell
python -m app.cli import-fsq-places --city ujjain --source C:\data\ujjain-fsq.jsonl
```

The importer streams records, checks India and the configured locality before
database matching, and commits in configured batches. Repeated FSQ IDs update
their source metadata without duplicating a place. A new closed record is
skipped; a closure on an existing source is retained.

Automatic cross-provider matching requires exactly one nearby canonical place
with an exact normalized name and compatible broad category. A fuzzy name,
category conflict, second FSQ identity on the same canonical place, or multiple
candidates creates/updates a pending `place_import_reviews` row. Matching only
adds source/category rows; it never overwrites manually curated canonical
values. Adjust the geographic threshold conservatively for local density.

To add a city, add exactly one `ImportCity` entry and its locality aliases in
`app/importers/city_config.py`. No importer logic should contain city-specific
conditions.

### Database change

Existing databases need the reversible scripts reviewed and applied in the
safe migration environment:

- `sql/add_fsq_geoapify_foundation.sql`
- `sql/rollback_fsq_geoapify_foundation.sql`

For an existing database that has accumulated the current PlaceSource, Trip,
and route-cache drift, use `sql/repair_current_schema_parity.sql` only after a
read-only schema audit, explicit development/test classification, and a
verified backup. It is a transactional forward repair and must not be followed
by the destructive FSQ rollback after application data uses the repaired
columns. Do not blindly rerun older forward scripts; there is no migration
ledger that can prove their execution history.

The forward script extends `place_sources`, creates `place_categories` and
`place_import_reviews`, and adds selected provider fields to `trips`. New local
test databases receive the same schema from SQLModel metadata. Never run these
scripts or imports directly against production without the project's normal
review and backup process.

PostGIS is not currently enabled in this repository, so this foundation uses a
Haversine distance calculation during the bounded per-city import and does not
add a new PostgreSQL extension or pretend to provide a spatial index. If
PostGIS is adopted later, migrate the matching query and indexes together.

Official references:

- [FSQ OS Places access](https://docs.foursquare.com/data-products/docs/access-fsq-os-places)
- [FSQ OS Places schema](https://docs.foursquare.com/data-products/docs/places-os-data-schema)
- [Geoapify autocomplete](https://apidocs.geoapify.com/docs/geocoding/address-autocomplete/)
- [Geoapify pricing and attribution](https://www.geoapify.com/pricing/)

Provider facts in this section were last verified on 2026-08-31. The complete
policy and fallback inventory is maintained in
[`docs/API_AND_DATA_SOURCES.md`](../docs/API_AND_DATA_SOURCES.md).

For an existing database, run `sql/add_cities_google_place_id_unique.sql` once
in the Supabase SQL Editor before using `/cities/resolve`. New databases receive
the same uniqueness rule from the SQLModel metadata automatically.

## Example: create a city

```bash
curl -X POST "http://127.0.0.1:8000/cities" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Jaipur",
    "state": "Rajasthan",
    "country": "India",
    "latitude": 26.9124,
    "longitude": 75.7873,
    "google_place_id": null
  }'
```

Copy the `id` from the response for the place request below.

## Example: create a place

```bash
curl -X POST "http://127.0.0.1:8000/places" \
  -H "Content-Type: application/json" \
  -d '{
    "city_id": "PASTE_CITY_UUID_HERE",
    "name": "Hawa Mahal",
    "category": "heritage",
    "latitude": 26.9239,
    "longitude": 75.8267,
    "rating": 4.5,
    "review_count": 12000,
    "is_popular": true,
    "is_heritage": true,
    "is_local_speciality": false,
    "last_fetched_at": null
  }'
```
