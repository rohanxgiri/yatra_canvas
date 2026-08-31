-- YatraCanvas FSQ OS Places provenance and Geoapify selection foundation.
-- Apply only through the project's reviewed database-change process.
-- The matching rollback is rollback_fsq_geoapify_foundation.sql.

ALTER TABLE place_sources
    ADD COLUMN IF NOT EXISTS source_url VARCHAR(1000),
    ADD COLUMN IF NOT EXISTS licence_identifier VARCHAR(120) NOT NULL DEFAULT 'unknown',
    ADD COLUMN IF NOT EXISTS address VARCHAR(500),
    ADD COLUMN IF NOT EXISTS locality VARCHAR(160),
    ADD COLUMN IF NOT EXISTS region VARCHAR(160),
    ADD COLUMN IF NOT EXISTS postcode VARCHAR(40),
    ADD COLUMN IF NOT EXISTS country_code VARCHAR(2),
    ADD COLUMN IF NOT EXISTS telephone VARCHAR(80),
    ADD COLUMN IF NOT EXISTS website VARCHAR(1000),
    ADD COLUMN IF NOT EXISTS email VARCHAR(320),
    ADD COLUMN IF NOT EXISTS social_identifiers JSONB NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS source_date_created DATE,
    ADD COLUMN IF NOT EXISTS source_date_refreshed DATE,
    ADD COLUMN IF NOT EXISTS source_date_closed DATE,
    ADD COLUMN IF NOT EXISTS unresolved_flags JSONB NOT NULL DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS imported_at TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS ix_place_sources_locality ON place_sources (locality);

CREATE TABLE IF NOT EXISTS place_categories (
    id UUID PRIMARY KEY,
    place_id UUID NOT NULL REFERENCES places(id),
    source VARCHAR(50) NOT NULL,
    external_category_id VARCHAR(255) NOT NULL,
    label VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_place_categories_place_source_external
        UNIQUE (place_id, source, external_category_id)
);

CREATE INDEX IF NOT EXISTS ix_place_categories_place_id ON place_categories (place_id);
CREATE INDEX IF NOT EXISTS ix_place_categories_source ON place_categories (source);
CREATE INDEX IF NOT EXISTS ix_place_categories_external_category_id
    ON place_categories (external_category_id);
CREATE INDEX IF NOT EXISTS ix_place_categories_label ON place_categories (label);

CREATE TABLE IF NOT EXISTS place_import_reviews (
    id UUID PRIMARY KEY,
    city_id UUID NOT NULL REFERENCES cities(id),
    provider VARCHAR(50) NOT NULL,
    external_place_id VARCHAR(255) NOT NULL,
    reason VARCHAR(255) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    candidate_place_ids JSONB NOT NULL DEFAULT '[]'::jsonb,
    match_details JSONB NOT NULL DEFAULT '{}'::jsonb,
    source_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT uq_place_import_reviews_provider_external
        UNIQUE (provider, external_place_id),
    CONSTRAINT ck_place_import_reviews_status
        CHECK (status IN ('pending', 'resolved', 'ignored'))
);

CREATE INDEX IF NOT EXISTS ix_place_import_reviews_city_id ON place_import_reviews (city_id);
CREATE INDEX IF NOT EXISTS ix_place_import_reviews_provider ON place_import_reviews (provider);
CREATE INDEX IF NOT EXISTS ix_place_import_reviews_external_place_id
    ON place_import_reviews (external_place_id);
CREATE INDEX IF NOT EXISTS ix_place_import_reviews_status ON place_import_reviews (status);

ALTER TABLE trips
    ADD COLUMN IF NOT EXISTS start_location_provider VARCHAR(50),
    ADD COLUMN IF NOT EXISTS start_location_provider_place_id VARCHAR(500);
