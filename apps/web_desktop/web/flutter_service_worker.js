// Kill-switch service worker.
//
// Hasta v0.1.12 servíamos un SW generado por Flutter que cacheaba el bundle
// agresivamente. Después de cada deploy a Vercel los users seguían viendo
// UI vieja porque el SW interceptaba el HTML antes de pegarle al server.
// El snippet de unregister en index.html no alcanzaba porque el SW
// servía el index.html viejo (sin el snippet).
//
// Este archivo se publica al PATH del SW viejo. Cuando el browser
// chequea por update (cada 24h o al navegar), se topa con este byte
// diferente → instala este SW → activa → borra caches → unregistera →
// recarga clients. Al siguiente load el browser tira fetch normal al
// server y baja el bundle nuevo. Una sola vez por user.
//
// Combinamos con `flutter build web --pwa-strategy=none` para que el
// build no genere uno nuevo encima.

self.addEventListener('install', (event) => {
  // Skipea el wait state para activar inmediatamente.
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    // Borrar todos los caches que el SW viejo dejó.
    const keys = await caches.keys();
    await Promise.all(keys.map((k) => caches.delete(k)));
    // Forzar a todos los clients abiertos a recargar — toman el bundle fresco.
    const clients = await self.clients.matchAll({ type: 'window' });
    for (const client of clients) {
      try {
        client.navigate(client.url);
      } catch (_) {
        // Algunos browsers no permiten navigate; el unregister + reload manual alcanza.
      }
    }
    // Desregistrar este SW para que futuros loads sean fetch directo al server.
    await self.registration.unregister();
  })());
});

// No intercept fetches — pasamos todo al network.
self.addEventListener('fetch', (event) => {
  // Default behavior: dejarlo pasar.
});
