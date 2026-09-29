-- Rollback removes the new uniqueness/provenance structures only.
-- Consolidated duplicate cities cannot be recreated safely. Restore a reviewed
-- backup if reversal of that data repair is required.

BEGIN;

DROP INDEX IF EXISTS public.uq_cities_normalized_identity;
DROP TABLE IF EXISTS public.city_sources;

COMMIT;
