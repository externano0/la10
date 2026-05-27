import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:la10_data/la10_data.dart';

import 'rider_home.dart';

final myOffersStreamProvider = StreamProvider<List<Offer>>((ref) {
  return OffersRepository.instance.watchMyPending();
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
            itemBuilder: (context, i) => _OfferCard(offer: offers[i], ref: ref),
          );
        },
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer, required this.ref});
  final Offer offer;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final remaining = offer.expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 999);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Orden ${offer.orderId.substring(0, 8)}'),
            Text('Expira en ${remaining}s'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Aceptar'),
                    onPressed: () async {
                      try {
                        await OffersRepository.instance.respond(offer.id, 'accepted');
                        ref.invalidate(myRiderProvider);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Orden aceptada')));
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.close),
                    label: const Text('Rechazar'),
                    onPressed: () async {
                      try {
                        await OffersRepository.instance.respond(offer.id, 'declined');
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
