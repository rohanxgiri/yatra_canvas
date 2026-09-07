-- Migration: Add assignment_mode and assigned_day_id to user_saved_places.
-- Non-destructive and idempotent for Supabase PostgreSQL.

BEGIN;

ALTER TABLE public.user_saved_places
    ADD COLUMN IF NOT EXISTS assignment_mode VARCHAR(20) NOT NULL DEFAULT 'AUTO',
    ADD COLUMN IF NOT EXISTS assigned_day_id UUID REFERENCES public.trip_days(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS ix_user_saved_places_assigned_day_id
    ON public.user_saved_places (assigned_day_id);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_user_saved_places_assignment_mode'
    ) THEN
        ALTER TABLE public.user_saved_places
            ADD CONSTRAINT ck_user_saved_places_assignment_mode
            CHECK (assignment_mode IN ('AUTO', 'LOCKED'));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_user_saved_places_assignment_consistency'
    ) THEN
        ALTER TABLE public.user_saved_places
            ADD CONSTRAINT ck_user_saved_places_assignment_consistency
            CHECK (
                (assignment_mode = 'AUTO' AND assigned_day_id IS NULL) OR
                (assignment_mode = 'LOCKED' AND assigned_day_id IS NOT NULL)
            );
    END IF;
END
$$;

COMMIT;
