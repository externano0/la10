# Security

## Roles

- `super_admin` — full access.
- `business_owner` — owns one or more businesses (via `business_members`).
- `dispatcher` — assigns orders, monitors riders.
- `rider` — sees own offers/orders and pushes own location.

Role is stored in `profiles.role` and read via the `public.current_role()` SECURITY DEFINER helper.

## RLS summary

| Table | Select | Insert | Update | Delete |
|---|---|---|---|---|
| profiles | self + admins | trigger only | self + admin | admin |
| businesses | members + dispatchers + admin | owner | owner + admin | admin (soft) |
| business_members | members + admin | owner + admin | owner + admin | owner + admin |
| riders | self + dispatcher + admin | trigger | self + admin | admin |
| rider_locations | self + dispatcher + assigned business | self via RPC | self via RPC | none |
| rider_location_history | self + dispatcher + assigned business | self | none | admin |
| orders | business members + dispatcher + assigned rider + admin | business members | business members + dispatcher + rider (constrained) | admin (soft) |
| order_events | mirrors orders | trigger / service role | none | none |
| dispatch_offers | target rider + dispatcher + admin | service role only | service role + target rider (response) | none |

## Key handling

- Anon key — bundled in Flutter clients (public).
- Service-role key — Supabase Function Secrets only. Never in client builds, never committed.
- `.env` is gitignored. CI/CD secrets via Supabase Dashboard or platform vaults.

## Auth

- Email/password mandatory.
- Phone OTP optional (Twilio); disabled when Twilio env vars are empty.
- All RLS policies require `auth.uid()`; no `using (true)` policies in production migrations.

## Transport

- All Supabase traffic is TLS.
- Edge functions reject unauthenticated requests (`verify_jwt: true`) except cron-internal ones.
