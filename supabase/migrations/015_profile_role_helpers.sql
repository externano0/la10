-- Profile helpers + manual-assign support.

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS avatar_url text;

-- Ensures the current user has a `riders` row. Called when promoting to rider.
CREATE OR REPLACE FUNCTION public.ensure_rider_row(p_display_name text DEFAULT NULL)
RETURNS public.riders
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row public.riders%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'auth required';
  END IF;
  INSERT INTO public.riders(user_id, display_name)
  VALUES (v_uid, COALESCE(p_display_name, 'Rider'))
  ON CONFLICT (user_id) DO UPDATE
    SET display_name = COALESCE(EXCLUDED.display_name, public.riders.display_name)
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;
GRANT EXECUTE ON FUNCTION public.ensure_rider_row(text) TO authenticated;
