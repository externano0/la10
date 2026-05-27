/// Popup modal full-screen para una oferta entrante.
///
/// Cuando llega una oferta nueva, abrimos este dialog que NO se puede cerrar
/// tocando afuera. Muestra:
///   - Direcciones pickup + dropoff
///   - Monto y notas
///   - Countdown del TTL (barra que se vacía)
///   - Aceptar (verde grande) y Rechazar (rojo)
/// Cuando el TTL se vence, el dialog se auto-cierra.
/// Si el rider acepta, navega a /r/orders/:id.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:la10_data/la10_data.dart';
import 'package:latlong2/latlong.dart';

Future<void> showOfferPopup(BuildContext context, Offer offer) async {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _OfferDialog(offer: offer),
  );
}

class _OfferDialog extends ConsumerStatefulWidget {
  const _OfferDialog({required this.offer});
  final Offer offer;

  @override
  ConsumerState<_OfferDialog> createState() => _OfferDialogState();
}

class _OfferDialogState extends ConsumerState<_OfferDialog> {
  Timer? _tick;
  Duration _remaining = Duration.zero;
  late Duration _total;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _remaining = widget.offer.expiresAt.difference(now);
    if (_remaining.isNegative) _remaining = Duration.zero;
    _total = _remaining;
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      final left = widget.offer.expiresAt.difference(DateTime.now());
      if (left.isNegative || left == Duration.zero) {
        _tick?.cancel();
        if (mounted) Navigator.of(context).pop();
        return;
      }
      setState(() => _remaining = left);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _respond(String response) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    // La edge fn espera 'accepted' o 'declined'.
    final apiValue = response == 'accept' ? 'accepted' : 'declined';
    try {
      await OffersRepository.instance.respond(widget.offer.id, apiValue);
      if (!mounted) return;
      Navigator.of(context).pop();
      if (response == 'accept') {
        context.push('/r/orders/${widget.offer.orderId}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(_orderProvider(widget.offer.orderId));
    final progress =
        _total.inMilliseconds == 0 ? 0.0 : _remaining.inMilliseconds / _total.inMilliseconds;
    final cs = Theme.of(context).colorScheme;

    return Dialog.fullscreen(
      child: SafeArea(
        child: Column(
          children: [
            // Barra de countdown.
            LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 8,
              color: _remaining.inSeconds <= 5 ? Colors.red : Colors.amber,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.local_shipping, size: 32, color: cs.primary),
                  const SizedBox(width: 12),
                  Text(
                    '¡Nueva oferta!',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _remaining.inSeconds <= 5 ? Colors.red : cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_remaining.inSeconds}s',
                      style: TextStyle(
                        color: _remaining.inSeconds <= 5 ? Colors.white : cs.onSecondaryContainer,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: order.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (o) {
                  if (o == null) {
                    return const Center(child: Text('No se pudo cargar el pedido'));
                  }
                  final pickup = (o.pickupLat != null && o.pickupLng != null)
                      ? LatLng(o.pickupLat!, o.pickupLng!) : null;
                  final dropoff = (o.dropoffLat != null && o.dropoffLng != null)
                      ? LatLng(o.dropoffLat!, o.dropoffLng!) : null;
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _MoneyBig(
                          cents: o.totalAmountCents,
                          currency: o.currency ?? 'ARS',
                        ),
                        const SizedBox(height: 12),
                        if (pickup != null || dropoff != null) ...[
                          SizedBox(
                            height: 180,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: _OfferMiniMap(pickup: pickup, dropoff: dropoff),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        _Row(icon: Icons.store, color: Colors.orange,
                          title: 'Retirar en', body: o.pickupAddress),
                        const SizedBox(height: 8),
                        _Row(icon: Icons.home, color: Colors.green,
                          title: 'Entregar a ${o.customerName}',
                          body: o.dropoffAddress),
                        if ((o.notes ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _Row(icon: Icons.note_alt_outlined, color: cs.outline,
                            title: 'Notas', body: o.notes!),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_error!, style: TextStyle(color: cs.error)),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(60),
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red, width: 2),
                      ),
                      onPressed: _busy ? null : () => _respond('reject'),
                      icon: const Icon(Icons.close),
                      label: const Text('Rechazar', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(60),
                        backgroundColor: Colors.green,
                      ),
                      onPressed: _busy ? null : () => _respond('accept'),
                      icon: _busy
                          ? const SizedBox(height: 20, width: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.check),
                      label: const Text('Aceptar', style: TextStyle(fontSize: 20)),
                    ),
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

final _orderProvider = FutureProvider.family<OrderRow?, String>((ref, id) async {
  return OrdersRepository.instance.getById(id);
});

class _MoneyBig extends StatelessWidget {
  const _MoneyBig({this.cents, required this.currency});
  final int? cents;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final money = cents == null ? '—' : (cents! / 100).toStringAsFixed(2);
    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            '$money $currency',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: cs.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}

class _OfferMiniMap extends StatelessWidget {
  const _OfferMiniMap({this.pickup, this.dropoff});
  final LatLng? pickup;
  final LatLng? dropoff;

  @override
  Widget build(BuildContext context) {
    final center = pickup ?? dropoff ?? const LatLng(-34.6037, -58.3816);
    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: 13,
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
                width: 36,
                height: 36,
                child: const _MapPin(color: Colors.orange, icon: Icons.store),
              ),
            if (dropoff != null)
              Marker(
                point: dropoff!,
                width: 36,
                height: 36,
                child: const _MapPin(color: Colors.green, icon: Icons.home),
              ),
          ],
        ),
      ],
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.color, required this.icon});
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.color, required this.title, required this.body});
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(backgroundColor: color, child: Icon(icon, color: Colors.white)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(body, style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
