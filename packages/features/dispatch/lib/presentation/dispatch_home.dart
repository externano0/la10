import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:la10_auth/la10_auth.dart';
import 'package:la10_data/la10_data.dart';

final allOrdersStreamProvider = StreamProvider<List<OrderRow>>((ref) {
  return OrdersRepository.instance.watchAll();
});

class DispatchHome extends ConsumerWidget {
  const DispatchHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allOrdersStreamProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispatch — La 10'),
        actions: [
          IconButton(
            tooltip: 'Mapa en vivo',
            icon: const Icon(Icons.map),
            onPressed: () => context.push('/d/map'),
          ),
          IconButton(
            tooltip: 'Riders',
            icon: const Icon(Icons.two_wheeler),
            onPressed: () => context.push('/d/riders'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              await AuthActions.instance.signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (orders) {
          final counts = _countByStatus(orders);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _Stat(label: 'Pendientes', value: counts['pending_assignment'] ?? 0, color: Colors.orange),
                    _Stat(label: 'Ofertadas', value: counts['offered'] ?? 0, color: Colors.amber),
                    _Stat(label: 'Asignadas', value: counts['assigned'] ?? 0, color: Colors.blue),
                    _Stat(label: 'En camino', value: counts['picked_up'] ?? 0, color: Colors.indigo),
                    _Stat(label: 'Entregadas hoy', value: counts['delivered'] ?? 0, color: Colors.green),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final o = orders[i];
                    return Card(
                      child: ListTile(
                        title: Text('${o.customerName} → ${o.dropoffAddress}'),
                        subtitle: Text('${o.status} · ${o.createdAt.toLocal()}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/d/orders/${o.id}'),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Map<String, int> _countByStatus(List<OrderRow> orders) {
    final m = <String, int>{};
    for (final o in orders) {
      m[o.status] = (m[o.status] ?? 0) + 1;
    }
    return m;
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}
