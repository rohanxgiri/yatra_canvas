# YatraCanvas project context

Last reviewed: 2026-08-31

This document is the primary overview for humans and agents. Status labels mean:

- `[IMPLEMENTED]`: a working repository code path and supporting tests/evidence exist.
- `[PARTIAL]`: some code or UI exists, but an essential part of the flow is absent.
- `[PLANNED]`: intended direction with no complete implementation in this repository.
- `[DEPRECATED]`: retained temporarily but not part of the target required architecture.
- `[UNKNOWN]`: repository or official-document evidence is insufficient.

## Product purpose and users

YatraCanvas is intended to help travellers—initially people planning trips to Indian
destinations—choose a city and arrival point, discover places, save preferences, and build a
practical itinerary. Future operators should be able to review imported place data and correct
provenance or deduplication problems.

The primary target users are independent travellers and small groups. Data reviewers and
administrators are a secondary target. Tour-operator commerce, bookings, ticketing, payments,
and a global social network are current non-goals.

## What exists today

### Technology stack

- `[IMPLEMENTED]` Flutter/Dart application with Material widgets, `http`, `geolocator`, and
  local `StatefulWidget` state. Navigation uses `Navigator`/`MaterialPageRoute`; no routing or
  application state-management package is installed.
- `[IMPLEMENTED]` Python FastAPI backend with Pydantic settings, SQLModel, psycopg 3, and a
  PostgreSQL connection. Supabase-hosted PostgreSQL is supported as a connection target.
- `[IMPLEMENTED]` Backend REST clients for Google Places API (New), Google Routes API, and
  Geoapify autocomplete. FSQ Open Source Places has a local CSV/JSONL import command.
- `[PARTIAL]` Schema evolution uses SQLModel `create_all` plus standalone SQL scripts. There is
  no versioned migration runner, and `create_all` does not alter existing tables.
- `[UNKNOWN]` Production deployment, CI, backups, monitoring, and Supabase Row Level Security:
  no Docker, CI workflow, deployment manifest, or RLS policy is tracked here.

### User journeys

| Journey | Status | Repository reality |
| --- | --- | --- |
| Splash, welcome, phone entry, onboarding | `[PARTIAL]` | UI and navigation exist; phone entry does not authenticate. |
| Select destination and dates | `[PARTIAL]` | UI and Google/stored-city services exist; no complete trip-create API persists the draft. |
| Choose arrival point | `[PARTIAL]` | Geoapify/device/custom-location UI exists; persistence only works when a pre-existing `trip_id` is supplied. |
| Choose purpose and preferences | `[PARTIAL]` | UI captures draft values; the normal flow does not persist a new trip/preferences. |
| Discover/recommend places | `[IMPLEMENTED]` | Backend endpoints read cached canonical places and can refresh via Google Nearby Search. |
| Save places | `[PARTIAL]` | API/UI exist for an existing trip; the regular create flow never assigns a trip ID. |
| Optimize itinerary | `[PARTIAL]` | Google route matrix and constraints exist, but output is day 1 only and requires an existing trip. |
| Interactive map | `[PLANNED]` | No map SDK/package or interactive map widget is present. Decorative artwork is not a map implementation. |
| Weather and currency | `[PLANNED]` | No endpoints, clients, models, or settings exist. |
| Admin review | `[PARTIAL]` | A mock admin shell and import-review schema exist; there are no admin APIs or connected review actions. |

The Flutter repository contains more than twenty visual states when the multi-step onboarding
and admin sub-pages are counted, but only a smaller set of distinct screen classes. Screen count
is not treated as evidence that the intended end-to-end product is complete.

## Intended direction

`[PLANNED]` Supabase Auth plus PostgreSQL become the canonical identity and application-data
layer. Open POI data is ingested in controlled batches from FSQ OS Places and, where justified,
OpenStreetMap/Overpass. Wikimedia can enrich descriptions and images while retaining per-item
licensing. Geoapify remains narrowly responsible for runtime autocomplete/geocoding.
openrouteservice replaces Google Routes after parity and cache tests. Open-Meteo and Frankfurter
provide weather and exchange-rate information after licensing and product decisions.

Google Places is `[DEPRECATED]` in the target architecture but `[IMPLEMENTED]` and still needed
by current city resolution and nearby discovery. Google Routes is likewise current but targeted
for replacement. Google Maps SDK is assessed independently and is currently not installed.

## Constraints

- Provider data is a candidate source, not automatically trusted canonical data. Preserve
  source IDs, timestamps, licensing/attribution metadata, and review state.
- Keep external-provider secrets on the backend. Flutter normally calls YatraCanvas APIs.
- Preserve nullable `google_place_id` and its unique constraint until a verified backfill and
  reversible migration prove it safe to retire.
- Never infer proprietary FSQ fields such as ratings from the open dataset; use only its
  documented schema.
- India-first filtering and conservative deduplication are deliberate initial boundaries.
- Do not run import or migration commands against production without review, backup, and a
  tested rollback path.

## Source-of-truth map

- [Complete ChatGPT handoff](CHATGPT_PROJECT_HANDOFF.md): self-contained snapshot for a new conversation.
- [Architecture](ARCHITECTURE.md): current and target components and flows.
- [APIs and data sources](API_AND_DATA_SOURCES.md): provider ownership, policy, cache, and fallback.
- [Data model](DATA_MODEL.md): current schema, provenance, and migration expectations.
- [Environment variables](ENVIRONMENT_VARIABLES.md): every accepted configuration name.
- [Roadmap](ROADMAP.md): phased work and acceptance criteria.
- [Decisions](DECISIONS.md): architectural decisions and evidence.
- [API-key audit](api-key-audit.md): detailed key/reference audit.

`docs/PROJECT_DOCUMENTATION.md`, its generated DOCX, and the screenshots under `docs/screenshots/`
are historical UI documentation. When they conflict with this source-of-truth set or current
code, current code and these dated documents take precedence.
