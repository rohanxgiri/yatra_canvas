-- Reverses add_fsq_geoapify_foundation.sql.
-- Review data retention before running; this intentionally drops import metadata.

ALTER TABLE trips
    DROP COLUMN IF EXISTS start_location_provider_place_id,
    DROP COLUMN IF EXISTS start_location_provider;

DROP TABLE IF EXISTS place_import_reviews;
DROP TABLE IF EXISTS place_categories;

DROP INDEX IF EXISTS ix_place_sources_locality;

ALTER TABLE place_sources
    DROP COLUMN IF EXISTS imported_at,
    DROP COLUMN IF EXISTS unresolved_flags,
    DROP COLUMN IF EXISTS source_date_closed,
    DROP COLUMN IF EXISTS source_date_refreshed,
    DROP COLUMN IF EXISTS source_date_created,
    DROP COLUMN IF EXISTS social_identifiers,
    DROP COLUMN IF EXISTS email,
    DROP COLUMN IF EXISTS website,
    DROP COLUMN IF EXISTS telephone,
    DROP COLUMN IF EXISTS country_code,
    DROP COLUMN IF EXISTS postcode,
    DROP COLUMN IF EXISTS region,
    DROP COLUMN IF EXISTS locality,
    DROP COLUMN IF EXISTS address,
    DROP COLUMN IF EXISTS licence_identifier,
    DROP COLUMN IF EXISTS source_url;
