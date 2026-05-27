-- Extiende ensure_rider_row para aceptar el teléfono y guardarlo en la fila del rider.
-- Antes: solo display_name. Ahora: display_name + phone (ambos opcionales en la RPC,
-- pero el cliente los exige en signup).

DROP FUNCTION IF EXISTS public.ensure_rider_row(text);

CREATE OR REPLACE FUNCTION public.ensure_rider_row(
  p_display_name text DEFAULT NULL,
  p_phone        text DEFAULT NULL
)
RETURNS public.riders
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row public.riders%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'auth required';
  END IF;
  INSERT INTO public.riders(user_id, display_name, phone)
  VALUES (v_uid, COALESCE(p_display_name, 'Rider'), NULLIF(trim(p_phone), ''))
  ON CONFLICT (user_id) DO UPDATE
    SET display_name = COALESCE(EXCLUDED.display_name, public.riders.display_name),
        phone        = COALESCE(EXCLUDED.phone, public.riders.phone)
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.ensure_rider_row(text, text) TO authenticated;
