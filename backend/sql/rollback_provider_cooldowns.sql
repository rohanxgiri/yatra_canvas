-- Destructive recovery helper for add_provider_cooldowns.sql.
-- This discards provider backoff history only; image and POI cache rows are unchanged.

BEGIN;
DROP TABLE IF EXISTS provider_cooldowns;
COMMIT;
