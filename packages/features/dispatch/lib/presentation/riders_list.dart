/// Listado de riders para el jefe. Realtime sobre la tabla `riders`.
/// Cada fila tiene tres acciones rápidas:
///   1. 🗺️ Localizar  → abre el mapa centrado en su última ubicación.
///   2. 📞 Llamar     → dispara el dialer del dispositivo (tel: link).
///   3. 💬 Mensaje    → abre el chat interno con el rider.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:la10_data/la10_data.dart';
import 'package:url_launcher/url_launcher.dart';

final ridersStreamProvider = StreamProvider<List<Rider>>((ref) {
  return RidersRepository.instance.watchAll();
});

class RidersList extends ConsumerWidget {
  const RidersList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ridersStreamProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riders'),
        leading: BackButton(onPressed: () => context.go('/d/home')),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (riders) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: riders.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) => _RiderCard(rider: riders[i]),
        ),
      ),
    );
  }
}

class _RiderCard extends StatelessWidget {
  const _RiderCard({required this.rider});
  final Rider rider;

  Color get _statusColor => switch (rider.status) {
        'available' => Colors.green,
        'on_delivery' => Colors.blue,
        'paused' => Colors.orange,
        _ => Colors.grey,
      };

  Future<void> _call(BuildContext context) async {
    final phone = rider.phone;
    if (phone == null || phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este rider no cargó un teléfono.')),
      );
      return;
    }
    // tel: launches the device dialer. On desktop / web suele no estar soportado;
    // en ese caso mostramos el número para que el usuario lo copie.
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Teléfono: $phone')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _statusColor,
                  child: const Icon(Icons.two_wheeler, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rider.displayName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text('${rider.vehicleType} · ${rider.status}'),
                    ],
                  ),
                ),
                if (!rider.isActive) const Chip(label: Text('Inactivo')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/d/map/rider/${rider.userId}'),
                    icon: const Icon(Icons.location_on_outlined),
                    label: const Text('Localizar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _call(context),
                    icon: const Icon(Icons.call),
                    label: const Text('Llamar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => context.push(
                      '/d/chat/${rider.userId}?name=${Uri.encodeComponent(rider.displayName)}',
                    ),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Mensaje'),
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
