# 0002. Offline admin login

**Date**: 2026-10-13
**Status**: Accepted

## Summary

[PLANNED] The user explicitly requires admin credential login while the phone is offline.
Add an explicit Offline admin mode to the existing sign in form. The local showcase
credentials unlock a device workspace immediately, without calling the backend.

## Requirements

1. AC-1: The documented local showcase email and password can enter Offline admin on a
   fresh installation, with zero authentication requests. Incorrect credentials fail.
2. AC-2: A successful local session persists in native secure storage, restores without
   internet, and logout clears it and resets navigation. Passwords are never persisted.
3. AC-3: Local access has no JWT or server ADMIN authority. AdminRepository rejects it
   before making a request, and AuthenticatedClient never attaches a local bearer token.
4. AC-4: The local view reads real installed city pack metadata, searchable places and
   bundled photos. Backend operations remain visibly dependent on an online admin login.
5. AC-5: Existing guest and registered account behavior remains covered by regression
   tests. Install an update on the connected phone without uninstalling existing data.

## Decision and value sources

[PLANNED] Keep AuthSession and backend authorization unchanged. Add a distinct
AuthStatus.offlineAdmin and a versioned secure storage marker, with no role or token.
Validate the public local showcase credential using a compiled digest. It is a convenience
unlock for bundled device data, not a secret, production identity, or server authorization.
Only explicit Offline admin sign in uses it; online login never falls back after rejection.

[PLANNED] Reuse CityPackRepository and AdminTheme. Its manifest, validated SQLite and
bundled asset paths supply all local values. Do not invent live metrics or City Lab scores,
edit immutable assets, publish corrections, or introduce a backend migration or variable.
The existing admin mobile screenshot supplies visual direction; Wanderlog references are
absent in this checkout. The user clarified that local correction editing is not requested.

## Build plan

1. Local credential validation, secure marker lifecycle and central navigation (AC-1..3).
2. Explicit form mode and device dataset view (AC-1, AC-4).
3. Regression tests, physical phone verification, source documentation and APK (AC-2..5).

## Consequences and rationale

[PARTIAL] Offline admin can inspect device data. User management, server moderation,
provider health, canonical repair and publication still require existing authorized services.
An offline login cannot prove a server role. A separate state avoids fabricated JWTs and
retains live server role checks. First login is possible without prior online enrollment,
which cached JWT restoration alone cannot provide.

## References

Project sources: ADR-028 and ADR-029, docs/OFFLINE_CITY_PACK_ARCHITECTURE.md,
lib/models/auth_controller.dart, lib/admin/data/admin_repository.dart,
lib/services/city_pack_repository.dart and docs/specs/0001-integrated-admin/index.md.

## Delivery evidence

[IMPLEMENTED] The local credential state, explicit form mode, secure marker restoration
and installed dataset screen are built. All 47 targeted authentication, admin and offline
pack tests pass, including wrong credential rejection, zero auth requests, lack of server
authority, stale response isolation and logout. Flutter analysis reports no issues.

[IMPLEMENTED] Release version code 20261014 installed on the connected SM_S911B phone
using `adb install -r`, without uninstalling its data. With no backend reverse forwarding,
the phone displays Offline Admin and the actual 685 place Jaipur pack with 18 bundled
photo records. Force stop and relaunch restore that local session with the backend still
disconnected. Native screenshot and restored UI evidence are in the local build share
directory. The APK uses the existing development signing key and USB online API address.

[PARTIAL] This physical check covers the local mode and restoration, not server identity,
canonical publication, general phone performance or the unimplemented production lifecycle.
