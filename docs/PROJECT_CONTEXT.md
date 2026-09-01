# YatraCanvas project context

Last reviewed: 2026-09-01

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
| Select destination and dates | `[PARTIAL]` | The normal Flutter flow searches stored cities, uses Geoapify city autocomplete when needed, persists a normalized city without requiring Google, and submits its ID, dates, and inclusive day count to `POST /trips`; the calendar remains fixed to August 2026. |
| Choose arrival point | `[PARTIAL]` | Trip creation persists the draft's arrival/start fields. Geoapify/device/custom locations can supply coordinates, but the built-in station/airport suggestions remain destination-specific mock data and may have no coordinates. |
| Choose purpose and preferences | `[IMPLEMENTED]` | The normal flow persists selected purposes, pace, budget, and transport choices as `TripPreference` rows in the trip-create transaction. |
| Discover/recommend places | `[PARTIAL]` | The normal recommendation flow performs bounded OpenStreetMap/Overpass queries, persists ODbL source metadata, caches results, and shows attribution. Public Overpass availability and raw OSM data quality are not production guarantees. |
| Save places | `[IMPLEMENTED]` | Place Discovery uses the real `TripDraft.tripId` to load, add, customize, reorder, and delete persisted saved places. Duplicate conflicts and failed mutations reconcile with backend state instead of leaving optimistic local data. |
| Optimize itinerary | `[PARTIAL]` | Constraint-aware day-1 ordering works with cached offline coordinate estimates. Distances/times are approximate; road directions and multi-day planning are absent. |
| Interactive map | `[PLANNED]` | No map SDK/package or interactive map widget is present. Decorative artwork is not a map implementation. |
| Weather and currency | `[PLANNED]` | No endpoints, clients, models, or settings exist. |
| Admin review | `[PARTIAL]` | A mock admin shell and import-review schema exist; there are no admin APIs or connected review actions. |

The Flutter repository contains more than twenty visual states when the multi-step onboarding
and admin sub-pages are counted, but only a smaller set of distinct screen classes. Screen count
is not treated as evidence that the intended end-to-end product is complete.

`[IMPLEMENTED]` For the current unauthenticated development slice, `POST /trips` creates a `Trip`
and related `TripPreference` rows transactionally and returns an application-generated UUID.
`GET /trips/{trip_id}` and `PATCH /trips/{trip_id}` allow loading and partially updating an
existing trip, including destination, dates/days, arrival/start coordinates, provider IDs, and
preferences.
`[PARTIAL]` The UUID is retained in the in-memory `TripDraft` and can be loaded/edited via
`TripService`; full trip history/listing UI, multi-trip persistence across accounts, ownership
enforcement, and authentication are not implemented. Until authentication exists, the backend
assigns a server-owned development-only placeholder `user_id` and rejects any client-supplied
identity or internal trip fields.

`[IMPLEMENTED]` The selected-places section is backed by `UserSavedPlace` rows rather than mock
state. It persists `custom_order`, `priority`, `is_locked`, `must_visit`, and `notes`, and reloads
authoritative order after a failed reorder. `[PARTIAL]` Changing a trip's city currently preserves
saved places from the prior city. This avoids silent data loss but can leave cross-city selections;
no automatic deletion or migration policy has been invented.

## Intended direction

`[PLANNED]` Supabase Auth plus PostgreSQL become the canonical identity and application-data
layer. Open POI data is ingested in controlled batches from FSQ OS Places and, where justified,
OpenStreetMap/Overpass. Wikimedia can enrich descriptions and images while retaining per-item
licensing. Geoapify remains narrowly responsible for runtime autocomplete/geocoding.
openrouteservice replaces Google Routes after parity and cache tests. Open-Meteo and Frankfurter
provide weather and exchange-rate information after licensing and product decisions.

Google Places and Google Routes are `[DEPRECATED]` legacy adapters. The normal Flutter
destination, recommendation, trip-create, and route-ordering flow does not require either key.
Google Maps SDK is assessed independently and is currently not installed.

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
