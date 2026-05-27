import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:la10_data/la10_data.dart';

final orderByIdProvider = FutureProvider.family<OrderRow?, String>((ref, id) async {
  return OrdersRepository.instance.getById(id);
});

final orderEventsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, id) async {
  return OrdersRepository.instance.eventsFor(id);
});

final allRidersProvider = FutureProvider<List<Rider>>((ref) async {
  return RidersRepository.instance.listAll();
});

class OrderDetail extends ConsumerWidget {
  const OrderDetail({required this.id, super.key});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(orderByIdProvider(id));
    final events = ref.watch(orderEventsProvider(id));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de orden'),
        leading: BackButton(onPressed: () => context.go('/d/home')),
      ),
      body: order.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (o) {
          if (o == null) return const Center(child: Text('No encontrada'));
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.customerName, style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text('Estado: ${o.status}'),
                        const SizedBox(height: 12),
                        Text('Pickup: ${o.pickupAddress}'),
                        Text('Dropoff: ${o.dropoffAddress}'),
                        if (o.totalAmountCents != null) ...[
                          const SizedBox(height: 8),
                          Text('Monto: ${(o.totalAmountCents! / 100).toStringAsFixed(2)} ${o.currency ?? "ARS"}'),
                        ],
                        if (o.assignedRiderId != null) ...[
                          const SizedBox(height: 8),
                          Text('Rider asignado: ${o.assignedRiderId}'),
                        ],
                        const SizedBox(height: 16),
                        if (['pending_assignment','offered'].contains(o.status))
                          FilledButton.icon(
                            onPressed: () => _showManualAssign(context, ref, o.id),
                            icon: const Icon(Icons.person_pin),
                            label: const Text('Reasignar manualmente'),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Línea de tiempo', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                events.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Error: $e'),
                  data: (evs) => Column(
                    children: evs.map((e) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.timeline),
                        title: Text('${e['from_status']} → ${e['to_status']}'),
                        subtitle: Text(DateTime.parse(e['created_at'] as String).toLocal().toString()),
                      ),
                    )).toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showManualAssign(BuildContext context, WidgetRef ref, String orderId) async {
    // Fuerza un fetch fresco — si un rider nuevo se acaba de registrar,
    // queremos que aparezca acá sin tener que reiniciar la app.
    ref.invalidate(allRidersProvider);
    final riders = await ref.read(allRidersProvider.future);
    if (!context.mounted) return;
    // Mostramos TODOS los riders activos (no sólo los `available`):
    // - El jefe puede querer despertar a uno offline para una urgencia.
    // - Los nuevos se registran con status='offline' y eran invisibles antes.
    // Ordenamos available primero, después paused, después offline.
    int rank(String s) => switch (s) {
          'available' => 0,
          'on_delivery' => 1,
          'paused' => 2,
          _ => 3,
        };
    final candidates = riders.where((r) => r.isActive).toList()
      ..sort((a, b) => rank(a.status).compareTo(rank(b.status)));
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Elegí rider'),
        children: candidates.isEmpty
            ? [const Padding(padding: EdgeInsets.all(16), child: Text('Todavía no hay riders activos'))]
            : candidates.map((r) {
                final dotColor = switch (r.status) {
                  'available' => Colors.green,
                  'on_delivery' => Colors.blue,
                  'paused' => Colors.orange,
                  _ => Colors.grey,
                };
                return SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, r.userId),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('${r.displayName} (${r.vehicleType})'),
                      ),
                      Text(r.status, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                );
              }).toList(),
      ),
    );
    if (picked == null) return;
    try {
      await DispatchRepository.instance.manualAssign(orderId: orderId, riderId: picked);
      ref.invalidate(orderByIdProvider(orderId));
      ref.invalidate(orderEventsProvider(orderId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Oferta enviada al rider')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}
