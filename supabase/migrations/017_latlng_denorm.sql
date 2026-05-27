-- Denormalized lat/lng on rider_locations + orders so we can stream them
-- via Supabase Realtime without a server-side WKB→lat/lng decode.
-- Triggers keep the columns in sync with the authoritative `geography` field.

ALTER TABLE public.rider_locations
  ADD COLUMN IF NOT EXISTS lat double precision,
  ADD COLUMN IF NOT EXISTS lng double precision;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS pickup_lat  double precision,
  ADD COLUMN IF NOT EXISTS pickup_lng  double precision,
  ADD COLUMN IF NOT EXISTS dropoff_lat double precision,
  ADD COLUMN IF NOT EXISTS dropoff_lng double precision;

CREATE OR REPLACE FUNCTION public.la10_rider_locations_set_latlng()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  NEW.lat := ST_Y(NEW.location::geometry);
  NEW.lng := ST_X(NEW.location::geometry);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_rider_locations_latlng ON public.rider_locations;
CREATE TRIGGER trg_rider_locations_latlng
  BEFORE INSERT OR UPDATE OF location ON public.rider_locations
  FOR EACH ROW EXECUTE FUNCTION public.la10_rider_locations_set_latlng();

CREATE OR REPLACE FUNCTION public.la10_orders_set_latlng()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.pickup_location IS NOT NULL THEN
    NEW.pickup_lat := ST_Y(NEW.pickup_location::geometry);
    NEW.pickup_lng := ST_X(NEW.pickup_location::geometry);
  END IF;
  IF NEW.dropoff_location IS NOT NULL THEN
    NEW.dropoff_lat := ST_Y(NEW.dropoff_location::geometry);
    NEW.dropoff_lng := ST_X(NEW.dropoff_location::geometry);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_latlng ON public.orders;
CREATE TRIGGER trg_orders_latlng
  BEFORE INSERT OR UPDATE OF pickup_location, dropoff_location ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.la10_orders_set_latlng();

-- Backfill existing rows.
UPDATE public.rider_locations
  SET lat = ST_Y(location::geometry),
      lng = ST_X(location::geometry)
  WHERE lat IS NULL OR lng IS NULL;

UPDATE public.orders
  SET pickup_lat  = ST_Y(pickup_location::geometry),
      pickup_lng  = ST_X(pickup_location::geometry),
      dropoff_lat = ST_Y(dropoff_location::geometry),
      dropoff_lng = ST_X(dropoff_location::geometry)
  WHERE pickup_lat IS NULL OR pickup_lng IS NULL OR dropoff_lat IS NULL OR dropoff_lng IS NULL;
