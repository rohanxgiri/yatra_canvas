-- Migration: Add importance_score column, check constraint, and index to places.
-- Non-destructive and idempotent for Supabase PostgreSQL.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'places' AND column_name = 'importance_score'
    ) THEN
        ALTER TABLE places ADD COLUMN importance_score FLOAT;
        ALTER TABLE places ADD CONSTRAINT ck_places_importance_score CHECK (importance_score IS NULL OR (importance_score BETWEEN 0 AND 1));
        CREATE INDEX IF NOT EXISTS ix_places_importance_score ON places (importance_score);
    END IF;
END
$$;
