-- [IMPLEMENTED] Durable per-city/versioned-category refresh coordination.
-- Review and run manually in a transaction on a verified non-production target first.

BEGIN;

CREATE TABLE IF NOT EXISTS place_refresh_jobs (
    id UUID PRIMARY KEY,
    city_id UUID NOT NULL REFERENCES cities(id),
    versioned_category VARCHAR(80) NOT NULL,
    state VARCHAR(20) NOT NULL DEFAULT 'queued',
    lease_owner VARCHAR(160),
    lease_expires_at TIMESTAMPTZ,
    last_started_at TIMESTAMPTZ,
    last_completed_at TIMESTAMPTZ,
    last_error VARCHAR(160),
    attempt_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_place_refresh_jobs_city_category
        UNIQUE (city_id, versioned_category),
    CONSTRAINT ck_place_refresh_jobs_state
        CHECK (state IN ('queued', 'running', 'completed', 'failed')),
    CONSTRAINT ck_place_refresh_jobs_attempt_count
        CHECK (attempt_count >= 0)
);

CREATE INDEX IF NOT EXISTS ix_place_refresh_jobs_city_id
    ON place_refresh_jobs(city_id);
CREATE INDEX IF NOT EXISTS ix_place_refresh_jobs_versioned_category
    ON place_refresh_jobs(versioned_category);
CREATE INDEX IF NOT EXISTS ix_place_refresh_jobs_state
    ON place_refresh_jobs(state);
CREATE INDEX IF NOT EXISTS ix_place_refresh_jobs_lease_owner
    ON place_refresh_jobs(lease_owner);
CREATE INDEX IF NOT EXISTS ix_place_refresh_jobs_lease_expires_at
    ON place_refresh_jobs(lease_expires_at);

COMMIT;
