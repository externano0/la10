-- Convenience: is the caller an admin / dispatcher?
CREATE OR REPLACE FUNCTION public.is_admin() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.current_role() = 'super_admin';
$$;
CREATE OR REPLACE FUNCTION public.is_dispatcher() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.current_role() IN ('dispatcher','super_admin');
$$;
GRANT EXECUTE ON FUNCTION public.is_admin(), public.is_dispatcher() TO authenticated;

-- =====================
-- profiles
-- =====================
CREATE POLICY profiles_self_select ON public.profiles
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

CREATE POLICY profiles_self_update ON public.profiles
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid() OR public.is_admin())
  WITH CHECK (user_id = auth.uid() OR public.is_admin());

-- =====================
-- businesses
-- =====================
CREATE POLICY businesses_member_select ON public.businesses
  FOR SELECT TO authenticated
  USING (
    owner_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.business_members bm WHERE bm.business_id = id AND bm.user_id = auth.uid())
    OR public.is_dispatcher()
  );

CREATE POLICY businesses_owner_insert ON public.businesses
  FOR INSERT TO authenticated WITH CHECK (owner_id = auth.uid());

CREATE POLICY businesses_owner_update ON public.businesses
  FOR UPDATE TO authenticated
  USING (owner_id = auth.uid() OR public.is_admin())
  WITH CHECK (owner_id = auth.uid() OR public.is_admin());

CREATE POLICY businesses_admin_delete ON public.businesses
  FOR DELETE TO authenticated USING (public.is_admin());

-- =====================
-- business_members
-- =====================
CREATE POLICY bmembers_select ON public.business_members
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.businesses b WHERE b.id = business_id AND b.owner_id = auth.uid())
    OR public.is_admin()
  );

CREATE POLICY bmembers_owner_write ON public.business_members
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.businesses b WHERE b.id = business_id AND b.owner_id = auth.uid()) OR public.is_admin())
  WITH CHECK (EXISTS (SELECT 1 FROM public.businesses b WHERE b.id = business_id AND b.owner_id = auth.uid()) OR public.is_admin());

-- =====================
-- riders
-- =====================
CREATE POLICY riders_self_select ON public.riders
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_dispatcher());

CREATE POLICY riders_self_update ON public.riders
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid() OR public.is_admin())
  WITH CHECK (user_id = auth.uid() OR public.is_admin());

CREATE POLICY riders_self_insert ON public.riders
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid() OR public.is_admin());

-- =====================
-- rider_locations
-- =====================
CREATE POLICY rider_loc_select ON public.rider_locations
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR public.is_dispatcher()
    OR EXISTS (
      SELECT 1 FROM public.orders o
      JOIN public.business_members bm ON bm.business_id = o.business_id
      WHERE o.assigned_rider_id = rider_locations.rider_id
        AND bm.user_id = auth.uid()
        AND o.status IN ('assigned','picked_up')
    )
  );

CREATE POLICY rider_loc_self_write ON public.rider_locations
  FOR ALL TO authenticated
  USING (rider_id = auth.uid())
  WITH CHECK (rider_id = auth.uid());

-- =====================
-- rider_location_history
-- =====================
CREATE POLICY rider_hist_self_insert ON public.rider_location_history
  FOR INSERT TO authenticated WITH CHECK (rider_id = auth.uid());

CREATE POLICY rider_hist_select ON public.rider_location_history
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR public.is_dispatcher()
    OR EXISTS (
      SELECT 1 FROM public.orders o
      JOIN public.business_members bm ON bm.business_id = o.business_id
      WHERE o.id = rider_location_history.order_id AND bm.user_id = auth.uid()
    )
  );

-- =====================
-- orders
-- =====================
CREATE POLICY orders_select ON public.orders
  FOR SELECT TO authenticated
  USING (
    public.is_dispatcher()
    OR assigned_rider_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.business_members bm WHERE bm.business_id = orders.business_id AND bm.user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.businesses b WHERE b.id = orders.business_id AND b.owner_id = auth.uid())
  );

CREATE POLICY orders_business_insert ON public.orders
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.business_members bm WHERE bm.business_id = orders.business_id AND bm.user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.businesses b WHERE b.id = orders.business_id AND b.owner_id = auth.uid())
    OR public.is_admin()
  );

CREATE POLICY orders_update ON public.orders
  FOR UPDATE TO authenticated
  USING (
    public.is_dispatcher()
    OR assigned_rider_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.business_members bm WHERE bm.business_id = orders.business_id AND bm.user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.businesses b WHERE b.id = orders.business_id AND b.owner_id = auth.uid())
  )
  WITH CHECK (
    public.is_dispatcher()
    OR assigned_rider_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.business_members bm WHERE bm.business_id = orders.business_id AND bm.user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.businesses b WHERE b.id = orders.business_id AND b.owner_id = auth.uid())
  );

-- =====================
-- order_events
-- =====================
CREATE POLICY order_events_select ON public.order_events
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.orders o WHERE o.id = order_events.order_id));
-- inserts come from the status-change trigger (runs as table owner) or edge fns (service role).

-- =====================
-- dispatch_offers
-- =====================
CREATE POLICY offers_select ON public.dispatch_offers
  FOR SELECT TO authenticated
  USING (rider_id = auth.uid() OR public.is_dispatcher());

CREATE POLICY offers_rider_update_response ON public.dispatch_offers
  FOR UPDATE TO authenticated
  USING (rider_id = auth.uid() AND response = 'pending')
  WITH CHECK (rider_id = auth.uid() AND response IN ('accepted','declined'));
-- inserts only from edge fns (service role).
