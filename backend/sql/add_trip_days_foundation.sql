-- Migration: Add trip_days foundation table, constraints, and non-destructive backfill.
-- Non-destructive and idempotent for Supabase PostgreSQL.

BEGIN;

CREATE TABLE IF NOT EXISTS public.trip_days (
    id UUID PRIMARY KEY,
    trip_id UUID NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
    day_number INTEGER NOT NULL,
    date DATE NOT NULL,
    day_type VARCHAR(20) NOT NULL DEFAULT 'FULL_DAY',
    start_time TIME,
    end_time TIME,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_trip_days_day_number CHECK (day_number > 0),
    CONSTRAINT ck_trip_days_day_type CHECK (day_type IN ('FULL_DAY', 'HALF_DAY', 'REST', 'TRAVEL')),
    CONSTRAINT uq_trip_days_trip_day_number UNIQUE (trip_id, day_number)
);

CREATE INDEX IF NOT EXISTS ix_trip_days_trip_id ON public.trip_days (trip_id);
CREATE INDEX IF NOT EXISTS ix_trip_days_date ON public.trip_days (date);

-- Safe backfill strategy:
-- For all existing trips that have start_date and positive days,
-- backfill TripDay rows if the trip does not already have any TripDay rows.
DO $$
BEGIN
    INSERT INTO public.trip_days (id, trip_id, day_number, date, day_type, start_time, end_time, created_at)
    SELECT
        gen_random_uuid(),
        t.id,
        s.day_idx,
        (t.start_date + (s.day_idx - 1) * INTERVAL '1 day')::DATE,
        'FULL_DAY',
        '09:00:00'::TIME,
        '19:00:00'::TIME,
        NOW()
    FROM public.trips t
    CROSS JOIN LATERAL generate_series(1, t.days) AS s(day_idx)
    WHERE t.start_date IS NOT NULL
      AND t.days > 0
      AND NOT EXISTS (
          SELECT 1 FROM public.trip_days td WHERE td.trip_id = t.id
      );
END
$$;

COMMIT;
