-- Rollback migration: Drop place_opening_hours and revert opening_hours columns.

BEGIN;

DROP TABLE IF EXISTS public.place_opening_hours CASCADE;

ALTER TABLE public.places
    DROP CONSTRAINT IF EXISTS ck_places_opening_hours_status,
    DROP COLUMN IF EXISTS opening_hours_status,
    DROP COLUMN IF EXISTS raw_opening_hours;

ALTER TABLE public.place_sources
    DROP COLUMN IF EXISTS raw_opening_hours;

COMMIT;
