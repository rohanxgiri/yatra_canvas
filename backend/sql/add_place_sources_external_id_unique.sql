-- Run once in Supabase SQL Editor before using place discovery in production.
-- This preserves existing rows and only adds the external-ID deduplication rule.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'uq_place_sources_source_external_place'
          AND conrelid = 'place_sources'::regclass
    ) THEN
        ALTER TABLE place_sources
        ADD CONSTRAINT uq_place_sources_source_external_place
        UNIQUE (source, external_place_id);
    END IF;
END
$$;
