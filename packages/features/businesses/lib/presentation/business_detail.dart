import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:la10_data/la10_data.dart';

final businessByIdProvider = FutureProvider.family<Business?, String>((ref, id) async {
  return BusinessesRepository.instance.getById(id);
});

final ordersForBusinessProvider =
    FutureProvider.family<List<OrderRow>, String>((ref, businessId) async {
  return OrdersRepository.instance.listForBusiness(businessId);
});

class BusinessDetail extends ConsumerWidget {
  const BusinessDetail({required this.id, super.key});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final biz = ref.watch(businessByIdProvider(id));
    final orders = ref.watch(ordersForBusinessProvider(id));
    return Scaffold(
      appBar: AppBar(
        title: biz.maybeWhen(data: (b) => Text(b?.name ?? 'Negocio'), orElse: () => const Text('Negocio')),
        leading: BackButton(onPressed: () => context.go('/b/home')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/b/businesses/$id/orders/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nueva orden'),
      ),
      body: orders.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('Aún no hay órdenes'));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(ordersForBusinessProvider(id)),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final o = list[i];
                return Card(
                  child: ListTile(
                    title: Text('${o.customerName} → ${o.dropoffAddress}'),
                    subtitle: Text('Estado: ${o.status}  ·  ${o.createdAt.toLocal()}'),
                    trailing: _StatusChip(status: o.status),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'draft' => Colors.grey,
      'pending_assignment' => Colors.orange,
      'offered' => Colors.amber,
      'assigned' => Colors.blue,
      'picked_up' => Colors.indigo,
      'delivered' => Colors.green,
      'cancelled' => Colors.red,
      _ => Colors.grey,
    };
    return Chip(
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color),
      label: Text(status, style: TextStyle(color: color)),
    );
  }
}
