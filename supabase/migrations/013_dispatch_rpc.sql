-- Scoring RPC for the dispatch-order edge function.
-- Returns candidate riders ordered by score (smaller = better).
-- score = distance_m * (1 + 0.25 * active_deliveries)
CREATE OR REPLACE FUNCTION public.la10_find_best_rider(p_order_id uuid, p_radius_m int DEFAULT 5000)
RETURNS TABLE(rider_id uuid, distance_m double precision, active integer, score numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH o AS (
    SELECT pickup_location FROM public.orders WHERE id = p_order_id
  ),
  active AS (
    SELECT assigned_rider_id AS rider_id, COUNT(*)::int AS n
    FROM public.orders
    WHERE status IN ('assigned','picked_up')
      AND assigned_rider_id IS NOT NULL
    GROUP BY assigned_rider_id
  )
  SELECT r.user_id AS rider_id,
         ST_Distance(rl.location, o.pickup_location)              AS distance_m,
         COALESCE(a.n, 0)                                          AS active,
         (ST_Distance(rl.location, o.pickup_location) * (1 + 0.25 * COALESCE(a.n,0)))::numeric AS score
  FROM public.riders r
  JOIN public.rider_locations rl ON rl.rider_id = r.user_id
  JOIN o ON ST_DWithin(rl.location, o.pickup_location, p_radius_m)
  LEFT JOIN active a ON a.rider_id = r.user_id
  WHERE r.is_active AND r.status = 'available'
  ORDER BY score ASC
  LIMIT 5;
$$;

GRANT EXECUTE ON FUNCTION public.la10_find_best_rider(uuid, int) TO authenticated, service_role;
