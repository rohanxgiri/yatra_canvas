# YatraCanvas Backend

This folder contains the initial FastAPI and PostgreSQL backend for
YatraCanvas. It provides city and place storage endpoints plus server-side
Google Places city discovery. Authentication, recommendations, and route
optimization are not part of this phase.

At startup, SQLModel creates any missing tables defined in `app/models`. This
keeps the first phase migration-free. A proper migration workflow can replace
this when the schema starts evolving.

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

## 3. Configure the Supabase PostgreSQL connection

Copy the example file:

```powershell
Copy-Item .env.example .env
```

Open `backend/.env` and paste the PostgreSQL connection string supplied by
Supabase immediately after `DATABASE_URL=`:

```dotenv
DATABASE_URL=postgresql://YOUR_DATABASE_USER:YOUR_URL_ENCODED_PASSWORD@YOUR_DATABASE_HOST:5432/postgres
GOOGLE_PLACES_API_KEY=YOUR_SERVER_SIDE_GOOGLE_PLACES_KEY
```

Do not add quotes and do not commit `.env`. The repository's root `.gitignore`
already excludes it. If the database password contains URL-reserved characters
such as `@`, `:`, `/`, `#`, or `%`, URL-encode the password before using it in
the connection string.

Enable Places API (New) in the Google Cloud project that owns the key. Keep the
key only in `backend/.env`; it must never be added to Flutter or committed.

The backend keeps `trips.user_id` as a UUID but does not create or reference
Supabase's `auth.users` table. Authentication integration will be added later.

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
| `POST` | `/cities/resolve` | Return or create a city by Google Place ID |
| `GET` | `/cities/search?query=` | Search stored cities by name or state |
| `GET` | `/cities/autocomplete?query=` | Search Google for India city predictions |
| `GET` | `/cities/place-details/{google_place_id}` | Normalize Google city details |
| `GET` | `/cities/{city_id}` | Get a city |
| `POST` | `/places` | Create a place |
| `GET` | `/cities/{city_id}/places` | List a city's places |

List endpoints accept optional `offset` and `limit` query parameters. `limit`
defaults to 100 and cannot exceed 500.

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
