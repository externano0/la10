CREATE TABLE public.dispatch_offers (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id       uuid NOT NULL REFERENCES public.orders(id)         ON DELETE CASCADE,
  rider_id       uuid NOT NULL REFERENCES public.riders(user_id)    ON DELETE CASCADE,
  score          numeric NOT NULL,
  expires_at     timestamptz NOT NULL,
  response       public.offer_response NOT NULL DEFAULT 'pending',
  responded_at   timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.dispatch_offers ENABLE ROW LEVEL SECURITY;
