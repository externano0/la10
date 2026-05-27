import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:la10_data/la10_data.dart';
import 'package:latlong2/latlong.dart';

import 'riders_list.dart';

final riderLocationsStreamProvider =
    StreamProvider<List<RiderLocation>>((ref) {
  return RidersRepository.instance.watchAllLocations();
});

final activeOrdersStreamProvider = StreamProvider<List<OrderRow>>((ref) {
  return OrdersRepository.instance.watchAll();
});

const _caba = LatLng(-34.6037, -58.3816);

class DispatchMap extends ConsumerStatefulWidget {
  const DispatchMap({super.key, this.focusRiderId});

  /// Si viene seteado, el mapa abre centrado y zoomeado sobre ese rider.
  /// Se usa desde el botón "Localizar en mapa" de la lista de riders.
  final String? focusRiderId;

  @override
  ConsumerState<DispatchMap> createState() => _DispatchMapState();
}

class _DispatchMapState extends ConsumerState<DispatchMap> {
  final _ctl = MapController();
  bool _focusedOnce = false;

  void _maybeFocus(List<RiderLocation> locs) {
    if (_focusedOnce || widget.focusRiderId == null) return;
    final target = locs.where((r) => r.riderId == widget.focusRiderId).firstOrNull;
    if (target == null) return;
    _focusedOnce = true;
    // Esperamos un frame para que el MapController esté montado.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ctl.move(LatLng(target.lat, target.lng), 15);
    });
  }

  @override
  Widget build(BuildContext context) {
    final riders = ref.watch(riderLocationsStreamProvider);
    final orders = ref.watch(activeOrdersStreamProvider);
    final ridersIndex = ref.watch(ridersStreamProvider);

    _maybeFocus(riders.asData?.value ?? const []);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa en vivo'),
        leading: BackButton(onPressed: () => context.go('/d/home')),
      ),
      body: FlutterMap(
        mapController: _ctl,
        options: const MapOptions(
          initialCenter: _caba,
          initialZoom: 12,
          interactionOptions: InteractionOptions(
            flags: InteractiveFlag.pinchZoom |
                InteractiveFlag.drag |
                InteractiveFlag.doubleTapZoom |
                InteractiveFlag.scrollWheelZoom,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.la10.app',
            maxZoom: 19,
          ),
          MarkerLayer(
            markers: [
              ..._buildOrderMarkers(orders.asData?.value ?? const []),
              ..._buildRiderMarkers(
                riders.asData?.value ?? const [],
                ridersIndex.asData?.value ?? const [],
                context,
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Marker> _buildRiderMarkers(
    List<RiderLocation> locs,
    List<Rider> ridersList,
    BuildContext context,
  ) {
    final byId = {for (final r in ridersList) r.userId: r};
    return locs.map((rl) {
      final r = byId[rl.riderId];
      final color = switch (r?.status) {
        'available' => Colors.green,
        'on_delivery' => Colors.blue,
        'paused' => Colors.orange,
        _ => Colors.grey,
      };
      return Marker(
        point: LatLng(rl.lat, rl.lng),
        width: 44,
        height: 44,
        child: Tooltip(
          message: '${r?.displayName ?? rl.riderId} · ${r?.status ?? '—'}',
          child: Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
            ),
            child: const Icon(Icons.two_wheeler, color: Colors.white, size: 22),
          ),
        ),
      );
    }).toList();
  }

  List<Marker> _buildOrderMarkers(List<OrderRow> orders) {
    final live = orders.where((o) =>
        o.pickupLat != null &&
        o.pickupLng != null &&
        const {
          'pending_assignment',
          'offered',
          'assigned',
          'picked_up',
        }.contains(o.status));
    return live.map((o) {
      final color = switch (o.status) {
        'pending_assignment' => Colors.orange,
        'offered' => Colors.amber,
        'assigned' => Colors.blue,
        'picked_up' => Colors.indigo,
        _ => Colors.grey,
      };
      return Marker(
        point: LatLng(o.pickupLat!, o.pickupLng!),
        width: 36,
        height: 36,
        child: Tooltip(
          message: '${o.customerName} · ${o.status}',
          child: Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(Icons.storefront, color: Colors.white, size: 18),
          ),
        ),
      );
    }).toList();
  }
}
