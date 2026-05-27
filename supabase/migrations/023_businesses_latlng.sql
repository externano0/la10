-- Lat/lng denormalizados en businesses + trigger que los mantiene en sync
-- con la columna geography.location. El comercio carga su dirección UNA VEZ
-- al registrar el negocio y todas las órdenes la usan como pickup default.

ALTER TABLE public.businesses
  ADD COLUMN IF NOT EXISTS lat double precision,
  ADD COLUMN IF NOT EXISTS lng double precision;

CREATE OR REPLACE FUNCTION public.la10_businesses_set_latlng()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.location IS NOT NULL THEN
    NEW.lat := ST_Y(NEW.location::geometry);
    NEW.lng := ST_X(NEW.location::geometry);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_businesses_latlng ON public.businesses;
CREATE TRIGGER trg_businesses_latlng
  BEFORE INSERT OR UPDATE OF location ON public.businesses
  FOR EACH ROW EXECUTE FUNCTION public.la10_businesses_set_latlng();

UPDATE public.businesses
  SET lat = ST_Y(location::geometry),
      lng = ST_X(location::geometry)
  WHERE location IS NOT NULL AND (lat IS NULL OR lng IS NULL);
