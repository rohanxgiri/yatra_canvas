-- Data preserving rollback. Stop writes and review a backup first.
-- Keep every audit/review row in archive tables. Restore by renaming them back
-- after removing any newly created empty replacement tables under review.
-- Fail rather than overwrite an existing archive from a previous rollback.
BEGIN;
DROP INDEX IF EXISTS ix_admin_reviews_release_key;
DROP INDEX IF EXISTS ix_admin_reviews_city_id;
DROP INDEX IF EXISTS ix_admin_audit_events_timestamp;
DROP INDEX IF EXISTS ix_admin_audit_events_admin_user_id;
DROP INDEX IF EXISTS ix_admin_audit_events_action;
DROP INDEX IF EXISTS ix_admin_audit_events_entity_type;
DROP INDEX IF EXISTS ix_admin_audit_events_entity_id;
DROP INDEX IF EXISTS ix_admin_audit_events_city_id;
ALTER TABLE admin_reviews RENAME TO admin_reviews_archive;
ALTER TABLE admin_audit_events RENAME TO admin_audit_events_archive;
COMMIT;
