import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:la10_auth/la10_auth.dart';
import 'package:la10_data/la10_data.dart';

import 'fcm_service.dart';
import 'offer_alert_guard.dart';
import 'offer_ringtone.dart';
import 'rider_gps_tracker.dart';

/// Provider que registra el token FCM una vez, después del login del rider.
/// Idempotente: si ya está registrado, hace upsert sin efecto.
final _fcmRegisteredProvider = FutureProvider<void>((ref) async {
  await registerFcmToken();
});

final myRiderProvider = FutureProvider<Rider?>((ref) async {
  return RidersRepository.instance.me();
});

class RiderHome extends ConsumerWidget {
  const RiderHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myRiderProvider);
    // Dispara el registro del token FCM la primera vez que se renderiza
    // el home del rider. Si falla (sin red, sin permisos) no rompe la UI.
    ref.watch(_fcmRegisteredProvider);
    return OfferAlertGuard(
      child: _buildScaffold(context, ref, me),
    );
  }

  Widget _buildScaffold(BuildContext context, WidgetRef ref, AsyncValue<Rider?> me) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('La 10 — Rider'),
        actions: [
          IconButton(
            tooltip: 'Probar sirena de oferta',
            icon: const Icon(Icons.volume_up),
            onPressed: () {
              OfferRingtone.instance.warmUp();
              OfferRingtone.instance.play();
            },
          ),
          IconButton(
            tooltip: 'Ofertas',
            icon: const Icon(Icons.notifications),
            onPressed: () => context.push('/r/offers'),
          ),
          IconButton(
            tooltip: 'Chat con el dispatch',
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => context.push('/r/chat'),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await AuthActions.instance.signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: me.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rider) {
          if (rider == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.two_wheeler, size: 64),
                    const SizedBox(height: 16),
                    const Text('Aún no estás registrado como rider'),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () async {
                        await RidersRepository.instance.ensureSelf(
                          displayName: AuthActions.instance.toString(),
                        );
                        ref.invalidate(myRiderProvider);
                      },
                      child: const Text('Activarme como rider'),
                    ),
                  ],
                ),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(rider.displayName, style: Theme.of(context).textTheme.titleLarge),
                        Text(rider.vehicleType),
                        const SizedBox(height: 12),
                        Text('Estado actual: ${rider.status}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Cambiar disponibilidad', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _StatusBtn(current: rider.status, target: 'available', label: 'Disponible', color: Colors.green, ref: ref),
                    _StatusBtn(current: rider.status, target: 'paused', label: 'Pausado', color: Colors.orange, ref: ref),
                    _StatusBtn(current: rider.status, target: 'offline', label: 'Offline', color: Colors.grey, ref: ref),
                  ],
                ),
                const SizedBox(height: 16),
                const RiderGpsTracker(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusBtn extends StatelessWidget {
  const _StatusBtn({required this.current, required this.target, required this.label, required this.color, required this.ref});
  final String current;
  final String target;
  final String label;
  final Color color;
  final WidgetRef ref;
  @override
  Widget build(BuildContext context) {
    final selected = current == target;
    return FilledButton.tonal(
      style: FilledButton.styleFrom(
        backgroundColor: selected ? color : null,
        foregroundColor: selected ? Colors.white : null,
      ),
      onPressed: selected
          ? null
          : () async {
              // Habilita audio para que el ringtone de oferta suene después.
              // El browser exige un gesture del user para autorizar audio.
              OfferRingtone.instance.warmUp();
              await RidersRepository.instance.updateStatus(target);
              ref.invalidate(myRiderProvider);
            },
      child: Text(label),
    );
  }
}
