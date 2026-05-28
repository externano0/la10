/// Tracking en vivo del rider asignado a una orden, para el jefe.
///
/// Muestra:
///  - Marker animado del rider con su posición actual (realtime via Supabase).
///  - Pin pickup (naranja) y dropoff (verde).
///  - Polyline de la ruta real del rider hacia el siguiente waypoint:
///      * Si la orden está `assigned`  → ruta rider → pickup.
///      * Si la orden está `picked_up` → ruta rider → dropoff.
///  - Si OSRM no contesta a tiempo, fallback a línea recta.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:la10_core/la10_core.dart';
import 'package:la10_data/la10_data.dart';
import 'package:la10_geo/la10_geo.dart' as geo;
import 'package:latlong2/latlong.dart';

final _riderLocationsStreamProvider =
    StreamProvider<List<RiderLocation>>((ref) {
  return RidersRepository.instance.watchAllLocations();
});

final _osrmClientProvider = Provider<geo.OsrmClient>((_) {
  return geo.OsrmClient(baseUrl: Env.osrmBaseUrl);
});

final _osrmRouteProvider =
    FutureProvider.family<List<LatLng>?, ({LatLng from, LatLng to})>((ref, p) async {
  final c = ref.read(_osrmClientProvider);
  final r = await c.route(
    geo.LatLng(p.from.latitude, p.from.longitude),
    geo.LatLng(p.to.latitude, p.to.longitude),
  );
  return r?.geometry.map((g) => LatLng(g.lat, g.lng)).toList();
});

class OrderTrackingMap extends ConsumerWidget {
  const OrderTrackingMap({super.key, required this.order});
  final OrderRow order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPickup = order.pickupLat != null && order.pickupLng != null;
    final hasDropoff = order.dropoffLat != null && order.dropoffLng != null;
    final pickup = hasPickup ? LatLng(order.pickupLat!, order.pickupLng!) : null;
    final dropoff = hasDropoff ? LatLng(order.dropoffLat!, order.dropoffLng!) : null;

    // Ubicación realtime del rider asignado (si hay).
    LatLng? riderLatLng;
    if (order.assignedRiderId != null) {
      final locs = ref.watch(_riderLocationsStreamProvider).asData?.value ?? const [];
      final me = locs.where((l) => l.riderId == order.assignedRiderId).firstOrNull;
      if (me != null) riderLatLng = LatLng(me.lat, me.lng);
    }

    // Decidir el target de la ruta según el estado.
    LatLng? target;
    if (order.status == 'assigned') target = pickup;
    if (order.status == 'picked_up') target = dropoff;

    final routeAsync = (riderLatLng != null && target != null)
        ? ref.watch(_osrmRouteProvider((from: riderLatLng, to: target)))
        : null;
    final routePoints = routeAsync?.asData?.value;

    final center = riderLatLng ?? pickup ?? dropoff ?? const LatLng(-34.6037, -58.3816);

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: 14,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.la10.app',
          maxZoom: 19,
        ),
        if (riderLatLng != null && target != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: routePoints ?? [riderLatLng, target],
                color: Colors.blue,
                strokeWidth: 4,
              ),
            ],
          )
        else if (pickup != null && dropoff != null)
          // Sin rider asignado: mostramos ruta entera pickup → dropoff como referencia.
          PolylineLayer(
            polylines: [
              Polyline(
                points: [pickup, dropoff],
                color: Colors.grey,
                strokeWidth: 3,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (pickup != null)
              Marker(
                point: pickup,
                width: 40,
                height: 40,
                child: const _Pin(color: Colors.orange, icon: Icons.store),
              ),
            if (dropoff != null)
              Marker(
                point: dropoff,
                width: 40,
                height: 40,
                child: const _Pin(color: Colors.green, icon: Icons.home),
              ),
            if (riderLatLng != null)
              Marker(
                point: riderLatLng,
                width: 44,
                height: 44,
                child: const _Pin(color: Colors.blue, icon: Icons.two_wheeler),
              ),
          ],
        ),
      ],
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.color, required this.icon});
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }
}
