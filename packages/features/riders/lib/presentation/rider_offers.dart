/// Pantalla de ofertas pendientes del rider.
/// Se usa como fallback cuando el popup full-screen se cerró (TTL vencido,
/// app reabierta, etc) — muestra las ofertas todavía pendientes y permite
/// aceptar/rechazar.
///
/// Después de aceptar, navegamos a /r/orders/:orderId para que el rider vea
/// la información del pedido (mapa, dirección, monto). Antes esta screen
/// solo mostraba un snackbar y el rider se quedaba sin saber qué hacer.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:la10_data/la10_data.dart';

import 'rider_home.dart';

final myOffersStreamProvider = StreamProvider<List<Offer>>((ref) {
  return OffersRepository.instance.watchMyPending();
});

/// Cargamos el detalle de la orden de cada oferta para mostrar info útil
/// (dirección y monto) en vez de solo el UUID.
final _orderForOfferProvider =
    FutureProvider.family<OrderRow?, String>((ref, orderId) async {
  return OrdersRepository.instance.getById(orderId);
});

class RiderOffers extends ConsumerWidget {
  const RiderOffers({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myOffersStreamProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ofertas'),
        leading: BackButton(onPressed: () => context.go('/r/home')),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (offers) {
          if (offers.isEmpty) {
            return const Center(child: Text('Sin ofertas pendientes'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: offers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _OfferCard(offer: offers[i]),
          );
        },
      ),
    );
  }
}

class _OfferCard extends ConsumerWidget {
  const _OfferCard({required this.offer});
  final Offer offer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remaining = offer.expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 999);
    final expired = remaining == 0;
    final asyncOrder = ref.watch(_orderForOfferProvider(offer.orderId));
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            asyncOrder.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => Text('Orden ${offer.orderId.substring(0, 8)}'),
              data: (o) {
                if (o == null) return Text('Orden ${offer.orderId.substring(0, 8)}');
                final money = o.totalAmountCents == null
                    ? '—'
                    : '${(o.totalAmountCents! / 100).toStringAsFixed(0)} ${o.currency ?? 'ARS'}';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(money,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                        )),
                    const SizedBox(height: 4),
                    Text('Retirar: ${o.pickupAddress}'),
                    Text('Entregar: ${o.dropoffAddress}'),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              expired ? 'Vencida' : 'Expira en ${remaining}s',
              style: TextStyle(
                color: expired ? Colors.red : cs.outline,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Aceptar'),
                    onPressed: expired ? null : () => _accept(context, ref),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.close),
                    label: const Text('Rechazar'),
                    onPressed: expired ? null : () => _reject(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _accept(BuildContext context, WidgetRef ref) async {
    try {
      await OffersRepository.instance.respond(offer.id, 'accepted');
      ref.invalidate(myRiderProvider);
      if (!context.mounted) return;
      // Llevamos al rider directo al detalle del pedido aceptado. Sin esto
      // se quedaba en la lista y no veía la información — era el bug reportado.
      context.go('/r/orders/${offer.orderId}');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _reject(BuildContext context) async {
    try {
      await OffersRepository.instance.respond(offer.id, 'declined');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}
