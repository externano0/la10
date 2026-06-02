# La 10 — Plataforma de delivery

> Una agencia de delivery (La 10) que coordina a muchos comercios. Los comercios crean
> pedidos, el sistema asigna riders cercanos automáticamente, el jefe puede intervenir
> y todos ven el estado del pedido en tiempo real.

**URLs:**
- 🌐 Web (PWA): https://la10-nine.vercel.app
- 📱 APK Android (rider): https://github.com/externano0/la10/releases (último release)
- 💻 Código: https://github.com/externano0/la10

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
10. [Features clave por rol](#features-clave-por-rol)
11. [Notificaciones y sonidos](#notificaciones-y-sonidos)
12. [Cómo agregar una feature nueva](#cómo-agregar-una-feature-nueva)
13. [Glosario](#glosario)
14. [Changelog rápido](#changelog-rápido)

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
| `chat_messages`           | Mensajes entre jefe y rider (texto y audio).                 |
| `fcm_tokens`              | Token FCM por (usuario, plataforma) para enviar push notifications. |

**Storage:**

| Bucket            | Para qué                                                              |
|-------------------|-----------------------------------------------------------------------|
| `chat-audios`     | Audios del chat (privado, signed URLs). Path `<sender_uid>/<ts>.webm`.|

Los cambios de schema están en `supabase/migrations/`. Cada uno empieza con un
número y un nombre. **Nunca editamos un archivo de migración ya aplicado** —
creamos una nueva.

---

## Edge functions (lógica que corre en el servidor)

Las edge functions corren en Deno, en servidores de Supabase. Las usamos cuando
no queremos confiar en lo que mande el cliente.

| Función           | Qué hace                                                                 |
|-------------------|--------------------------------------------------------------------------|
| `dispatch-order`  | Toma un pedido y le hace una oferta al rider más cercano (o uno manual). Dispara `send-push` para alertar al rider. |
| `offer-respond`   | El rider acepta/rechaza una oferta. Avanza el pedido si acepta.          |
| `expire-offers`   | Marca ofertas vencidas como `expired` (corre en cron cada minuto).       |
| `rider-heartbeat` | El rider manda su lat/lng. Se guarda en `rider_locations`.               |
| `order-status`    | Transiciones de estado del pedido con validación (no podés saltar pasos).|
| `send-push`       | Manda push notification FCM a un user (firma JWT con service account de Firebase). |

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

## Features clave por rol

### Rider (`/r/*`)
- **`/r/home`** — estado (Disponible/Pausado/Offline), GPS automático con throttle, botón "Probar sirena", chat con dispatch.
- **`/r/offers`** — lista de ofertas pendientes.
- **`/r/orders/:id`** — pedido activo: mapa con polyline pickup→dropoff, monto destacado, botones "Ir" (Google Maps), "Llamar", y acción principal "Retiré"→"Entregué".
- **Popup de oferta full-screen** — aparece automáticamente cuando llega una oferta nueva. Tiene countdown del TTL, mini-mapa, monto y direcciones. No se puede cerrar (Aceptar / Rechazar).
- **`/r/chat`** — hilo con el jefe (texto + audio).

### Comercio (`/b/*`)
- **`/b/home`** — grilla de mis negocios + botón "Nuevo".
- **`/b/businesses/new`** — registro del negocio con **map picker** (tap en mapa, sin lat/lng manual). La ubicación se guarda como pickup default de TODAS las órdenes del comercio.
- **`/b/businesses/:id`** — header del negocio, lista de pedidos.
- **`/b/businesses/:id/orders/new`** — form de orden: pickup auto-cargado del comercio, dropoff con **map picker** (tap en mapa), cliente, monto, notas.

### Jefe / super-admin (`/d/*`)
- **`/d/home`** — contadores por estado + lista realtime de órdenes.
- **`/d/map`** — mapa en vivo con markers de riders (color por status) y pickups de órdenes activas.
- **`/d/map/rider/:id`** — abre el mapa centrado en un rider específico.
- **`/d/riders`** — listado realtime. Cada card tiene 3 botones: Localizar / Llamar / Mensaje.
- **`/d/orders/:id`** — detalle con **mapa de tracking en vivo del rider asignado** (marker que se mueve realtime + polyline OSRM hacia el siguiente waypoint), timeline + botón "Reasignar manualmente" (muestra todos los riders activos, no sólo `available`).
- **`/d/chat/:id`** — chat con un rider específico.

### Mapas y navegación
- **Visualización in-app** → `flutter_map` + tiles de OpenStreetMap (gratis, sin API key).
- **Rutas reales** → cliente `OsrmClient` consulta `https://router.project-osrm.org` y devuelve la polyline siguiendo calles. Si OSRM no responde, fallback a línea recta.
- **Navegación turn-by-turn** → delegada a Google Maps externa via `tel:`/`https://google.com/maps` (botón "Ir" en `/r/orders/:id`).

---

## Notificaciones y sonidos

Tres canales separados:

| Evento                        | Web                                          | Mobile (APK)                                       |
|-------------------------------|----------------------------------------------|----------------------------------------------------|
| **Oferta nueva al rider**     | Sirena sintetizada (4 beeps 880↔1320 Hz)     | Vibración fuerte + ringtone de alarma del sistema  |
| **Mensaje nuevo al rider**    | Ding-dong suave (sine 1568→1318 Hz)          | Vibración corta + tono de notification             |
| **Mensaje nuevo al jefe**     | Ding-dong suave                              | (mismo) — el jefe también lo recibe en `/d/home`   |

**Cómo se implementa:**
- En web: Web Audio API generando los tonos en el momento (`packages/features/*/lib/presentation/*_ringtone_web.dart`).
- En mobile: `flutter_ringtone_player` para sonidos del sistema + `vibration` para el patrón de vibración.
- El audio del browser **requiere un gesto del usuario** primero (autoplay policy). El primer tap en cualquier botón "despierta" el audio context.

### Push notifications (celu bloqueado / app cerrada) — FCM

Para que el rider reciba la oferta con el celu en el bolsillo, usamos **Firebase Cloud Messaging**.

**Flujo:**
1. Rider abre la app → `initFcm()` inicializa Firebase + registra un background handler top-level.
2. Rider entra a `/r/home` → `registerFcmToken()` pide permiso de notificaciones, obtiene el token del device y lo upsertea en `fcm_tokens`.
3. Comercio crea orden → `dispatch-order` elige rider → invoca `send-push` con `user_id`.
4. `send-push` firma un JWT RS256 con la service account de Firebase, lo cambia por un access token OAuth, y manda POST a `https://fcm.googleapis.com/v1/projects/<proj>/messages:send`.
5. FCM despierta el celu (incluso bloqueado o con la app killeada) y muestra la notif heads-up con sonido.

**Setup operacional (una vez):**
- `apps/mobile/android/app/google-services.json` — descargado de Firebase Console y committeado al repo (no tiene secretos críticos, solo IDs públicos).
- Secret `FIREBASE_SERVICE_ACCOUNT_JSON` en Supabase → Edge Functions → Secrets — JSON completo del service account (Firebase → Project settings → Service accounts → Generate new private key). **Este SÍ es secreto.**

**Limitación:** FCM no garantiza entrega en celus con modos de ahorro agresivo (Xiaomi MIUI, Huawei). En esos casos hay que pedirle al usuario que excluya la app de optimización de batería.

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

## Changelog rápido

Solo cambios estructurales que mueven la app, no cada bugfix. La historia completa está en `git log`.

- **2026-06-02 — Card del rider_home desaparece al entregar/cancelar (v0.1.18):** fix al feedback del user "ya entregué y el cartel amarillo sigue ahí". Después de `transition('delivered')` o `transition('cancelled')` en `rider_active_order`: (1) navegamos automáticamente de vuelta a `/r/home` (antes el rider se quedaba en la pantalla del pedido entregado), (2) `ref.invalidate(myActiveOrderProvider)` fuerza re-fetch del stream del card — antes el card podía quedar visible 1-2s hasta que el realtime de Supabase propagaba la UPDATE. El provider `_myActiveOrderProvider` fue exportado como `myActiveOrderProvider` para poder invalidarlo desde otros files. Snackbar más visual: "Pedido entregado ✅".
- **2026-06-02 — Card "Pedido activo" en rider_home + fallback de orderId vía body.id (v0.1.17):** dos fixes complementarios al accept del popup tipo llamada que el user reporto "no me lleva a ningun lado". (1) En `_onCallkitEvent` ahora si `extra['order_id']` viene vacío (caso "Bundle Serializable se perdió en MethodChannel"), usamos `event.body['id']` como fallback — el `id` del CallKitParams es seteado al `orderId` cuando se muestra el popup, así que es source-of-truth confiable. (2) Nuevo `OrdersRepository.watchMyActive(riderId)` que streamea el pedido del rider en status `assigned` o `picked_up`. `rider_home` ahora pinta arriba un card amarillo grande "Pedido por retirar / en camino" cuando hay uno, con dirección, monto, y botón "Abrir pedido" que va a `/r/orders/{id}`. Es la escotilla de emergencia para que el rider siempre llegue al detalle del pedido aunque el popup accept no haya logrado navegar.
- **2026-06-02 — Full-screen intent permission + offer_id en extra + drain-on-boot (v0.1.16):** tres fixes al popup tipo llamada. (1) **Permiso de "Notificaciones de pantalla completa"** agregado al sheet de modo en línea — sin esto Android 14+ no muestra la Activity full-screen sobre el lock screen (solo se oía el ringtone). Se chequea con `FlutterCallkitIncoming.canUseFullScreenIntent()` y se pide via `requestFullIntentPermission()` que abre Settings. (2) `offer_id` ahora va dentro del `extra` del CallKitParams — sin él, el accept handler no podía postear `respond('accepted')` al backend. (3) `_drainAcceptedCallOnBoot()` en `initFcm`: al arrancar la app, consulta `activeCalls()` y si encuentra una con `order_id` (caso "app matada → callkit Activity → user accept → engine muerto pierde el evento"), la procesa: respond accepted + navega a `/r/orders/{order_id}` + endCall para que no vuelva a popup. Cubre el escenario "el rider aceptó mientras la app no existía".
- **2026-06-02 — Popup tipo llamada exclusivo + accept va al detalle (v0.1.15):** `send-push` v9 ahora manda payload DATA-ONLY (sin `notification`) — el SO ya no muestra heads-up estilo "mensaje" en paralelo. La única UI que aparece es el popup full-screen del `flutter_callkit_incoming`. Aceptar el popup ahora: 1) hace POST a `OffersRepository.respond(offer_id, accepted)`, 2) navega directo a `/r/orders/{order_id}` (la pantalla con mapa + direcciones + monto + botones de estado). Rechazar también postea `declined`. Si el accept ocurre antes que el app boot termine (caso "app matada → callkit launcheo MainActivity"), guardamos un pending y el navigator lo drena cuando se inyecta. Web: address_field reescrito — pin es un `Container` (no `Icon`) para evitar tree-shaking de Material Icons + dropdown de Nominatim re-ordenado para priorizar hits con `house_number` matcheado sobre centroides de calle.
- **2026-06-01 — Popup tipo llamada real + SW kill-switch (v0.1.14):** integramos `flutter_callkit_incoming` para que cuando llega una oferta aparezca un POPUP FULL-SCREEN tipo llamada entrante (estilo WhatsApp call) sobre el lock screen / Instagram / banco — el plugin mantiene un foreground service que no es matado por el battery saver de ZTE/MIUI/Samsung. El popup muestra el monto + `pickup → dropoff` y tiene botones grandes Aceptar/Rechazar. ACCEPT navega al rider a `/r/offers`. `dispatch-order` v12 ahora pasa `pickup`, `dropoff` y `amount` en el `data` payload del push (antes solo el `order_id`). Web: el snippet `unregister` no alcanzaba porque `vercel.json` cacheaba `flutter_service_worker.js` con `max-age=31536000 immutable` — el browser ni siquiera pedía el nuevo. Fix: regla `no-cache` específica para `flutter_service_worker.js` + `flutter_bootstrap.js` + `main.dart.js`, y reemplazo del SW por un kill-switch que borra caches y se autodesregistra. Después de 1 reload el browser entra al server limpio y muestra la UI nueva (autocomplete + mini-mapa).
- **2026-06-01 — Heads-up FCM confiable + SW unregister (v0.1.13):** vuelta al payload híbrido (`notification` + `data`) — el campo `notification` es lo único que garantiza delivery cuando la app fue matada por el battery saver (ZTE/Samsung/MIUI con celu bloqueado). Canal `la10_offers_call` reconfigurado con `Importance.max`, `vibrationPattern` largo tipo llamada (1s vibra/0.5s pausa x3), LED rojo, `visibility: PUBLIC` para que aparezca en lock screen. Sacamos `_localNotifs.show()` custom desde el bg handler (duplicaba la notif del SO). Web: snippet en `index.html` que unregistra el service worker viejo — soluciona el problema de UI cacheada pre-v0.1.9 que veían los usuarios después de cada deploy. El popup full-screen estilo "incoming call WhatsApp" queda como follow-up (requiere foreground service + Activity Kotlin nativa).
- **2026-06-01 — Fix push 401 + dirección Enter→mapa (v0.1.10):** root cause de que las push notifications nunca llegaban: `dispatch-order` invocaba `send-push` con `sb.functions.invoke()` que NO auto-inyecta el JWT del servicio → send-push (verify_jwt=true) rechazaba con 401 en cada call. Cambiamos a `fetch` directo pasando `service_role_key` como Bearer. Ahora el push llega cuando el celu está bloqueado / con otra app en foreground. AddressField: Enter (o botón lupa) ahora abre el map picker centrado en el primer hit de Nominatim → el user toca el punto exacto y confirma. Antes Enter no hacía nada, había que tocar el resultado del dropdown.
- **2026-06-01 — Address autocomplete inline + FCM payload híbrido (v0.1.9):** widget `AddressField` reusable con autocomplete Nominatim: el comercio/jefe escribe la dirección y debajo aparecen los hits — toca uno y queda fijado el punto sin abrir mapa. "Ajustar" sigue disponible si querés afinar. Usado en `business_create` y `order_new` (dropoff). FCM: volvimos a payload híbrido (`notification` + `data`) con `channel_id: la10_offers_call` + `notification_priority: PRIORITY_MAX`. Antes era data-only que en MIUI/Xiaomi se perdía con battery saver. Ahora el SO muestra heads-up siempre (en lock screen + en foreground de otra app) con sonido y vibración. Sacamos `flutter_local_notifications.show()` custom (no era confiable en Android 14+ con fullScreenIntent restringido).
- **2026-06-01 — Modo en línea + auto-pick mapa (v0.1.8):** rider home muestra botón grande "Estoy en línea" que abre bottom sheet pidiendo permisos: notificaciones, overlay (`SYSTEM_ALERT_WINDOW`), exact alarm, ignore battery. Sin estos, FCM no aparece con el celu bloqueado o con otra app en foreground. Solo después de granted pasa a `available`. Map picker ahora auto-centra el mapa en el primer hit de Nominatim en cuanto el comercio escribe (sin necesidad de tocar el resultado). Submit con Enter o botón → centra siempre el primero. Permiso `SYSTEM_ALERT_WINDOW` en manifest (vía permission_handler).
- **2026-06-01 — Búsqueda de direcciones + FCM llamada (v0.1.7):** map picker ahora tiene buscador de direcciones (Nominatim/OSM) — el comercio escribe "Av. Corrientes 1234" y le tira hasta 5 hits para tocar y centrar. Se evita pinchar la cuadra a ojo. FCM rider muestra notificación tipo *llamada entrante* full-screen (`flutter_local_notifications` + `fullScreenIntent` + canal HIGH importance) que pinta la pantalla incluso con el celu bloqueado. `MainActivity` configurada con `showWhenLocked` + `turnScreenOn`. Permisos `USE_FULL_SCREEN_INTENT` + `SCHEDULE_EXACT_ALARM` en manifest. `send-push` ahora manda payload data-only (sin `notification`) para que el cliente maneje toda la UI. Signup web esconde "Soy rider" (riders usan el APK).
- **2026-05-28 — Ronda fix UX (v0.1.6):** quitamos definitivamente los inputs de lat/lng del form de orden (pickup se hereda del local marcado en el mapa; dropoff usa map picker). FCM: el tap en la notificación navega a `/r/offers` donde el guard levanta el popup automáticamente (antes la notif quedaba "muda"). `rider_offers` ahora navega a `/r/orders/:id` después de aceptar y muestra el monto/direcciones reales en cada card (antes solo el UUID). Mensaje de error de red en el home rider en humano ("Sin internet — reintentando…") en vez de stack. Migración 025 (columna `created_by` audit en orders + INSERT policy explícita con `auth.uid() IS NOT NULL`).
- **2026-05-27 — FCM push notifications:** tabla `fcm_tokens` + edge fn `send-push` (firma JWT RS256, llama FCM HTTP v1). `dispatch-order` dispara push al rider con cada oferta. Servicio Flutter `fcm_service` con conditional imports (stub web / impl mobile). Compatible con celu bloqueado o app cerrada. Requiere setup de Firebase (ver sección "Push notifications"). Migración 024.
- **2026-05-27 — Map picker + dirección del comercio:** comercio se registra marcando el local en un mapa (sin pedir lat/lng). El pickup queda fijo y se autocompleta en cada orden. Form de orden usa también map picker para el dropoff. OSRM client para rutas reales (no líneas rectas) en rider activo y en `/d/orders/:id` (tracking en vivo del rider con polyline al siguiente waypoint). Migración 023 (lat/lng denormalizado en businesses).
- **2026-05-27 — Persistencia de sesión + comercio default address:** refresh del token con timeout 6s al arrancar la app; signOut limpio si falla. `HomeScreen` con botones Reintentar / Cerrar sesión si profile no carga. compileSdk Android forzado a 36 (vía `subprojects { afterEvaluate }`) para que las deps modernas compilen.
- **2026-05-27 — APK + CI:** repo en GitHub, GitHub Actions builda `app-release.apk` y lo deja como artifact + release. Web sigue auto-deployando manual a Vercel. Migración 017 (lat/lng denormalizado en `rider_locations` y `orders`), 018 (REPLICA IDENTITY FULL para que realtime mande payload completo en UPDATEs), 019 (`chat_messages`), 020 (`ensure_rider_row` con phone), 021 (audio en chat + bucket `chat-audios`), 022 (RLS del rider para leer la orden mientras tiene oferta pendiente).
- **2026-05-27 — Mapa + GPS real:** `flutter_map` + tiles OSM. Rider envía heartbeats automáticos vía `geolocator` (throttle por tiempo+distancia). Mapa del jefe (`/d/map`) muestra markers vivos.
- **2026-05-27 — 3 surfaces por rol:** comercio, jefe, rider con role-aware routing. Antes era todo placeholder.
- **2026-05-27 — Auth + role bootstrap:** profile + role enum, redirect según rol, signup con selector "Soy rider / Soy comercio".
- **2026-05-26 — Fase 1 (backend completo):** 16 migraciones iniciales, RLS, 5 edge functions deployadas (dispatch-order, offer-respond, expire-offers, rider-heartbeat, order-status).

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
6. **Código que pisa Web APIs vive en `*_web.dart`** y se importa con conditional
   imports (`if (dart.library.js_interop)`). En mobile carga el stub equivalente
   (`*_stub.dart`). Si tocás una de estas, recordá mantener la otra al día.
7. **Convención de versión APK:** `gh release create vX.Y.Z dist/app-release.apk`.
   Cada bump tiene release notes con los cambios visibles al usuario.
8. **El secret de GitHub Actions se llama `ENV_FILE`** y guarda el `.env` completo.
   Si rotás claves de Supabase, hay que actualizar ahí también.
