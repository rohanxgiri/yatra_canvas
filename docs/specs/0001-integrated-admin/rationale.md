# Architecture inspection before implementation

Date: 2026-10-07

[IMPLEMENTED] Flutter uses Material 3, widget state, ChangeNotifier session presentation, Navigator, small HTTP services, LocalFirstClient and separate SQLite pack/enrichment/trip databases. `main.dart` currently opens Splash and guest onboarding; dedicated account screens are UI only. Home and Explore have established protected visual designs. `main_admin.dart` launches an unprotected mock panel.

[IMPLEMENTED] FastAPI already has User roles USER/ADMIN, bcrypt password hashing, JWT login and `/me`, a database backed `require_admin` dependency, paginated users/destinations/places/trips/reports endpoints and a web dashboard. Signup, reset delivery and durable audit do not exist. Current provider status reports configuration and includes misleading fixed healthy labels. Trips use a server owned development identity; unscheduled solver reasons are not persisted.

[IMPLEMENTED] CityPack Lab and DataFactory are sibling repositories. Lab is Flutter desktop with local SQLite review/curation and QA services, no HTTP API. It owns READY/REVIEW_REQUIRED/BLOCKED release decisions and manual review, image/license/integrity/readiness gates. DataFactory owns immutable releases, evidence checked research, deduplication, validation, citylab patch import and app export. Existing Python functions and release artifacts can be adapted behind FastAPI; duplicating Lab's Dart scoring in Flutter or Python would create competing truth.

[PARTIAL] No existing network adapter connects these workflows. No exported aggregate readiness evidence means the console must display unavailable rather than invent 92/GO. The existing user offline pack projection cannot supply all canonical provenance or research metadata. Real canonical review requires a configured DataFactory release root.

Alternatives considered: a separate admin app conflicts with the request; embedding the web dashboard leaves mobile account routing unresolved; new auth/state providers would duplicate working infrastructure. Extend the existing services and keep a single guarded Flutter application.

Repository inspection included app entrypoints, account/onboarding screens, theme/widgets, draft/trip services, offline repositories, backend routers/models/security, existing admin tests/migrations, and sibling QA/research/release code through read only scouts. Wanderlog reference images are absent in this checkout. Existing deleted `.pytest_tmp_baseline` fixtures predate this work and remain untouched.
