CREATE TABLE public.orders (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id          uuid NOT NULL REFERENCES public.businesses(id) ON DELETE RESTRICT,
  customer_name        text NOT NULL,
  customer_phone       text,
  pickup_address       text NOT NULL,
  pickup_location      geography(Point, 4326) NOT NULL,
  dropoff_address      text NOT NULL,
  dropoff_location     geography(Point, 4326) NOT NULL,
  status               public.order_status NOT NULL DEFAULT 'draft',
  assigned_rider_id    uuid REFERENCES public.riders(user_id) ON DELETE SET NULL,
  assigned_at          timestamptz,
  picked_up_at         timestamptz,
  delivered_at         timestamptz,
  cancelled_at         timestamptz,
  cancel_reason        text,
  total_amount_cents   integer,
  currency             text NOT NULL DEFAULT 'ARS',
  notes                text,
  deleted_at           timestamptz,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

CREATE TRIGGER orders_set_updated_at
  BEFORE UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION moddatetime(updated_at);

CREATE TABLE public.order_events (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id        uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  event_type      text NOT NULL,
  from_status     public.order_status,
  to_status       public.order_status,
  actor_user_id   uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  payload         jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.order_events ENABLE ROW LEVEL SECURITY;

-- Append an order_events row whenever orders.status changes.
CREATE OR REPLACE FUNCTION public.log_order_status_change()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO public.order_events(order_id, event_type, from_status, to_status, actor_user_id)
    VALUES (NEW.id, 'status_change', OLD.status, NEW.status, auth.uid());
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER orders_log_status_change
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.log_order_status_change();
