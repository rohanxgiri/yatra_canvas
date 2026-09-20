-- [IMPLEMENTED] Shared provider cooldown state for Wikimedia 429 handling.
-- Review and run manually in a transaction on a verified non-production target first.

BEGIN;

CREATE TABLE IF NOT EXISTS provider_cooldowns (
    provider_key VARCHAR(80) PRIMARY KEY,
    host VARCHAR(255) NOT NULL,
    cooldown_until TIMESTAMPTZ NOT NULL,
    reason VARCHAR(80),
    retry_after_seconds INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_provider_cooldowns_retry_after_seconds
        CHECK (retry_after_seconds IS NULL OR retry_after_seconds >= 0)
);

CREATE INDEX IF NOT EXISTS ix_provider_cooldowns_host
    ON provider_cooldowns(host);
CREATE INDEX IF NOT EXISTS ix_provider_cooldowns_cooldown_until
    ON provider_cooldowns(cooldown_until);

COMMIT;
