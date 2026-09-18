-- [IMPLEMENTED] Durable provider-neutral place image cache.
-- Review and run manually in a transaction on a verified non-production target first.

BEGIN;

CREATE TABLE IF NOT EXISTS place_image_cache (
    id UUID PRIMARY KEY,
    place_id UUID NOT NULL REFERENCES places(id) ON DELETE CASCADE,
    provider_place_id VARCHAR(255),
    normalized_category VARCHAR(40) NOT NULL,
    url VARCHAR(2000),
    thumbnail_url VARCHAR(2000),
    provider VARCHAR(40),
    source_url VARCHAR(2000),
    attribution VARCHAR(1000),
    author VARCHAR(500),
    license VARCHAR(160),
    license_url VARCHAR(1000),
    status VARCHAR(20) NOT NULL,
    fetched_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    failure_reason VARCHAR(500),
    CONSTRAINT uq_place_image_cache_place_id UNIQUE (place_id),
    CONSTRAINT ck_place_image_cache_status
        CHECK (status IN ('resolved', 'not_found', 'failed')),
    CONSTRAINT ck_place_image_cache_provider
        CHECK (provider IN ('geoapify', 'wikimedia', 'foursquare') OR provider IS NULL)
);

CREATE INDEX IF NOT EXISTS ix_place_image_cache_place_id ON place_image_cache(place_id);
CREATE INDEX IF NOT EXISTS ix_place_image_cache_provider_place_id ON place_image_cache(provider_place_id);
CREATE INDEX IF NOT EXISTS ix_place_image_cache_normalized_category ON place_image_cache(normalized_category);
CREATE INDEX IF NOT EXISTS ix_place_image_cache_provider ON place_image_cache(provider);
CREATE INDEX IF NOT EXISTS ix_place_image_cache_status ON place_image_cache(status);
CREATE INDEX IF NOT EXISTS ix_place_image_cache_expires_at ON place_image_cache(expires_at);

COMMIT;
