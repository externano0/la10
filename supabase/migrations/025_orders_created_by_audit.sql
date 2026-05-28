-- Agrega columna `created_by` a orders para auditar quién creó cada orden.
-- Default `auth.uid()` la setea automáticamente en cada INSERT del cliente.
-- También refuerza la policy de INSERT para fallar explícito si la sesión
-- es anónima (auth.uid() IS NULL) — antes el OR de las funciones helper
-- también devolvía false en ese caso pero el mensaje era confuso.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL;

-- Default que dispara cuando el cliente no manda el campo.
ALTER TABLE public.orders
  ALTER COLUMN created_by SET DEFAULT auth.uid();

-- Recreamos la policy de INSERT siendo más explícitos para que falle más
-- temprano si la sesión está rota.
DROP POLICY IF EXISTS orders_business_insert ON public.orders;
CREATE POLICY orders_business_insert ON public.orders
  FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() IS NOT NULL AND (
      public.is_admin()
      OR public.is_dispatcher()
      OR public.is_business_owner(business_id)
      OR public.is_business_member(business_id)
    )
  );

-- También permitimos que el creador vea sus propias órdenes.
DROP POLICY IF EXISTS orders_select ON public.orders;
CREATE POLICY orders_select ON public.orders
  FOR SELECT
  TO authenticated
  USING (
    public.is_dispatcher()
    OR (assigned_rider_id = auth.uid())
    OR public.is_business_owner(business_id)
    OR public.is_business_member(business_id)
    OR (created_by = auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.dispatch_offers d
      WHERE d.order_id = orders.id
        AND d.rider_id = auth.uid()
        AND d.response = 'pending'::offer_response
        AND d.expires_at > now()
    )
  );
