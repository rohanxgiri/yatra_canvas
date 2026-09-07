-- Rollback status column and check constraint on trip_itinerary

ALTER TABLE trip_itinerary
DROP CONSTRAINT IF EXISTS ck_trip_itinerary_status;

ALTER TABLE trip_itinerary
DROP COLUMN IF EXISTS status;
