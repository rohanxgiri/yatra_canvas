-- Migration: Add place_opening_hours table and opening_hours columns to places and place_sources.
-- Non-destructive and idempotent for Supabase PostgreSQL.

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

-- 1. Add opening_hours columns to places
ALTER TABLE public.places
    ADD COLUMN IF NOT EXISTS opening_hours_status VARCHAR(20) NOT NULL DEFAULT 'UNKNOWN',
    ADD COLUMN IF NOT EXISTS raw_opening_hours VARCHAR(1000);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.places'::regclass
          AND conname = 'ck_places_opening_hours_status'
    ) THEN
        ALTER TABLE public.places
            ADD CONSTRAINT ck_places_opening_hours_status
            CHECK (opening_hours_status IN ('KNOWN', 'CLOSED', 'UNKNOWN'));
    END IF;
END
$$;

-- 2. Add raw_opening_hours to place_sources for provider provenance
ALTER TABLE public.place_sources
    ADD COLUMN IF NOT EXISTS raw_opening_hours VARCHAR(1000);

-- 3. Create place_opening_hours table for normalized daily intervals
CREATE TABLE IF NOT EXISTS public.place_opening_hours (
    id UUID PRIMARY KEY,
    place_id UUID NOT NULL REFERENCES public.places(id) ON DELETE CASCADE,
    day_of_week INTEGER NOT NULL, -- 0=Monday, 6=Sunday
    status VARCHAR(20) NOT NULL DEFAULT 'UNKNOWN',
    intervals JSON NOT NULL DEFAULT '[]'::json,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_place_opening_hours_day CHECK (day_of_week BETWEEN 0 AND 6),
    CONSTRAINT ck_place_opening_hours_status CHECK (status IN ('KNOWN', 'CLOSED', 'UNKNOWN')),
    CONSTRAINT uq_place_opening_hours_place_day UNIQUE (place_id, day_of_week)
);

CREATE INDEX IF NOT EXISTS ix_place_opening_hours_place_id ON public.place_opening_hours (place_id);
CREATE INDEX IF NOT EXISTS ix_place_opening_hours_day_of_week ON public.place_opening_hours (day_of_week);

-- CREATE TABLE IF NOT EXISTS does not repair an older SQLModel-created foreign key.
-- Align the dependent schedule lifecycle with the current data-model contract.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.place_opening_hours'::regclass
          AND confrelid = 'public.places'::regclass
          AND contype = 'f'
          AND confdeltype = 'c'
    ) THEN
        ALTER TABLE public.place_opening_hours
            DROP CONSTRAINT IF EXISTS place_opening_hours_place_id_fkey;
        ALTER TABLE public.place_opening_hours
            ADD CONSTRAINT place_opening_hours_place_id_fkey
            FOREIGN KEY (place_id) REFERENCES public.places(id) ON DELETE CASCADE;
    END IF;
END
$$;

COMMIT;
