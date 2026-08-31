-- YatraCanvas current-model schema parity repair.
--
-- Preconditions:
--   * Run only against a confirmed development/test PostgreSQL database.
--   * Take and verify a recoverable database backup immediately before use.
--   * Review the read-only schema audit and confirm the named public tables exist.
--   * Resolve any value longer than the VARCHAR limits below before execution.
--
-- Recovery:
--   * PostgreSQL DDL below is transactional; any error rolls the whole migration back.
--   * After COMMIT, roll forward or restore the verified backup. Do not use the older
--     destructive rollback_fsq_geoapify_foundation.sql after application writes begin.
--
-- This migration preserves rows, identifiers, provenance, licensing, lifecycle values,
-- foreign keys, and existing valid cascade behavior. It performs no DROP COLUMN, DELETE,
-- TRUNCATE, table recreation, or destructive rename.

BEGIN;

DO $$
DECLARE
    required_table text;
BEGIN
    FOREACH required_table IN ARRAY ARRAY[
        'cities',
        'places',
        'city_category_cache',
        'place_tags',
        'place_sources',
        'place_categories',
        'place_import_reviews',
        'trips',
        'trip_preferences',
        'user_saved_places',
        'route_matrix_cache',
        'trip_itinerary'
    ]
    LOOP
        IF to_regclass('public.' || required_table) IS NULL THEN
            RAISE EXCEPTION 'Required table public.% is missing', required_table;
        END IF;
    END LOOP;
END
$$;

ALTER TABLE public.place_sources
    ADD COLUMN IF NOT EXISTS source_url VARCHAR(1000),
    ADD COLUMN IF NOT EXISTS licence_identifier VARCHAR(120),
    ADD COLUMN IF NOT EXISTS address VARCHAR(500),
    ADD COLUMN IF NOT EXISTS locality VARCHAR(160),
    ADD COLUMN IF NOT EXISTS region VARCHAR(160),
    ADD COLUMN IF NOT EXISTS postcode VARCHAR(40),
    ADD COLUMN IF NOT EXISTS country_code VARCHAR(2),
    ADD COLUMN IF NOT EXISTS telephone VARCHAR(80),
    ADD COLUMN IF NOT EXISTS website VARCHAR(1000),
    ADD COLUMN IF NOT EXISTS email VARCHAR(320),
    ADD COLUMN IF NOT EXISTS social_identifiers JSON,
    ADD COLUMN IF NOT EXISTS source_date_created DATE,
    ADD COLUMN IF NOT EXISTS source_date_refreshed DATE,
    ADD COLUMN IF NOT EXISTS source_date_closed DATE,
    ADD COLUMN IF NOT EXISTS unresolved_flags JSON,
    ADD COLUMN IF NOT EXISTS imported_at TIMESTAMPTZ;

ALTER TABLE public.trips
    ADD COLUMN IF NOT EXISTS start_location_provider VARCHAR(50),
    ADD COLUMN IF NOT EXISTS start_location_provider_place_id VARCHAR(500);

-- Abort before any narrowing conversion if existing values violate model limits.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.trips
        WHERE length(start_location_type) > 30
           OR length(start_location_name) > 255
           OR length(start_location_provider) > 50
           OR length(start_location_provider_place_id) > 500
    ) THEN
        RAISE EXCEPTION 'trips contains a value longer than the current model limit';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.route_matrix_cache
        WHERE length(from_location_type) > 30
           OR length(from_name) > 255
           OR length(to_location_type) > 30
           OR length(to_name) > 255
           OR length(from_key) > 350
           OR length(to_key) > 350
           OR length(travel_mode) > 30
    ) THEN
        RAISE EXCEPTION 'route_matrix_cache contains a value longer than the current model limit';
    END IF;
END
$$;

-- Preserve known lifecycle timing for legacy source rows; only use the migration
-- transaction time when no earlier source timestamp exists.
UPDATE public.place_sources
SET licence_identifier = COALESCE(licence_identifier, 'unknown'),
    social_identifiers = COALESCE(social_identifiers, '{}'::json),
    unresolved_flags = COALESCE(unresolved_flags, '[]'::json),
    imported_at = COALESCE(imported_at, last_fetched_at, transaction_timestamp())
WHERE licence_identifier IS NULL
   OR social_identifiers IS NULL
   OR unresolved_flags IS NULL
   OR imported_at IS NULL;

ALTER TABLE public.place_sources
    ALTER COLUMN source_url TYPE VARCHAR(1000) USING source_url::VARCHAR(1000),
    ALTER COLUMN licence_identifier TYPE VARCHAR(120)
        USING licence_identifier::VARCHAR(120),
    ALTER COLUMN address TYPE VARCHAR(500) USING address::VARCHAR(500),
    ALTER COLUMN locality TYPE VARCHAR(160) USING locality::VARCHAR(160),
    ALTER COLUMN region TYPE VARCHAR(160) USING region::VARCHAR(160),
    ALTER COLUMN postcode TYPE VARCHAR(40) USING postcode::VARCHAR(40),
    ALTER COLUMN country_code TYPE VARCHAR(2) USING country_code::VARCHAR(2),
    ALTER COLUMN telephone TYPE VARCHAR(80) USING telephone::VARCHAR(80),
    ALTER COLUMN website TYPE VARCHAR(1000) USING website::VARCHAR(1000),
    ALTER COLUMN email TYPE VARCHAR(320) USING email::VARCHAR(320),
    ALTER COLUMN social_identifiers TYPE JSON USING social_identifiers::json,
    ALTER COLUMN source_date_created TYPE DATE USING source_date_created::date,
    ALTER COLUMN source_date_refreshed TYPE DATE USING source_date_refreshed::date,
    ALTER COLUMN source_date_closed TYPE DATE USING source_date_closed::date,
    ALTER COLUMN unresolved_flags TYPE JSON USING unresolved_flags::json,
    ALTER COLUMN imported_at TYPE TIMESTAMPTZ USING imported_at::timestamptz,
    ALTER COLUMN licence_identifier SET DEFAULT 'unknown',
    ALTER COLUMN social_identifiers SET DEFAULT '{}'::json,
    ALTER COLUMN unresolved_flags SET DEFAULT '[]'::json,
    ALTER COLUMN imported_at SET DEFAULT now(),
    ALTER COLUMN licence_identifier SET NOT NULL,
    ALTER COLUMN social_identifiers SET NOT NULL,
    ALTER COLUMN unresolved_flags SET NOT NULL,
    ALTER COLUMN imported_at SET NOT NULL;

ALTER TABLE public.trips
    ALTER COLUMN start_location_type TYPE VARCHAR(30)
        USING start_location_type::VARCHAR(30),
    ALTER COLUMN start_location_name TYPE VARCHAR(255)
        USING start_location_name::VARCHAR(255),
    ALTER COLUMN start_location_provider TYPE VARCHAR(50)
        USING start_location_provider::VARCHAR(50),
    ALTER COLUMN start_location_provider_place_id TYPE VARCHAR(500)
        USING start_location_provider_place_id::VARCHAR(500);

ALTER TABLE public.route_matrix_cache
    ALTER COLUMN from_location_type TYPE VARCHAR(30)
        USING from_location_type::VARCHAR(30),
    ALTER COLUMN from_name TYPE VARCHAR(255) USING from_name::VARCHAR(255),
    ALTER COLUMN to_location_type TYPE VARCHAR(30)
        USING to_location_type::VARCHAR(30),
    ALTER COLUMN to_name TYPE VARCHAR(255) USING to_name::VARCHAR(255),
    ALTER COLUMN from_key TYPE VARCHAR(350) USING from_key::VARCHAR(350),
    ALTER COLUMN to_key TYPE VARCHAR(350) USING to_key::VARCHAR(350),
    ALTER COLUMN travel_mode TYPE VARCHAR(30) USING travel_mode::VARCHAR(30),
    ALTER COLUMN travel_mode SET DEFAULT 'driving';

CREATE INDEX IF NOT EXISTS ix_place_sources_locality
    ON public.place_sources (locality);
CREATE INDEX IF NOT EXISTS ix_route_matrix_cache_from_key
    ON public.route_matrix_cache (from_key);
CREATE INDEX IF NOT EXISTS ix_route_matrix_cache_from_place_id
    ON public.route_matrix_cache (from_place_id);
CREATE INDEX IF NOT EXISTS ix_route_matrix_cache_to_key
    ON public.route_matrix_cache (to_key);
CREATE INDEX IF NOT EXISTS ix_route_matrix_cache_to_place_id
    ON public.route_matrix_cache (to_place_id);

-- The original route script created three anonymous inline checks. Preserve the
-- checks and only align their names with current SQLModel metadata.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.route_matrix_cache'::regclass
          AND conname = 'route_matrix_cache_distance_meters_check'
    ) AND NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.route_matrix_cache'::regclass
          AND conname = 'ck_route_matrix_distance'
    ) THEN
        ALTER TABLE public.route_matrix_cache
            RENAME CONSTRAINT route_matrix_cache_distance_meters_check
            TO ck_route_matrix_distance;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.route_matrix_cache'::regclass
          AND conname = 'route_matrix_cache_static_duration_seconds_check'
    ) AND NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.route_matrix_cache'::regclass
          AND conname = 'ck_route_matrix_static_duration'
    ) THEN
        ALTER TABLE public.route_matrix_cache
            RENAME CONSTRAINT route_matrix_cache_static_duration_seconds_check
            TO ck_route_matrix_static_duration;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.route_matrix_cache'::regclass
          AND conname = 'route_matrix_cache_traffic_duration_seconds_check'
    ) AND NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.route_matrix_cache'::regclass
          AND conname = 'ck_route_matrix_traffic_duration'
    ) THEN
        ALTER TABLE public.route_matrix_cache
            RENAME CONSTRAINT route_matrix_cache_traffic_duration_seconds_check
            TO ck_route_matrix_traffic_duration;
    END IF;
END
$$;

-- Promote the existing unique index to the model-declared table constraint.
CREATE UNIQUE INDEX IF NOT EXISTS uq_route_matrix_cache_trip_pair_mode
    ON public.route_matrix_cache (trip_id, from_key, to_key, travel_mode);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.route_matrix_cache'::regclass
          AND conname = 'uq_route_matrix_cache_trip_pair_mode'
          AND contype = 'u'
    ) THEN
        ALTER TABLE public.route_matrix_cache
            ADD CONSTRAINT uq_route_matrix_cache_trip_pair_mode
            UNIQUE USING INDEX uq_route_matrix_cache_trip_pair_mode;
    END IF;
END
$$;

COMMIT;
