-- Destructive metadata rollback. Normalized schedules remain intact.

BEGIN;

ALTER TABLE public.place_opening_hours
    DROP COLUMN IF EXISTS updated_at;

COMMIT;
