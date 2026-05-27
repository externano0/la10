-- Realtime UPDATE events only carry the primary key by default.
-- For map markers to update live (lat/lng, status), we need FULL row payloads.
-- Trade-off: WAL volume grows. Acceptable for our table sizes.

ALTER TABLE public.rider_locations REPLICA IDENTITY FULL;
ALTER TABLE public.riders           REPLICA IDENTITY FULL;
ALTER TABLE public.orders           REPLICA IDENTITY FULL;
ALTER TABLE public.dispatch_offers  REPLICA IDENTITY FULL;

-- Add riders to the realtime publication so the map can react to status changes.
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.riders;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
