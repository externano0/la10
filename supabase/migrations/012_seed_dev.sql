-- DEV-ONLY SEED. Idempotent. Skip on prod by simply not running this migration there.
-- Note: requires that at least one auth.users row already exists (creates one if not via dashboard).

DO $$
DECLARE
  v_admin_uid uuid;
  v_business_id uuid;
BEGIN
  -- Pick first auth user (or no-op if none exist yet — seed manually after sign-up).
  SELECT id INTO v_admin_uid FROM auth.users ORDER BY created_at LIMIT 1;
  IF v_admin_uid IS NULL THEN
    RAISE NOTICE 'No auth.users; skipping seed.';
    RETURN;
  END IF;

  -- Promote to super_admin so we can exercise dispatcher flows.
  UPDATE public.profiles SET role = 'super_admin' WHERE user_id = v_admin_uid;

  -- One demo business.
  INSERT INTO public.businesses (owner_id, name, address, location)
  VALUES (v_admin_uid, 'Demo Pizzeria', 'Av. Corrientes 1000, CABA',
          ST_SetSRID(ST_MakePoint(-58.387, -34.603), 4326)::geography)
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_business_id;
END $$;
