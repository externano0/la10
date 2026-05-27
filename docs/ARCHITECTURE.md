# Architecture

## Monorepo layout

```
apps/
  mobile/          Flutter (Android/iOS) shell — riders + business owners
  web_desktop/     Flutter (web + Windows/macOS) shell — dispatchers + admin
packages/
  core/            Pure Dart: Result, Failure, env, value objects
  data/            Supabase client, repositories, realtime service, generated DB types
  ui/              Shared widgets, theme, design tokens
  geo/             OSRM client, geohash, distance utilities
  features/
    auth/          Sign-in, sign-up, role gate
    riders/        Rider profile, status, dashboard
    businesses/    Business profile, members, dashboard
    orders/        Order CRUD, status timeline
    tracking/      Rider live location, map view
    dispatch/      Dispatcher console, manual assignment, offer monitor
supabase/
  migrations/      Ordered SQL (001…012)
  functions/       Edge functions (TypeScript / Deno)
  policies/        RLS reference (mirror of migration 010)
  seed/            Dev-only seed scripts
```

## Feature module shape

Every feature is `data / domain / presentation`:
- `domain/` — entities (Freezed), repository interfaces, use cases. No Supabase imports.
- `data/` — repository implementations against `packages/data`. Maps DTOs ↔ domain.
- `presentation/` — Riverpod providers/notifiers (codegen), routes, widgets.

The rule: `presentation` depends on `domain`; `data` depends on `domain`; `domain` depends on nothing outside Dart core. UI never touches Supabase directly.

## State management

Riverpod 2 with `riverpod_generator` and `riverpod_lint`. Notifiers are `@riverpod` async classes. Streams use `StreamProvider` so Supabase channels auto-cancel on dispose.

## Routing

`go_router` per-app. Role-aware redirect:
- `mobile`: rider role → `/rider`; business_owner → `/business`.
- `web_desktop`: dispatcher → `/dispatch`; super_admin → `/admin`.

## Realtime

`RealtimeService` (in `packages/data`) opens one channel per subscription scope (e.g. `orders:business_id`, `rider_locations`, `dispatch_offers:rider_id`). Subscriptions are owned by Riverpod providers and torn down with the provider.

**Heartbeat throttle** (rider only): emit a location upsert when (`distance > 20 m` AND `t > 10 s`) OR `t > 30 s`. Implementation in `packages/data/lib/realtime/rider_heartbeat_throttle.dart`.

## Maps

`flutter_map` + OSM tiles. `packages/geo/osrm_client.dart` wraps OSRM HTTP. Distances pre-computed via PostGIS `ST_Distance` server-side when possible.

## Auth + roles

Supabase Auth (email/password, phone OTP optional). On `auth.users` insert, a trigger creates a `profiles` row with default role `rider`. Roles: `super_admin`, `business_owner`, `dispatcher`, `rider`. All RLS uses `auth.uid()` + a `public.current_role()` helper.

## Dispatch flow (Phase 1)

1. Business creates order → `orders.status='draft'`.
2. Business submits → trigger sets `status='pending_assignment'` + invokes `dispatch-order`.
3. `dispatch-order` selects best rider (closest available, lowest workload, within radius), writes `dispatch_offers` with 30 s TTL, sets order to `offered`.
4. Rider accepts → `offer-respond` sets order to `assigned`; declines → re-dispatch.
5. `expire-offers` cron (10 s) marks expired and re-dispatches.

Grouped delivery (Phase 2) and AI prediction (Phase 3) are explicitly out of scope here.
