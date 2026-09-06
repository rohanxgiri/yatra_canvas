# YatraCanvas

YatraCanvas is a Flutter and FastAPI travel-planning application focused first
on Indian destinations. The repository currently supports destination and arrival lookup,
cache-first POI discovery with progressive prefetch (OpenStreetMap, Audiala seed, Geoapify fallback),
canonical multi-source Place identity and importance scoring, destination-scoped manual place search,
saved place curation, multi-day itinerary optimization via Google OR-Tools VRPTW solver (with complete
logical day sequence preservation), keyless road-route geometry (OSRM / openrouteservice), progressive
Frame-1 interactive map rendering (FlutterMap + OSM tiles), weather-aware trip assistance (Open-Meteo),
and smart re-planning. Supabase Auth JWT verification, restart-durable multi-trip account persistence,
and real admin review APIs remain planned.

Start with [the project context](docs/PROJECT_CONTEXT.md). It is the entry point to the
evidence-backed source of truth:

- [Single-file ChatGPT project handoff](docs/CHATGPT_PROJECT_HANDOFF.md)
- [Architecture](docs/ARCHITECTURE.md)
- [APIs and data sources](docs/API_AND_DATA_SOURCES.md)
- [Data model](docs/DATA_MODEL.md)
- [Environment variables](docs/ENVIRONMENT_VARIABLES.md)
- [Roadmap](docs/ROADMAP.md)
- [Architectural decisions](docs/DECISIONS.md)
- [Backend setup and commands](backend/README.md)
- [API-key audit](docs/api-key-audit.md)

## Local setup

1. Install a Flutter SDK compatible with `pubspec.yaml` and Python 3.10 or newer.
2. Follow [the backend setup](backend/README.md), including copying
   `backend/.env.example` to an untracked `backend/.env`.
3. Start FastAPI from `backend/` with `uvicorn app.main:app --reload`.
4. Start the regular traveller app from the repository root with `flutter run`; `regular` is the
   default flavor. Override the backend URL when needed with
   `flutter run --dart-define=API_BASE_URL=http://YOUR_HOST:8000`. Start the separate Android
   admin flavor with `flutter run --flavor admin -t lib/main_admin.dart`.

`DATABASE_URL` is the only backend variable required to start. Provider keys are optional
and only enable their corresponding implemented endpoints. See
[Environment variables](docs/ENVIRONMENT_VARIABLES.md) before requesting any key.

## Development checks

Backend tests live in `backend/tests/`; Flutter tests live in `test/`. The repository also
provides backend development dependencies in `backend/requirements-dev.txt`. Run the checks
relevant to your change and do not commit local `.env` files or credentials.

The generated document files and screenshots under `docs/` describe an earlier UI snapshot.
They are historical references, not the current architecture source of truth.
