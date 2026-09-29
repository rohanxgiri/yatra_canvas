-- Migration: align place_opening_hours with the application update path.
-- Existing rows keep their original created_at and receive updated_at=NOW().

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

ALTER TABLE public.place_opening_hours
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

COMMIT;
