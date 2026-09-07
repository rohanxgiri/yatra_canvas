-- Rollback: Remove trip_days foundation table.
-- WARNING: Drops configured trip days. Use only during recovery or rollback.

BEGIN;

DROP TABLE IF EXISTS public.trip_days CASCADE;

COMMIT;
