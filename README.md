# La 10 — Plataforma de delivery

> Una agencia de delivery (La 10) que coordina a muchos comercios. Los comercios crean
> pedidos, el sistema asigna riders cercanos automáticamente, el jefe puede intervenir
> y todos ven el estado del pedido en tiempo real.

**URL de prueba:** https://la10-nine.vercel.app

---

## Tabla de contenidos

1. [¿Qué es esto?](#qué-es-esto)
2. [Los 3 roles](#los-3-roles)
3. [Cómo se conectan las piezas](#cómo-se-conectan-las-piezas)
4. [Cómo está organizado el código](#cómo-está-organizado-el-código)
5. [Cómo correrlo en tu PC](#cómo-correrlo-en-tu-pc)
6. [Cómo deployar a producción](#cómo-deployar-a-producción)
7. [Base de datos: tablas y por qué cada una](#base-de-datos-tablas-y-por-qué-cada-una)
8. [Edge functions (lógica que corre en el servidor)](#edge-functions-lógica-que-corre-en-el-servidor)
9. [Flujo completo de un pedido (paso a paso)](#flujo-completo-de-un-pedido-paso-a-paso)
10. [Cómo agregar una feature nueva](#cómo-agregar-una-feature-nueva)
11. [Glosario](#glosario)

---

## ¿Qué es esto?

La 10 es como Rappi o PedidosYa pero para una sola agencia local de delivery.
Una agencia tiene varios comercios clientes (almacenes, kioscos, restoranes) y sus
propios riders (motoqueros). Cuando un comercio carga un pedido, La 10 lo asigna
automáticamente al rider más cercano que esté disponible. El jefe de la agencia ve
todo en un panel y puede intervenir si hace falta (reasignar a otro rider, cancelar,
priorizar).

**Funciona en cualquier dispositivo**: la misma app responde al tamaño de pantalla.
El rider la usa desde el celu, el comercio desde una tablet o PC, el jefe desde la PC.

---

## Los 3 roles

| Rol               | Qué ve                                          | Rutas                 |
|-------------------|-------------------------------------------------|-----------------------|
| **Rider**         | Sus ofertas, su orden activa, su GPS, su estado | `/r/*`                |
| **Comercio**      | Sus negocios, sus pedidos, crear pedido nuevo   | `/b/*`                |
| **Jefe**          | Todos los pedidos, todos los riders, mapa vivo  | `/d/*`                |
| **Super-admin**   | Lo mismo que jefe + promover roles              | `/d/*`                |

El **role-gate** está en el router (ver [apps/web_desktop/lib/app.dart](apps/web_desktop/lib/app.dart)):
si un rider intenta abrir `/d/home`, lo redirige a `/r/home`. Cada rol tiene su
"prefijo permitido" y el redirect se ocupa de no dejar que se cruce.

---

## Cómo se conectan las piezas

```
┌─────────────────────┐         ┌─────────────────────┐
│  App Flutter (web)  │◄───────►│   Supabase Cloud    │
│  - mobile           │  HTTPS  │  - Postgres + RLS   │
│  - web_desktop      │   WSS   │  - Realtime (WAL)   │
└─────────────────────┘         │  - Edge Functions   │
                                │  - Auth             │
                                └─────────────────────┘
                                          │
                                          │ (tile fetch)
                                          ▼
                                ┌─────────────────────┐
                                │ OpenStreetMap tiles │
                                └─────────────────────┘
```

- **App Flutter**: una sola codebase corre en web (Vercel), en Android y en iOS.
  No tiene secrets: la lógica que requiere permisos elevados está en edge functions.
- **Supabase**: hace de backend completo. La DB tiene políticas de seguridad (RLS)
  que limitan qué fila puede leer cada usuario según su rol.
- **Edge functions**: TypeScript/Deno que corre en servidores de Supabase. Lo usamos
  para dispatch, cambios de estado, heartbeat del rider, etc. — lugares donde no
  queremos confiar en el cliente.
- **OpenStreetMap**: tiles del mapa, son gratis y públicos (el GPS lo provee el browser).

---

## Cómo está organizado el código

```
la 10/
├── apps/                  ← entry points (donde está main.dart)
│   ├── mobile/            ← Android + iOS (futuro)
│   └── web_desktop/       ← lo que se sirve en https://la10-nine.vercel.app
│
├── packages/              ← código compartido entre apps
│   ├── core/              ← config + utilidades comunes (Env, App.id...)
│   ├── geo/               ← LatLng, distancia haversine, cliente OSRM
│   ├── ui/                ← theme Material 3, tokens de color, widgets reusables
│   ├── data/              ← acceso a Supabase + repositorios
│   │   └── lib/src/repositories/
│   │       ├── businesses_repository.dart
│   │       ├── orders_repository.dart
│   │       ├── riders_repository.dart
│   │       ├── offers_repository.dart
│   │       ├── dispatch_repository.dart
│   │       └── chat_repository.dart
│   └── features/          ← un paquete por feature/rol
│       ├── auth/          ← login, signup, role bootstrap
│       ├── businesses/    ← surface del comercio
│       ├── orders/        ← form de creación de orden, detalle
│       ├── riders/        ← surface del rider (home, ofertas, GPS)
│       ├── dispatch/      ← surface del jefe (home, mapa, riders, chat)
│       └── tracking/      ← componentes de tracking compartidos
│
└── supabase/
    ├── migrations/        ← SQL de la DB (corren en orden)
    └── functions/         ← edge functions (TypeScript/Deno)
```

**Regla mental**: si algo se usa en más de un rol → vive en `packages/`. Si es de
un rol solo → vive en `packages/features/<rol>/`. Los `apps/*` solo arman el router
y pegan las features.

---

## Cómo correrlo en tu PC

**Pre-requisitos:** Flutter 3.22+, Dart 3.4+, Node 18+ (para Vercel CLI).

1. Cloná el repo y entrá a la carpeta.
2. Copiá `.env.example` a `.env` si no existe y rellená `SUPABASE_URL` + `SUPABASE_ANON_KEY` (están en el panel de Supabase → Settings → API).
3. Instalá dependencias de todos los packages:
   ```powershell
   dart pub global run melos bootstrap
   ```
4. Levantá el web en Chrome:
   ```powershell
   cd apps/web_desktop
   flutter run -d chrome --dart-define-from-file='..\..\.env' --web-port=5176
   ```

La primera vez tarda ~1 minuto. Después los hot-reloads son instantáneos (apretás `r` en la terminal).

---

## Cómo deployar a producción

El frontend va a **Vercel** (estático, sin backend ahí). El backend ya vive en Supabase Cloud.

```powershell
cd apps/web_desktop
flutter build web --release --dart-define-from-file='..\..\.env'
Copy-Item vercel.json build/web/
cd build/web
vercel --prod
```

La URL queda en `https://la10-nine.vercel.app`. Si querés un dominio propio, lo
agregás desde el dashboard de Vercel.

**Para deployar una edge function:** se hace por separado con el MCP de Supabase
o con `supabase functions deploy <nombre>`.

**Para aplicar una migración SQL:** se hace por separado con el MCP de Supabase
o con `supabase db push`. Las migraciones están numeradas (`001`, `002`, ...) y
se aplican en orden.

---

## Base de datos: tablas y por qué cada una

Todas las tablas viven en el schema `public` y tienen **Row Level Security (RLS)**
activada. Eso quiere decir que cada query se filtra automáticamente según quién
sos. Si un rider hace `SELECT * FROM orders`, solo ve las órdenes que le tocan
a él, no las de otros.

| Tabla                     | Para qué                                                     |
|---------------------------|--------------------------------------------------------------|
| `profiles`                | Una fila por usuario. Guarda el rol y el nombre.             |
| `riders`                  | Una fila por usuario que es rider. Guarda vehículo y estado. |
| `businesses`              | Comercios (uno por cliente de la agencia).                   |
| `business_members`        | Empleados con acceso a un comercio (a futuro, invitaciones). |
| `orders`                  | Pedidos. Tienen pickup, dropoff, estado y rider asignado.    |
| `order_events`            | Historia de cambios de estado de un pedido (timeline).       |
| `dispatch_offers`         | Una oferta de pedido a un rider con TTL (30s por default).   |
| `rider_locations`         | Última ubicación conocida de cada rider (lat/lng).           |
| `rider_location_history`  | Histórico de ubicaciones (para auditoría/optimización).      |
| `chat_messages`           | Mensajes entre jefe y rider.                                 |

Los cambios de schema están en `supabase/migrations/`. Cada uno empieza con un
número y un nombre. **Nunca editamos un archivo de migración ya aplicado** —
creamos una nueva.

---

## Edge functions (lógica que corre en el servidor)

Las edge functions corren en Deno, en servidores de Supabase. Las usamos cuando
no queremos confiar en lo que mande el cliente.

| Función           | Qué hace                                                                 |
|-------------------|--------------------------------------------------------------------------|
| `dispatch-order`  | Toma un pedido y le hace una oferta al rider más cercano (o uno manual). |
| `offer-respond`   | El rider acepta/rechaza una oferta. Avanza el pedido si acepta.          |
| `expire-offers`   | Marca ofertas vencidas como `expired` (corre en cron cada minuto).       |
| `rider-heartbeat` | El rider manda su lat/lng. Se guarda en `rider_locations`.               |
| `order-status`    | Transiciones de estado del pedido con validación (no podés saltar pasos).|

**Por qué edge fns y no SQL directo desde el cliente:**
- Validan el estado anterior (no podés pasar de `draft` a `delivered`).
- Auditan (`order_events`).
- Encapsulan lógica de negocio (cómo se elige el rider).
- No exponen lógica sensible al frontend.

---

## Flujo completo de un pedido (paso a paso)

1. **Comercio crea pedido** (`/b/businesses/:id/orders/new`)
   - Llena cliente, direcciones (pickup + dropoff) y monto.
   - `OrdersRepository.create(...)` inserta en `orders` con `status = 'draft'`.
2. **Comercio envía el pedido** (botón "Enviar a despacho")
   - Invoca `order-status` edge fn con `to: 'pending_assignment'`.
   - La fn valida la transición y agrega un row a `order_events`.
3. **Sistema busca el rider más cercano**
   - El jefe (o un trigger) invoca `dispatch-order` con `order_id`.
   - La fn corre la RPC `la10_find_best_rider` que mezcla distancia + carga activa.
   - Crea una fila en `dispatch_offers` con TTL de 30s.
   - Cambia `orders.status` a `'offered'`.
4. **Rider ve la oferta** (`/r/offers`)
   - El cliente está suscrito por realtime a `dispatch_offers` filtrado a su user.
   - Aparece una card con countdown.
5. **Rider acepta o rechaza**
   - Llama a `offer-respond` con `'accept'` o `'reject'`.
   - Si acepta: `orders.status = 'assigned'`, `orders.assigned_rider_id = self`, y el rider pasa a `'on_delivery'`.
   - Si rechaza o vence: se busca el próximo candidato.
6. **Rider hace el delivery**
   - Botón "Retiré" → `order-status` con `to: 'picked_up'`.
   - Botón "Entregué" → `order-status` con `to: 'delivered'`.
   - En el medio, el GPS manda heartbeats cada 10–30s (ver `RiderGpsTracker`).
7. **Jefe ve todo en tiempo real**
   - `/d/home`: contadores + lista live.
   - `/d/map`: markers de riders y pickups actualizándose.
   - `/d/orders/:id`: timeline completa + botón "Reasignar manualmente".

---

## Cómo agregar una feature nueva

Pongamos que querés agregar "calificación del rider al final del delivery".

1. **Pensá los datos**: ¿hace falta una tabla nueva? Si sí, escribí una migración
   en `supabase/migrations/0XX_ratings.sql` con la tabla, sus índices y sus
   políticas RLS.
2. **Backend si hace falta**: ¿hay lógica que no podés confiar al cliente? Hacé
   una edge function en `supabase/functions/<nombre>/index.ts`.
3. **Repositorio**: agregá `packages/data/lib/src/repositories/ratings_repository.dart`
   con métodos puros (no UI). Exportalo desde `la10_data.dart`.
4. **UI**: agregá una screen en `packages/features/<rol>/lib/presentation/`. Si es
   compartida entre roles, pensá un widget en `packages/ui/`.
5. **Router**: registrá la nueva ruta en el `*_routes.dart` del feature, y
   eventualmente en el redirect del `apps/*/lib/app.dart` si necesita guard.
6. **Probá en local** (`flutter run -d chrome`).
7. **Deployá**: rebuild + `vercel --prod`. Migraciones via MCP/CLI.

**Convenciones que mantenemos:**
- Strings de UI en castellano rioplatense.
- Cada feature tiene un solo paquete `la10_<feature>`.
- Repositorios devuelven dominios (clases con `fromJson`), no `Map<String, dynamic>`.
- Realtime se modela como `StreamProvider` de Riverpod.
- Si una lógica no es obvia, se comenta el **por qué** (no el qué).

---

## Glosario

- **Edge function**: código que corre en el servidor de Supabase (Deno), no en el cliente.
- **RLS (Row Level Security)**: políticas de Postgres que filtran filas según quién consulta.
- **Realtime / WAL**: cuando una tabla está publicada, los cambios se propagan a los clientes suscritos vía WebSocket. El WAL es el log de cambios de Postgres.
- **Replica Identity FULL**: setting de Postgres que hace que el WAL incluya la fila entera (no solo la PK) en UPDATEs. Necesario para que el mapa reciba el nuevo lat/lng.
- **Riverpod**: librería de gestión de estado en Flutter. Provee `Provider`, `FutureProvider`, `StreamProvider`.
- **GoRouter**: router de Flutter con soporte de redirects y deep links.
- **Edge offer / dispatch offer**: la propuesta que el sistema le hace a un rider para un pedido específico, con un TTL.
- **Heartbeat**: ping periódico del rider mandando su ubicación.

---

## Para vos (Claude / cualquier dev nuevo)

Si llegaste a este archivo es porque querés entender el proyecto sin tener que
leer todo el código. Te dejo lo que importa de verdad:

1. **El monorepo es Flutter + Supabase.** No hay un servidor Node propio en el medio.
2. **El cliente nunca habla con la DB sin pasar por una edge function** cuando hay
   lógica de transición de estado. Los `select` directos están bien para lectura.
3. **El mapa se actualiza solo** porque las tablas tienen `REPLICA IDENTITY FULL` y
   están en la publicación `supabase_realtime`. Si agregás una tabla nueva que
   debería streamear, agregala a la publicación y setealea a FULL.
4. **El throttle del heartbeat** (`RiderHeartbeatThrottle`) decide cuándo mandar
   una posición: máximo cada 30s, mínimo cada 10s, mínimo 20m de movimiento.
5. **Las migraciones son inmutables.** Si te equivocaste, sumá una nueva que arregle.
