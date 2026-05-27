# Environment variables

All keys with origin and consumer. Public keys go through `--dart-define`; secrets stay in Supabase Function Secrets.

| Key | Origin | Used by | Notes |
|---|---|---|---|
| `SUPABASE_URL` | Supabase Dashboard | Flutter clients + edge functions | Public. |
| `SUPABASE_ANON_KEY` | Supabase Dashboard | Flutter clients | Public. |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase Dashboard | Edge functions only | **Never** in client builds. Set via `supabase secrets set`. |
| `OSRM_BASE_URL` | OSRM (self-hosted or public demo) | `packages/geo` | Default public demo is rate-limited; use self-hosted in prod. |
| `OSM_TILE_URL` | OpenStreetMap | `flutter_map` | Respect OSM tile usage policy. |
| `TWILIO_ACCOUNT_SID` | Twilio | Supabase Auth (phone) | Optional. Leave blank to disable phone OTP. |
| `TWILIO_AUTH_TOKEN` | Twilio | Supabase Auth | Optional. |
| `TWILIO_PHONE_FROM` | Twilio | Supabase Auth | Optional. |
| `RIDER_HEARTBEAT_MIN_INTERVAL_SEC` | App config | Mobile (rider) | Throttle floor between location upserts. Default 10. |
| `RIDER_HEARTBEAT_MAX_INTERVAL_SEC` | App config | Mobile (rider) | Force-send ceiling regardless of movement. Default 30. |
| `RIDER_HEARTBEAT_MIN_DISTANCE_M` | App config | Mobile (rider) | Min meters of movement to trigger send. Default 20. |
| `DISPATCH_OFFER_TTL_SEC` | App config | Edge fn `dispatch-order` | Default 30. |
| `DISPATCH_SEARCH_RADIUS_M` | App config | Edge fn `dispatch-order` | `ST_DWithin` radius. Default 5000. |
