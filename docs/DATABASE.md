# Database

Postgres on Supabase. PostGIS for geo, `pgcrypto` for UUIDs, `moddatetime` for `updated_at` triggers, `pg_cron` for scheduled jobs.

## Tables (Phase 1)

| Table | Purpose |
|---|---|
| `profiles` | One row per `auth.users`. Holds `role` and contact info. |
| `businesses` | Restaurants/shops with pickup `location` (PostGIS). |
| `business_members` | Multi-user access to a business (`owner`/`manager`/`staff`). |
| `riders` | Rider profile + `status` (offline/available/on_delivery/paused). |
| `rider_locations` | Latest position per rider (one row per rider, upserted). |
| `rider_location_history` | Append-only GPS trail. |
| `orders` | Delivery orders with pickup + dropoff geographies and lifecycle timestamps. |
| `order_events` | Append-only state timeline (one row per status change). |
| `dispatch_offers` | Time-bounded offer to a specific rider. |

All tables: `id uuid pk`, `created_at`, `updated_at` (where mutable), `deleted_at` for soft-deletable entities, RLS enabled.

## Enums

- `app_role`: `super_admin | business_owner | dispatcher | rider`
- `business_role`: `owner | manager | staff`
- `rider_status`: `offline | available | on_delivery | paused`
- `order_status`: `draft | pending_assignment | offered | assigned | picked_up | delivered | cancelled`
- `offer_response`: `pending | accepted | declined | expired`

## Indexes (highlights)

- GIST on `businesses.location`, `orders.pickup_location`, `orders.dropoff_location`, `rider_locations.location`.
- `orders(status, business_id)`, `orders(assigned_rider_id, status)`.
- `dispatch_offers(rider_id, response, expires_at)`.

## Migration policy

- One concern per migration (`001_enable_extensions.sql` … `012_seed_dev.sql`).
- Migrations applied via `mcp__supabase__apply_migration` against a **Supabase branch** first, then merged.
- Never edit a migration after it is applied to a shared environment. Add a new one.

## ER diagram (high level)

```
auth.users ──1:1──▶ profiles
profiles  ─1:N─▶ business_members ◀─N:1─ businesses
businesses ─1:N─▶ orders ─N:1─ riders (assigned_rider_id)
orders     ─1:N─▶ order_events
orders     ─1:N─▶ dispatch_offers ─N:1─ riders
riders     ─1:1─▶ rider_locations
riders     ─1:N─▶ rider_location_history
```
