-- Destructive recovery helper for add_place_refresh_jobs.sql.
-- This discards refresh job history only. It never removes canonical POIs or cache rows.

BEGIN;
DROP TABLE IF EXISTS place_refresh_jobs;
COMMIT;
