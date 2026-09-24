# YatraCanvas

YatraCanvas is a Flutter and FastAPI travel planning application focused first on Indian
destinations.

`[IMPLEMENTED]` The current repository includes the traveller app, a PostgreSQL backed FastAPI
API, cache first place discovery, saved places, multi day itinerary optimization, road route
geometry, weather assistance, JWT protected administration APIs, POI moderation, and a web admin
dashboard.

`[PARTIAL]` The traveller app still uses a guest session and a server owned development user.
Supabase Auth integration, authenticated traveller ownership, restart durable trip history, an
ordered migration runner, and always on background job delivery remain incomplete.

For the evidence backed project state, start with [Project context](docs/PROJECT_CONTEXT.md).

## Repository layout

| Path | Purpose |
| --- | --- |
| `lib/` | Flutter traveller app and the separate Flutter admin shell |
| `test/` | Flutter unit, widget, flow, and golden tests |
| `backend/app/` | FastAPI routers, services, models, configuration, and admin web assets |
| `backend/tests/` | Backend tests |
| `backend/sql/` | Reviewed manual upgrade and rollback scripts, not an ordered migration runner |
| `docs/` | Architecture, data, provider, roadmap, decision, and verification documents |
| `.agents/skills/` | Project local planning, development, testing, review, and documentation workflows |

## Prerequisites

1. Install Flutter with a Dart SDK compatible with `pubspec.yaml`. The current Dart constraint is
   `^3.13.0`.
2. Install Python 3.10 or newer. The maintained project context uses Python 3.12 or newer.
3. Install PostgreSQL, or obtain a PostgreSQL connection URL from a development database. A
   Supabase hosted PostgreSQL connection URL is supported.
4. Install the platform tooling required by your Flutter target, such as Android Studio and an
   Android emulator for Android development.

You can confirm the local toolchain from the repository root:

```powershell
flutter doctor
py --version
```

## Run the complete project locally

Use two terminals. Run the backend first, then the Flutter app.

### 1. Create the backend environment

PowerShell:

```powershell
cd backend
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
Copy-Item .env.example .env
```

macOS or Linux:

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
cp .env.example .env
```

Edit `backend/.env` and set at least:

```dotenv
APP_ENV=development
DATABASE_URL=postgresql://USER:URL_ENCODED_PASSWORD@HOST:5432/DATABASE
JWT_SECRET_KEY=replace-with-a-long-random-development-secret
```

`DATABASE_URL` is the only variable required for normal API startup. `APP_ENV=development` is
recommended locally and is required before guarded diagnostic write tests can run.
`JWT_SECRET_KEY` has a development fallback, but you should set a strong value for any shared or
deployed environment. Never commit `backend/.env`.

Optional provider settings enable individual features:

| Variable | Effect |
| --- | --- |
| `GEOAPIFY_API_KEY` | Destination, arrival, and manual place search enrichment |
| `FOURSQUARE_API_KEY` | Optional place photo enrichment only |
| `OPENROUTESERVICE_API_KEY` | Hosted openrouteservice geometry when selected |
| `GOOGLE_ROUTES_API_KEY` | Deprecated legacy route adapter only |

Normal POI recommendations use persisted data plus Audiala and OpenStreetMap or Overpass refresh.
Normal optimization uses local estimates and does not require a paid Google key. See
[Environment variables](docs/ENVIRONMENT_VARIABLES.md) for the complete inventory.

### 2. Prepare the database

For an empty development database, the backend creates missing SQLModel tables when it starts.
It does not upgrade existing tables.

For an existing database, read [the SQL change guide](backend/sql/README.md) before applying
anything. The SQL files are not an alphabetical migration chain. Do not apply repository
migrations to production as part of local setup.

### 3. Start FastAPI

From `backend/`, with the virtual environment active:

```powershell
python -m uvicorn app.main:app --reload
```

Then open:

| URL | Purpose |
| --- | --- |
| `http://127.0.0.1:8000/` | API health response |
| `http://127.0.0.1:8000/docs` | Interactive API documentation |
| `http://127.0.0.1:8000/admin/` | Web admin dashboard |

### 4. Install Flutter packages

In the second terminal, from the repository root:

```powershell
flutter pub get
```

### 5. Start the traveller app

The `regular` Flutter flavor is the default:

```powershell
flutter run
```

The backend URL is selected as follows:

| Target | Default backend URL |
| --- | --- |
| Android emulator | `http://10.0.2.2:8000` |
| Flutter web | `http://localhost:8000` |
| iOS simulator | `http://localhost:8000` |
| Windows, macOS, or Linux desktop | `http://localhost:8000` |
| Physical device | No automatic host discovery. Pass your computer's LAN address |

For a physical device, bind the API to the local network and pass the host address to Flutter:

```powershell
python -m uvicorn app.main:app --reload --host 0.0.0.0
flutter run --dart-define=API_BASE_URL=http://192.168.1.50:8000
```

Replace the sample address with the development computer's LAN address. Allow the port through
the local firewall only on a trusted network.

Useful explicit targets include:

```powershell
flutter run -d chrome
flutter run -d windows
flutter run -d <device-id> --dart-define=API_BASE_URL=http://YOUR_HOST:8000
```

## Run the admin experiences

### Web admin dashboard

The implemented operational dashboard is served by FastAPI. Before signing in, create an admin
account from `backend/`:

```powershell
python -m app.scripts.create_admin --email admin@yatracanvas.com
```

The command prompts for a password and stores only its bcrypt hash. You can also set
`ADMIN_EMAIL` and `ADMIN_PASSWORD` in the untracked `backend/.env`. To reset an existing admin
password:

```powershell
python -m app.scripts.create_admin --email admin@yatracanvas.com --update-password
```

Start the API and open `http://127.0.0.1:8000/admin/`. The dashboard uses the implemented
`POST /api/auth/login`, `GET /api/auth/me`, and protected `/api/admin/*` endpoints.

### Flutter admin shell

The repository also contains a separate Flutter admin flavor:

```powershell
flutter run --flavor admin -t lib/main_admin.dart
```

`[PARTIAL]` This Flutter shell is not the operational web dashboard and still contains local
presentation data. Use the FastAPI served web dashboard for the implemented admin API workflow.

## Development checks

Install backend development tools once in the active virtual environment:

```powershell
cd backend
python -m pip install -r requirements-dev.txt
```

Run backend checks from `backend/`:

```powershell
python -m pytest
python -m ruff check app tests
python -m black --check app tests
python -m mypy app
```

Run Flutter checks from the repository root:

```powershell
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed lib test
```

Some integration paths call public or configured providers and need the corresponding environment
settings. Run only safe tests against development or test databases. Never point diagnostic writes
at an unclassified, staging, or production database.

## Project documentation

| Document | Purpose |
| --- | --- |
| [Project context](docs/PROJECT_CONTEXT.md) | Concise current status and product boundary |
| [Architecture](docs/ARCHITECTURE.md) | Detailed current and target architecture |
| [APIs and data sources](docs/API_AND_DATA_SOURCES.md) | Provider ownership, caching, attribution, and fallback policy |
| [Data model](docs/DATA_MODEL.md) | Current models, constraints, and migration rules |
| [Environment variables](docs/ENVIRONMENT_VARIABLES.md) | Complete configuration inventory |
| [Roadmap](docs/ROADMAP.md) | Delivery status and acceptance criteria |
| [Decisions](docs/DECISIONS.md) | Accepted architecture decisions |
| [Agent workflow](docs/AGENT_WORKFLOW.md) | How to use the project local workflow skills |
| [Backend guide](backend/README.md) | Backend details, APIs, providers, and import commands |

Generated document files and screenshots under `docs/` may describe earlier UI snapshots. Treat
the seven source of truth documents linked above as authoritative for current architecture.

## Agent workflow skills

The repository includes project local `scope`, `audit`, `architect`, `develop`, `check`, `test`,
`document`, `sync`, and `debug` skills under `.agents/skills/`. Read
[Agent workflow](docs/AGENT_WORKFLOW.md) and root [AGENTS.md](AGENTS.md) before using them. The
roadmap and source of truth documents take precedence over generic skill defaults.

## Security and deployment notes

1. Keep database URLs, JWT secrets, and provider keys only in backend environment configuration.
2. Never add secrets to Flutter, logs, screenshots, examples, tests, or commits.
3. Public Overpass and OSRM endpoints are useful for development but do not provide a production
   service guarantee.
4. FastAPI currently runs `SQLModel.metadata.create_all` at startup. An ordered migration runner
   and environment restricted schema initialization are still `[PLANNED]`.
5. Deployment configuration, backup objectives, centralized logs, and production monitoring are
   `[UNKNOWN]` because this repository does not define them.
