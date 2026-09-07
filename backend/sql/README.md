# YatraCanvas manual database changes

Last reviewed: 2026-09-07

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
- all expected TripDay rows for the 21 trips in the audit;
- valid assignment state for all 100 saved-place rows.

Pending against the current models:

1. `add_places_opening_hours.sql` — the normalized table exists and is empty, but
   `places.opening_hours_status`, `places.raw_opening_hours`,
   `place_sources.raw_opening_hours`, and `ck_places_opening_hours_status` are absent. Its
   existing place foreign key also needs alignment from `NO ACTION` to `ON DELETE CASCADE`.
2. `add_trip_itinerary_status.sql` — `trip_itinerary.status` and
   `ck_trip_itinerary_status` are absent; 92 existing rows will receive `PLANNED`.

Do not rerun the older scripts on this database. Do not run a rollback script as an
installation step. Applying the two pending scripts still requires explicit confirmation that
the target is a development/test database and that a recoverable backup or Supabase restore
point exists.

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

`repair_current_schema_parity.sql` is a convergence repair for the older provider and route
scripts. On the currently configured database its effects are already present, so rerunning the
historical chain adds no value and makes execution history harder to understand.

## Rollback files

Files beginning with `rollback_` remove schema and may discard data. They are recovery tools for
their matching forward migration, not later steps in the sequence. Use one only as part of a
reviewed restore plan. In particular, `rollback_fsq_geoapify_foundation.sql` drops provenance
tables and columns, and `rollback_trip_days_foundation.sql` drops configured trip days with
dependent assignment data.

## Verification checklist

Before a forward change:

- confirm the exact Supabase project is development/test;
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
