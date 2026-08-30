-- Run once in the Supabase SQL Editor for an existing YatraCanvas database.
-- The constraint prevents duplicate cities during concurrent resolve requests.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'uq_cities_google_place_id'
          AND conrelid = 'public.cities'::regclass
    ) THEN
        ALTER TABLE public.cities
            ADD CONSTRAINT uq_cities_google_place_id UNIQUE (google_place_id);
    END IF;
END
$$;
