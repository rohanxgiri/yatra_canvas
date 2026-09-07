-- Rollback: Remove assignment_mode and assigned_day_id from user_saved_places.

BEGIN;

ALTER TABLE public.user_saved_places
    DROP CONSTRAINT IF EXISTS ck_user_saved_places_assignment_consistency,
    DROP CONSTRAINT IF EXISTS ck_user_saved_places_assignment_mode,
    DROP COLUMN IF EXISTS assigned_day_id,
    DROP COLUMN IF EXISTS assignment_mode;

DROP INDEX IF EXISTS public.ix_user_saved_places_assigned_day_id;

COMMIT;
