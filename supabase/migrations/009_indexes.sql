-- Geo indexes
CREATE INDEX idx_businesses_location           ON public.businesses           USING GIST (location);
CREATE INDEX idx_orders_pickup_location        ON public.orders               USING GIST (pickup_location);
CREATE INDEX idx_orders_dropoff_location       ON public.orders               USING GIST (dropoff_location);
CREATE INDEX idx_rider_locations_location      ON public.rider_locations      USING GIST (location);
CREATE INDEX idx_rider_loc_hist_location       ON public.rider_location_history USING GIST (location);

-- Order routing
CREATE INDEX idx_orders_status_business        ON public.orders (status, business_id);
CREATE INDEX idx_orders_rider_status           ON public.orders (assigned_rider_id, status);
CREATE INDEX idx_orders_created_at             ON public.orders (created_at DESC);

-- Dispatch offers
CREATE INDEX idx_offers_rider_response_expiry  ON public.dispatch_offers (rider_id, response, expires_at);
CREATE INDEX idx_offers_order                  ON public.dispatch_offers (order_id);

-- Order events timeline
CREATE INDEX idx_order_events_order_created    ON public.order_events (order_id, created_at);

-- Rider history time-window
CREATE INDEX idx_rider_loc_hist_rider_time     ON public.rider_location_history (rider_id, recorded_at DESC);

-- Business members lookup
CREATE INDEX idx_business_members_user         ON public.business_members (user_id);

-- Riders by status (used heavily by dispatcher console)
CREATE INDEX idx_riders_status                 ON public.riders (status) WHERE is_active;
