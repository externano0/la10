# API (Edge Functions)

All functions live under `supabase/functions/`. Default `verify_jwt: true`. Service-role logic is server-side only.

## `dispatch-order` (POST)

Selects the best rider for an order and writes a `dispatch_offers` row.

**Request**
```json
{ "order_id": "<uuid>" }
```
**Response**
```json
{ "offered_rider_id": "<uuid>", "offer_id": "<uuid>", "expires_at": "<iso>" }
```
**Errors**: `404` order not found, `409` order not in `pending_assignment`, `503` no eligible rider.

## `offer-respond` (POST)

Rider accepts or declines an offer.

**Request**
```json
{ "offer_id": "<uuid>", "response": "accepted" | "declined" }
```
**Response**
```json
{ "order_status": "assigned" | "pending_assignment" }
```

## `expire-offers` (cron, internal)

Invoked by `pg_cron` every 10 s. Marks `dispatch_offers` where `expires_at < now()` AND `response = 'pending'` as `expired`, then re-dispatches the order. No HTTP contract.

## `rider-heartbeat` (POST)

Upserts the rider's current location.

**Request**
```json
{ "lat": -34.6, "lng": -58.4, "heading": 90, "speed": 5.5, "accuracy_m": 8 }
```
**Response** `{ "ok": true }` or `{ "skipped": "throttled" }`.

## `order-status` (POST)

Centralised state-machine transitions for orders. Validates allowed transitions per role.

**Request**
```json
{ "order_id": "<uuid>", "to": "picked_up" | "delivered" | "cancelled", "reason": "string?" }
```
**Response** `{ "order_status": "<new status>" }`.

## Error shape (all functions)

```json
{ "error": { "code": "STRING", "message": "human readable" } }
```
