-- Fixes: RLS policies on businesses ↔ business_members ↔ orders triggered
-- "infinite recursion detected in policy" because they cross-referenced each
-- other inline. Use SECURITY DEFINER helpers that bypass RLS.

CREATE OR REPLACE FUNCTION public.is_business_owner(p_business_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.businesses
    WHERE id = p_business_id AND owner_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.is_business_member(p_business_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.business_members
    WHERE business_id = p_business_id AND user_id = auth.uid()
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_business_owner(uuid), public.is_business_member(uuid) TO authenticated;

-- Rebuild the offending policies using the helpers.
DROP POLICY IF EXISTS businesses_member_select ON public.businesses;
CREATE POLICY businesses_member_select ON public.businesses
  FOR SELECT TO authenticated
  USING (
    owner_id = auth.uid()
    OR public.is_business_member(id)
    OR public.is_dispatcher()
  );

DROP POLICY IF EXISTS bmembers_select ON public.business_members;
CREATE POLICY bmembers_select ON public.business_members
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_business_owner(business_id)
    OR public.is_admin()
  );

DROP POLICY IF EXISTS bmembers_owner_write ON public.business_members;
CREATE POLICY bmembers_owner_write ON public.business_members
  FOR ALL TO authenticated
  USING (public.is_business_owner(business_id) OR public.is_admin())
  WITH CHECK (public.is_business_owner(business_id) OR public.is_admin());

DROP POLICY IF EXISTS orders_select ON public.orders;
CREATE POLICY orders_select ON public.orders
  FOR SELECT TO authenticated
  USING (
    public.is_dispatcher()
    OR assigned_rider_id = auth.uid()
    OR public.is_business_owner(business_id)
    OR public.is_business_member(business_id)
  );

DROP POLICY IF EXISTS orders_business_insert ON public.orders;
CREATE POLICY orders_business_insert ON public.orders
  FOR INSERT TO authenticated
  WITH CHECK (
    public.is_admin()
    OR public.is_business_owner(business_id)
    OR public.is_business_member(business_id)
  );

DROP POLICY IF EXISTS orders_update ON public.orders;
CREATE POLICY orders_update ON public.orders
  FOR UPDATE TO authenticated
  USING (
    public.is_dispatcher()
    OR assigned_rider_id = auth.uid()
    OR public.is_business_owner(business_id)
    OR public.is_business_member(business_id)
  )
  WITH CHECK (
    public.is_dispatcher()
    OR assigned_rider_id = auth.uid()
    OR public.is_business_owner(business_id)
    OR public.is_business_member(business_id)
  );

DROP POLICY IF EXISTS rider_loc_select ON public.rider_locations;
CREATE POLICY rider_loc_select ON public.rider_locations
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR public.is_dispatcher()
    OR EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.assigned_rider_id = rider_locations.rider_id
        AND public.is_business_member(o.business_id)
        AND o.status IN ('assigned','picked_up')
    )
  );

DROP POLICY IF EXISTS rider_hist_select ON public.rider_location_history;
CREATE POLICY rider_hist_select ON public.rider_location_history
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR public.is_dispatcher()
    OR (order_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = rider_location_history.order_id
        AND public.is_business_member(o.business_id)
    ))
  );
