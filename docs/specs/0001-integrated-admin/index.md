# Integrated authentication and admin console

**Status**: In Progress
**Date**: 2026-10-07

## Summary

[PLANNED] Implement the user's supplied authentication and operational console request in the existing Flutter application. Reuse FastAPI JWT accounts, `require_admin`, existing admin resources, and immutable DataFactory releases. The request authorizes implementation; no external service connection or production migration is authorized.

## Requirements

1. AC-1: Dedicated login, signup and honest password reset screens, validation, loading and safe errors.
2. AC-2: Central role model, secure native session persistence, startup gate, separate navigation stacks and logout that clears navigation.
3. AC-3: Explicitly enabled development admin credentials, never usable in staging or production.
4. AC-4: Responsive integrated admin dashboard, City Lab, trips, users, research, packs, health and audit pages using real paginated backend data.
5. AC-5: Preserve canonical city identity, provenance, QA vocabulary and existing confidence/readiness rules. Corrections are reviewed overlays, never writes to installed app assets.
6. AC-6: Read only trip inspection with actual days, saved places, itinerary and honest unavailable planner history.
7. AC-7: Privileged actions require server authorization, confirmations and atomic audit evidence.
8. AC-8: Home and Explore visual files stay unchanged. Existing offline planning remains available with a restored user session or explicit guest entry.
9. AC-9: Backend and Flutter regression checks, migration verification on disposable databases, and a complete limitations report.

## Decision

[PLANNED] Extend the existing local JWT backend instead of adding an identity provider. Supabase Auth remains future production work. Use Flutter ChangeNotifier and Navigator, with one central gate and role guarded nested navigators. Native tokens use `flutter_secure_storage`; web sessions remain in memory. Persist a profile only with its token. Restore expired tokens by signing out; offline restoration of unexpired traveller sessions permits local packs, but never grants server access without verification.

[PLANNED] Use backend owned audit and review tables. The DataFactory adapter reads configured immutable releases and calls existing validation/export routines. Any unavailable published confidence score is nullable and labelled unavailable; no new scoring algorithm is introduced. Unsupported publish/merge capabilities are reported explicitly. Existing backend moderation statuses and City Lab QA statuses remain separate.

Implementation skills: project `architect`, `develop`, and `appllama-app-design-skill`.

## Value sourcing

| Surface | Sources |
| --- | --- |
| Accounts and role | `User`, bcrypt, existing JWT service and live `/api/auth/me` |
| Dashboard/users/trips | Existing SQLModel tables and protected admin queries |
| City Lab packs/places | Configured immutable DataFactory release JSON/manifest, backend review overlays |
| Confidence/readiness | Existing exported report when present, otherwise unavailable |
| Quality inbox | Missing fields and media inventory on actual release records |
| Research | Existing DataFactory research artifacts and explicit review state |
| Jobs/cache | `PlaceRefreshJob`, `CityCategoryCache`, `PlaceImageCache`, `ProviderCooldown` |
| Audit | Backend append only `AdminAuditEvent`, same transaction as SQL mutations |

## Design

[PLANNED] Auth uses existing Inter, YCStyle blue, cool neutral surfaces, 28 point heading, 52 point inputs and buttons, restrained borders, no decorative imagery. Admin has five compact mobile destinations and a sidebar at 700 pixels. Detail pages push within the active experience; authentication replaces the whole navigator so back cannot cross identity changes. The missing `design_reference/wanderlog/` directory was checked; existing YatraCanvas tokens and supplied visual direction govern this work.

## Build plan

- [ ] Authentication backend, state, service, persistence, gate and screens (AC-1, AC-2, AC-3).
- [ ] Operational API, review and audit migrations, real health and trip/user extensions (AC-4, AC-5, AC-6, AC-7).
- [ ] Responsive admin shell and operational detail/action pages (AC-4, AC-5, AC-6, AC-7).
- [ ] Regression tests, visual verification and source documentation (AC-8, AC-9).

## Consequences and follow up

[PARTIAL] Reset email delivery, Supabase identity, release deployment, aggregate City Lab scores where no exported report exists, and full production observability are not fabricated. Schema files are created and tested locally; applying them to any configured remote database requires its controlled deployment process.

## Implementation evidence, 2026-10-08

[IMPLEMENTED] The local authentication, role gate, ownership checks, audit/review schema and
operational console are built. The default city selection follows bundled app provenance;
timestamp ties are disclosed. The accepted decision is recorded in ADR-028. See
[the delivery report](../../AUTH_ADMIN_IMPLEMENTATION.md) for checks and feature limitations.

[PARTIAL] This spec remains In Progress for physical mobile acceptance and production
qualification. Host tests and browser renders cannot prove device storage, native gestures
or measured release performance. No production migration or external release write occurred.

## Rationale

See [inspection report](rationale.md). Secure storage package documentation verified 2026-10-07 at [the official package page](https://pub.dev/packages/flutter_secure_storage).
