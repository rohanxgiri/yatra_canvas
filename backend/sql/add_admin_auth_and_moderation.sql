-- Add users, admin role authorization, destination management, POI moderation, and place reports.

BEGIN;

-- 1. Create users table
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY,
    email VARCHAR(255) NOT NULL,
    name VARCHAR(120) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'USER',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_users_role CHECK (role IN ('USER', 'ADMIN'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_users_email ON users(email);
CREATE INDEX IF NOT EXISTS ix_users_role ON users(role);

-- 2. Add destination management columns to cities
ALTER TABLE cities
    ADD COLUMN IF NOT EXISTS is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS is_featured BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS is_popular BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS image_url VARCHAR(1000) NULL,
    ADD COLUMN IF NOT EXISTS description VARCHAR(1000) NULL,
    ADD COLUMN IF NOT EXISTS display_order INTEGER NOT NULL DEFAULT 0;

-- 3. Add moderation_status to places
ALTER TABLE places
    ADD COLUMN IF NOT EXISTS moderation_status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_places_moderation_status'
    ) THEN
        ALTER TABLE places
            ADD CONSTRAINT ck_places_moderation_status
            CHECK (moderation_status IN ('ACTIVE', 'HIDDEN', 'RESTRICTED', 'DUPLICATE', 'INVALID'));
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS ix_places_moderation_status ON places(moderation_status);

-- 4. Create place_reports table
CREATE TABLE IF NOT EXISTS place_reports (
    id UUID PRIMARY KEY,
    place_id UUID NOT NULL REFERENCES places(id) ON DELETE CASCADE,
    user_id UUID NULL,
    reason VARCHAR(100) NOT NULL,
    details VARCHAR(1000) NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'OPEN',
    admin_notes VARCHAR(1000) NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_place_reports_status CHECK (status IN ('OPEN', 'REVIEWING', 'RESOLVED', 'REJECTED'))
);

CREATE INDEX IF NOT EXISTS ix_place_reports_place_id ON place_reports(place_id);
CREATE INDEX IF NOT EXISTS ix_place_reports_user_id ON place_reports(user_id);
CREATE INDEX IF NOT EXISTS ix_place_reports_status ON place_reports(status);

COMMIT;
