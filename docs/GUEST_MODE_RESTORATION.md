# Guest mode restoration and admin presentation

Last reviewed: 2026-10-12

## Cause and correction

`[IMPLEMENTED]` The regression was in uncommitted changes layered over the last committed
guest flow. `AuthGate` sent signed-out travellers to sign-in after onboarding. Separately,
`trip_actor` returned 401 unless `ALLOW_DEV_GUEST` was explicitly enabled, and the shared
trip guard covered creation, days, saved places, optimization, geometry, weather and replanning.
Hiding the login screen alone would therefore have left server trip creation broken.

`[IMPLEMENTED]` The traveller gate now opens Home after onboarding completion or Skip.
Home, Explore and Create Trip keep their existing visuals and navigation. Account entry is
optional, labeled honestly and dismissible. The dedicated admin entry remains authenticated.
Restored accounts keep their existing role routing. Traveller logout returns to guest Home.

`[IMPLEMENTED]` Token-free trip requests use the original server-owned guest UUID, preserving
existing guest trip IDs without a schema or data migration. No account or guest flag is needed.
Authenticated travellers retain ownership checks; anonymous requests cannot access account
trips. Invalid supplied tokens are rejected, and administrative trip inspection stays separate.
All admin APIs keep `require_admin`, live role/activity checks and the existing audit behavior.
The compatibility variable `ALLOW_DEV_GUEST` is retained but no longer controls traveller access.

## Admin presentation

`[IMPLEMENTED]` Flutter Admin Studio uses the existing Flutter/Material stack and a scoped
`AdminTheme` derived from the approved YatraCanvas blue, cream and ink tokens. Its cream
sidebar and compact blue brand mark distinguish the workspace. Typography, spacing, metric
cards, tabular numbers, navigation selection, labeled dropdown filters, borders, buttons and
status icons are consistent. Existing loading, partial failure, empty, pagination and refresh
behavior remain. No new metrics, data source, pipeline, authentication system or migration
was introduced. No external component inspiration or new assets were needed.

Phone, tablet and desktop widget renders use the existing test fixture data, not live counts:

- [Phone, 390 pixels](verification/admin-guest-correction-390.png)
- [Tablet, 840 pixels](verification/admin-guest-correction-840.png)
- [Desktop, 1440 pixels](verification/admin-guest-correction-1440.png)

## Persistence limits

`[IMPLEMENTED]` Native prepared-city trips keep the original device-local guest SQLite file.
Trip state, selections, day settings and itineraries survive reopening that store, including
with the network unavailable. Account-specific files remain separate and legacy rows are not
reassigned. Online trips use the existing server persistence and shared guest namespace.

`[PARTIAL]` `YatraSession` saved/history presentation snapshots remain in memory. Automatic
trip history restoration, private per-guest online storage and cross-device guest history are
not implemented. An online trip ID can retrieve its existing guest record, but there is no
traveller server listing/history UI. Offline routes remain approximate coordinate overviews;
offline street tiles, road routing and live weather are unavailable.

## Verification evidence

`[IMPLEMENTED]` The regression test first reproduced `POST /trips` returning 401 with
`ALLOW_DEV_GUEST=false`. It passes after the scoped guest correction, including guest/account
separation, unchanged guest UUID, no synthetic registered guest account and invalid-token checks.

| Check | Result |
| --- | --- |
| Full backend suite with the guest flag disabled | 495 passed, 1 skipped |
| Final auth, config and documentation checks, including five environment cases | 41 passed |
| Full Flutter suite after updating obsolete compulsory-login assertions | 328 passed |
| Flutter analysis | No issues |
| Admin widget rendering with bundled fonts at 390, 840 and 1440 pixels | 3 passed, inspected visually |
| Configured local backend without authentication | 17 HTTP checks passed, including create, idempotent retry, edit, days, three saved places, optimization, itinerary and route geometry |
| Admin protection on configured backend | Dashboard and system health returned 401 without credentials |
| Offline city pack suite | Included in the full Flutter run, including no-network planning, persistence across store restart, pack upgrade and account separation |

`[IMPLEMENTED]` The configured-backend verification created one clearly named Ziro test trip
with three scheduled stops. No database migration was applied. The full Flutter suite verifies
cold guest launch, guest launch after restart, completion/Skip, optional account dismissal,
Home/Create navigation and the existing five-step creation flow. Existing backend integration
tests cover optimization, stop execution, editing and replanning.

`[IMPLEMENTED]` The running Flutter web preview completed the guest journey without credentials:
onboarding Skip, Home, Explore, Create Trip, Ziro selection, dates, a confirmed city-centre start,
Sightseeing interest and travel preferences, backend trip creation, four recommendations,
saved District Museum, map day filters and a place sheet, route optimization and the generated
Day 2 itinerary (09:01 to 10:01, approximately 60 minutes). The result is visible in
[the guest itinerary screenshot](verification/guest-web-itinerary.jpg). This browser-created
verification trip is additional to the clearly named HTTP verification trip.

`[PARTIAL]` Basemap tiles did not render in the in-app browser preview, although the map markers,
day controls and place sheet worked. The configured backend route-geometry request returned 200.
The installed Android emulator repeatedly exited after app launch; Android build succeeded,
but this does not establish physical-device acceptance, Android motion quality or release
frame-rate measurements. Web verification does not establish native SQLite or offline tile support.

## Files changed for this correction

`[IMPLEMENTED]` Entry behavior lives in `lib/main.dart`, `lib/screens/auth/auth_gate.dart`,
the optional account/login entries and the onboarding completion path. The guest actor and its
existing ownership guard live in `backend/app/core/trip_access.py`. Admin presentation is scoped
to `lib/admin/admin_theme.dart`, its shell, dashboard, collections and shared components.
Regression expectations and the final onboarding-label golden were updated. Source-of-truth
documents record the superseding guest decision and the existing persistence limits.

Unrelated working-tree changes were preserved. No whole commit was reverted, no new migration
was added or applied, and no further account or authentication feature was developed.
