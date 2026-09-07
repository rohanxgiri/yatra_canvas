-- Add status column and check constraint to trip_itinerary
-- Required states: PLANNED, COMPLETED, MISSED, SKIPPED
-- Default value: 'PLANNED'

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

ALTER TABLE public.trip_itinerary
ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'PLANNED';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.trip_itinerary'::regclass
          AND conname = 'ck_trip_itinerary_status'
    ) THEN
        ALTER TABLE public.trip_itinerary
        ADD CONSTRAINT ck_trip_itinerary_status
        CHECK (status IN ('PLANNED', 'COMPLETED', 'MISSED', 'SKIPPED'));
    END IF;
END $$;

COMMIT;
