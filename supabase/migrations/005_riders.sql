CREATE TABLE public.riders (
  user_id       uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name  text NOT NULL,
  phone         text,
  vehicle_type  text NOT NULL DEFAULT 'motorcycle',
  status        public.rider_status NOT NULL DEFAULT 'offline',
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.riders ENABLE ROW LEVEL SECURITY;

CREATE TRIGGER riders_set_updated_at
  BEFORE UPDATE ON public.riders
  FOR EACH ROW EXECUTE FUNCTION moddatetime(updated_at);
