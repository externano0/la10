-- El rider necesita poder leer la orden mientras le está siendo ofrecida
-- (pickup, dropoff, monto), no recién cuando la acepta. Sin esto el popup
-- muestra "No se pudo cargar el pedido".

DROP POLICY IF EXISTS orders_select ON public.orders;
CREATE POLICY orders_select ON public.orders
  FOR SELECT TO authenticated
  USING (
    public.is_dispatcher()
    OR assigned_rider_id = auth.uid()
    OR public.is_business_owner(business_id)
    OR public.is_business_member(business_id)
    -- NUEVO: el rider ve la orden si hay una oferta pendiente para él.
    OR EXISTS (
      SELECT 1 FROM public.dispatch_offers d
      WHERE d.order_id = orders.id
        AND d.rider_id = auth.uid()
        AND d.response = 'pending'
        AND d.expires_at > now()
    )
  );
