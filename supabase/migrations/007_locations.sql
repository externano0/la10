CREATE TABLE public.rider_locations (
  rider_id     uuid PRIMARY KEY REFERENCES public.riders(user_id) ON DELETE CASCADE,
  location     geography(Point, 4326) NOT NULL,
  heading      double precision,
  speed_ms     double precision,
  accuracy_m   double precision,
  recorded_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.rider_locations ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.rider_location_history (
  id           bigserial PRIMARY KEY,
  rider_id     uuid NOT NULL REFERENCES public.riders(user_id) ON DELETE CASCADE,
  order_id     uuid REFERENCES public.orders(id) ON DELETE SET NULL,
  location     geography(Point, 4326) NOT NULL,
  heading      double precision,
  speed_ms    double precision,
  accuracy_m   double precision,
  recorded_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.rider_location_history ENABLE ROW LEVEL SECURITY;
