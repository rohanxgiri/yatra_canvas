-- Destructive recovery helper for add_place_image_cache.sql.
-- This discards cached image URLs and attribution. Do not use as an install step.

BEGIN;
DROP TABLE IF EXISTS place_image_cache;
COMMIT;
