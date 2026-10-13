-- Reviewed additive schema for integrated admin review overlays and audit history.
-- Run only through the controlled deployment process. No legacy rows are altered.
BEGIN;
CREATE TABLE IF NOT EXISTS admin_audit_events (
    id UUID PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL,
    admin_user_id UUID NOT NULL,
    action VARCHAR(80) NOT NULL,
    entity_type VARCHAR(40) NOT NULL,
    entity_id VARCHAR(200) NOT NULL,
    city_id VARCHAR(200),
    before JSON NOT NULL,
    after JSON NOT NULL,
    reason VARCHAR(1000) NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_admin_audit_events_timestamp ON admin_audit_events(timestamp);
CREATE INDEX IF NOT EXISTS ix_admin_audit_events_admin_user_id ON admin_audit_events(admin_user_id);
CREATE INDEX IF NOT EXISTS ix_admin_audit_events_action ON admin_audit_events(action);
CREATE INDEX IF NOT EXISTS ix_admin_audit_events_entity_type ON admin_audit_events(entity_type);
CREATE INDEX IF NOT EXISTS ix_admin_audit_events_entity_id ON admin_audit_events(entity_id);
CREATE INDEX IF NOT EXISTS ix_admin_audit_events_city_id ON admin_audit_events(city_id);
CREATE TABLE IF NOT EXISTS admin_reviews (
    id UUID PRIMARY KEY,
    release_key VARCHAR(200) NOT NULL,
    entity_type VARCHAR(40) NOT NULL,
    entity_id VARCHAR(200) NOT NULL,
    city_id VARCHAR(200) NOT NULL,
    base_fingerprint VARCHAR(128) NOT NULL,
    status VARCHAR(40) NOT NULL,
    changes JSON NOT NULL,
    base_values JSON NOT NULL,
    notes VARCHAR(4000) NOT NULL,
    evidence_url VARCHAR(1000),
    updated_by UUID NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT uq_admin_review_entity UNIQUE (release_key, entity_type, entity_id)
);
CREATE INDEX IF NOT EXISTS ix_admin_reviews_release_key ON admin_reviews(release_key);
CREATE INDEX IF NOT EXISTS ix_admin_reviews_city_id ON admin_reviews(city_id);
COMMIT;
