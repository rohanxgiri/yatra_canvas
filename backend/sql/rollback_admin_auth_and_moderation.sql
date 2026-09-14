-- Rollback for add_admin_auth_and_moderation.sql
-- CAUTION: Drops place_reports, users, and removes admin destination/moderation columns.

BEGIN;

DROP TABLE IF EXISTS place_reports CASCADE;

DROP INDEX IF EXISTS ix_places_moderation_status;
ALTER TABLE places DROP CONSTRAINT IF EXISTS ck_places_moderation_status;
ALTER TABLE places DROP COLUMN IF EXISTS moderation_status;

ALTER TABLE cities
    DROP COLUMN IF EXISTS is_enabled,
    DROP COLUMN IF EXISTS is_featured,
    DROP COLUMN IF EXISTS is_popular,
    DROP COLUMN IF EXISTS image_url,
    DROP COLUMN IF EXISTS description,
    DROP COLUMN IF EXISTS display_order;

DROP TABLE IF EXISTS users CASCADE;

COMMIT;
