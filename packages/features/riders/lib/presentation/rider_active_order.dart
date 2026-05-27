/// Pantalla del rider para una orden activa.
/// Muestra: mapa con pickup→dropoff, datos del cliente, monto y los botones
/// "Retiré" → "Entregué" según el estado actual.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:la10_data/la10_data.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

final activeOrderProvider =
    FutureProvider.family<OrderRow?, String>((ref, id) async {
  return OrdersRepository.instance.getById(id);
});

class RiderActiveOrder extends ConsumerWidget {
  const RiderActiveOrder({super.key, required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(activeOrderProvider(orderId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedido activo'),
        leading: BackButton(onPressed: () => context.go('/r/home')),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (o) {
          if (o == null) return const Center(child: Text('No encontrada'));
          return _OrderView(order: o, onChange: () {
            ref.invalidate(activeOrderProvider(orderId));
          });
        },
      ),
    );
  }
}

class _OrderView extends StatelessWidget {
  const _OrderView({required this.order, required this.onChange});
  final OrderRow order;
  final VoidCallback onChange;

  bool get _hasPickup => order.pickupLat != null && order.pickupLng != null;
  bool get _hasDropoff => order.dropoffLat != null && order.dropoffLng != null;

  Future<void> _openMaps(double lat, double lng) async {
    // Abre la app de mapas nativa con la dirección. Universal: funciona en
    // Google Maps, Apple Maps, Waze (según lo que el OS prefiera).
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _transition(BuildContext context, String to) async {
    try {
      await OrdersRepository.instance.transition(order.id, to);
      onChange();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Estado actualizado: $to')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        // Mapa con pickup y dropoff.
        SizedBox(
          height: 220,
          child: _MiniMap(
            pickup: _hasPickup ? LatLng(order.pickupLat!, order.pickupLng!) : null,
            dropoff:
                _hasDropoff ? LatLng(order.dropoffLat!, order.dropoffLng!) : null,
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MoneyCard(
                  cents: order.totalAmountCents,
                  currency: order.currency ?? 'ARS',
                  status: order.status,
                ),
                const SizedBox(height: 12),
                _AddressCard(
                  icon: Icons.store,
                  iconColor: Colors.orange,
                  title: 'Retirar en',
                  address: order.pickupAddress,
                  onOpenMaps: _hasPickup
                      ? () => _openMaps(order.pickupLat!, order.pickupLng!)
                      : null,
                ),
                const SizedBox(height: 8),
                _AddressCard(
                  icon: Icons.home,
                  iconColor: Colors.green,
                  title: 'Entregar a',
                  subtitle: order.customerName,
                  address: order.dropoffAddress,
                  phone: order.customerPhone,
                  onOpenMaps: _hasDropoff
                      ? () => _openMaps(order.dropoffLat!, order.dropoffLng!)
                      : null,
                ),
                if (order.notes != null && order.notes!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Card(
                    color: cs.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.note_alt_outlined),
                          const SizedBox(width: 8),
                          Expanded(child: Text(order.notes!)),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _ActionButton(status: order.status, onPressed: (to) => _transition(context, to)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniMap extends StatelessWidget {
  const _MiniMap({this.pickup, this.dropoff});
  final LatLng? pickup;
  final LatLng? dropoff;

  @override
  Widget build(BuildContext context) {
    final center = pickup ?? dropoff ?? const LatLng(-34.6037, -58.3816);
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
        if (pickup != null && dropoff != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [pickup!, dropoff!],
                color: Colors.indigo,
                strokeWidth: 4,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (pickup != null)
              Marker(
                point: pickup!,
                width: 44,
                height: 44,
                child: const _Pin(color: Colors.orange, icon: Icons.store),
              ),
            if (dropoff != null)
              Marker(
                point: dropoff!,
                width: 44,
                height: 44,
                child: const _Pin(color: Colors.green, icon: Icons.home),
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

class _MoneyCard extends StatelessWidget {
  const _MoneyCard({this.cents, required this.currency, required this.status});
  final int? cents;
  final String currency;
  final String status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final money = cents == null ? '—' : (cents! / 100).toStringAsFixed(2);
    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.attach_money, color: cs.onPrimaryContainer, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$money $currency',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    'Estado: $status',
                    style: TextStyle(color: cs.onPrimaryContainer),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.address,
    this.subtitle,
    this.phone,
    this.onOpenMaps,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final String address;
  final String? phone;
  final VoidCallback? onOpenMaps;

  Future<void> _call() async {
    final p = phone;
    if (p == null) return;
    final uri = Uri(scheme: 'tel', path: p);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(backgroundColor: iconColor, child: Icon(icon, color: Colors.white)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.labelLarge),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      const SizedBox(height: 2),
                      Text(address),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (onOpenMaps != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onOpenMaps,
                      icon: const Icon(Icons.navigation),
                      label: const Text('Ir'),
                    ),
                  ),
                if (phone != null && phone!.trim().isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _call,
                      icon: const Icon(Icons.call),
                      label: const Text('Llamar'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.status, required this.onPressed});
  final String status;
  final void Function(String) onPressed;

  @override
  Widget build(BuildContext context) {
    // assigned → picked_up → delivered. Damos un solo botón grande según el paso.
    if (status == 'assigned') {
      return FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          backgroundColor: Colors.orange,
        ),
        onPressed: () => onPressed('picked_up'),
        icon: const Icon(Icons.shopping_bag),
        label: const Text('Retiré el pedido', style: TextStyle(fontSize: 16)),
      );
    }
    if (status == 'picked_up') {
      return FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          backgroundColor: Colors.green,
        ),
        onPressed: () => onPressed('delivered'),
        icon: const Icon(Icons.check_circle),
        label: const Text('Entregué', style: TextStyle(fontSize: 16)),
      );
    }
    return const SizedBox.shrink();
  }
}
