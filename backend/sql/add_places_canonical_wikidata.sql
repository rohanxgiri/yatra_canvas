-- Migration: Add wikidata_id column and indices to places and place_sources.
-- Non-destructive and idempotent for Supabase PostgreSQL.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'places' AND column_name = 'wikidata_id'
    ) THEN
        ALTER TABLE places ADD COLUMN wikidata_id VARCHAR(50);
        CREATE INDEX IF NOT EXISTS ix_places_wikidata_id ON places (wikidata_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'place_sources' AND column_name = 'wikidata_id'
    ) THEN
        ALTER TABLE place_sources ADD COLUMN wikidata_id VARCHAR(50);
        CREATE INDEX IF NOT EXISTS ix_place_sources_wikidata_id ON place_sources (wikidata_id);
    END IF;
END
$$;

-- Backfill existing Audiala place_sources where external_place_id is a Wikidata QID
UPDATE place_sources
SET wikidata_id = external_place_id
WHERE source = 'audiala'
  AND external_place_id ~ '^Q[0-9]+$'
  AND wikidata_id IS NULL;

-- Backfill places linked to Audiala sources where external_place_id is a Wikidata QID
UPDATE places p
SET wikidata_id = ps.external_place_id
FROM place_sources ps
WHERE ps.place_id = p.id
  AND ps.source = 'audiala'
  AND ps.external_place_id ~ '^Q[0-9]+$'
  AND p.wikidata_id IS NULL;
