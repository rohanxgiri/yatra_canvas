# YatraCanvas manual database changes

Last reviewed: 2026-09-27

This directory contains upgrade scripts for databases created by older versions of
YatraCanvas. It is not an ordered migration runner, and filenames must not be executed
alphabetically. New empty databases should be created from the current SQLModel metadata;
they do not need this historical chain.

## Configured Supabase audit snapshot

The configured remote database was inspected in a read-only transaction on 2026-09-07.
It contains application data, and the repository does not identify the project as development,
staging, or production. No backup or restore point can be verified from this repository.

Already present:

- route matrix, priority, start-location, FSQ/Geoapify, city/provider uniqueness,
  schema-parity repair, Wikidata, importance score, TripDay, and saved-place assignment changes;
- all 80 expected TripDay rows for the 22 trips in the audit;
- valid assignment state for all 100 saved-place rows.

The same audit found the historical `place_categories.created_at` column created by
`add_fsq_geoapify_foundation.sql`. The SQLModel definition now includes that preserved column;
no database change is required for it.

Current-model migrations verified as applied on 2026-09-07:

1. `add_places_opening_hours.sql` — all three source/canonical columns, both opening-hours
   checks, indexes, unique day constraint, and `ON DELETE CASCADE` place foreign key are present.
   All 1,265 existing places were preserved and defaulted to `opening_hours_status='UNKNOWN'`.
2. `add_trip_itinerary_status.sql` — the status column, default, and lifecycle check are present.
   All 92 existing itinerary rows were preserved and backfilled to `PLANNED`.
3. `add_admin_auth_and_moderation.sql` — users and place_reports tables, destination management columns
   on cities (`is_enabled`, `is_featured`, `is_popular`, `image_url`, `description`, `display_order`),
   and `moderation_status` column and check on places verified as applied on 2026-09-14. All existing
   cities preserved with `is_enabled=true`, and all existing places preserved with `moderation_status='ACTIVE'`.

Deployment state after the 2026-09-27 cache/persistence repair:

- `add_provider_cooldowns.sql` is `[IMPLEMENTED]` in repository models/tests and remains
  unapplied by repository work. It adds shared provider backoff metadata only; it does not alter
  canonical places or image cache rows. `rollback_provider_cooldowns.sql` drops cooldown history
  only.
- `add_place_refresh_jobs.sql` is `[IMPLEMENTED]` in repository models/tests and its complete
  schema is present in the configured development database. The 2026-09-27 recovery manifest
  contained 57 durable refresh-job rows, and concurrent-request verification found no duplicate
  job keys. Its original deployment actor remains `[UNKNOWN]` because there is no migration
  ledger. `rollback_place_refresh_jobs.sql` drops job history only and is a reviewed destructive
  recovery helper, not an installation step.
- `add_place_image_cache.sql` is `[IMPLEMENTED]` in repository models/tests. A read-only catalog
  inspection found `place_image_cache` already present on the configured remote database with the
  expected columns, indexes, constraints, and no server default on `fetched_at`. Its creation
  mechanism remains `[UNKNOWN]`; unconditional startup `create_all` may have created it. The SQL
  now matches the ORM/application-owned `fetched_at` behavior. Do not rerun it against the
  unclassified remote database.
- `backend/scripts/verify_place_image_cache.py` performs catalog checks in a PostgreSQL-enforced
  read-only transaction by default. Its optional `--write-test` is rejected unless `APP_ENV` is
  explicitly `development` or `test`, commits uniquely identified temporary rows, verifies them
  in a fresh session, and deletes only those rows in cleanup.
- `add_place_opening_hours_updated_at.sql` is `[IMPLEMENTED]` in repository models/tests and was
  permanently applied to the configured development database on 2026-09-27. A fresh connection
  verified the non-null column and all 651 pre-existing rows; later real refreshes wrote additional
  rows without the prior `UndefinedColumn` failure.
- `add_city_identity_and_sources.sql` is `[IMPLEMENTED]` in repository models/API/tests and was
  permanently applied in the same guarded transaction. It preserved provider IDs, reassigned the
  six known city foreign keys, consolidated the one duplicate normalized identity, backfilled 23
  legacy identities, and installed `uq_cities_normalized_identity`.

Before application, a transactionally consistent database-side recovery snapshot was created as
schema `migration_backup_20260927t121718z`. The manifest was checked in the same transaction:
28 cities, 2,625 places, 94 trips, 0 import reviews, 1 city source, 133 category-cache rows, 57
refresh jobs, and 651 opening-hour rows. Post-commit verification from a fresh connection found 27
cities, 24 city sources, zero normalized duplicates, zero orphan city sources, and both expected
schema objects. The snapshot remains in the database as the authoritative before-state for a
reviewed rollback; it is not a platform-level disaster-recovery backup.

Do not rerun either applied script or an older script on this database without first auditing the
complete result, and do not run a rollback script as an installation step.

## Historical upgrade order

For an audited legacy database, use this dependency order. At every step, skip a script whose
complete result is already present. Run each forward script in a reviewed transaction and verify
the catalog before continuing.

1. `add_route_matrix_priorities_start_location.sql`
2. `add_cities_google_place_id_unique.sql`
3. `add_place_sources_external_id_unique.sql`
4. `add_fsq_geoapify_foundation.sql`
5. `add_places_canonical_wikidata.sql`
6. `add_places_importance_score.sql`
7. `repair_current_schema_parity.sql`
8. `add_trip_days_foundation.sql`
9. `add_places_opening_hours.sql`
10. `add_saved_places_assignment_mode.sql`
11. `add_trip_itinerary_status.sql`
12. `add_admin_auth_and_moderation.sql`
13. `add_place_image_cache.sql`
14. `add_place_refresh_jobs.sql`
15. `add_provider_cooldowns.sql`
16. `add_place_opening_hours_updated_at.sql`
17. `add_city_identity_and_sources.sql`

`repair_current_schema_parity.sql` is a convergence repair for the older provider and route
scripts. On the currently configured database its effects are already present, so rerunning the
historical chain adds no value and makes execution history harder to understand.

## Rollback files

Files beginning with `rollback_` remove schema and may discard data. They are recovery tools for
their matching forward migration, not later steps in the sequence. Use one only as part of a
reviewed restore plan. In particular, `rollback_fsq_geoapify_foundation.sql` drops provenance
tables and columns, `rollback_trip_days_foundation.sql` drops configured trip days with
dependent assignment data, and `rollback_admin_auth_and_moderation.sql` drops place reports,
users, and admin moderation/destination columns.
`rollback_place_refresh_jobs.sql` drops only durable refresh coordination history.
`rollback_provider_cooldowns.sql` drops only provider backoff history.
`rollback_place_opening_hours_updated_at.sql` drops only the update timestamp.
`rollback_city_identity_and_sources.sql` drops the identity index and provider identity table; it
cannot recreate duplicate cities consolidated by the forward repair.

## Verification checklist

Before a forward change:

- set `APP_ENV` explicitly and confirm the exact target is development/test;
- create and record a recoverable backup, branch, or point-in-time restore target;
- run a read-only catalog and data-precondition audit;
- stop application writers if the migration requires it.

After a forward change:

- verify expected columns, defaults, indexes, foreign keys, and named checks;
- verify pre-existing row counts and backfilled values;
- run backend model/import/API tests;
- record the execution actor, timestamp, script checksum, and target project outside secrets.

The repository still has no application migration ledger. Adopting an ordered migration tool
remains `[PLANNED]`.
