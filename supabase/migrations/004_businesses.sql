CREATE TABLE public.businesses (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  name         text NOT NULL,
  phone        text,
  address      text,
  location     geography(Point, 4326),
  is_active    boolean NOT NULL DEFAULT true,
  deleted_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.businesses ENABLE ROW LEVEL SECURITY;

CREATE TRIGGER businesses_set_updated_at
  BEFORE UPDATE ON public.businesses
  FOR EACH ROW EXECUTE FUNCTION moddatetime(updated_at);

CREATE TABLE public.business_members (
  business_id  uuid NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
  user_id      uuid NOT NULL REFERENCES auth.users(id)        ON DELETE CASCADE,
  role         public.business_role NOT NULL DEFAULT 'staff',
  created_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (business_id, user_id)
);

ALTER TABLE public.business_members ENABLE ROW LEVEL SECURITY;
