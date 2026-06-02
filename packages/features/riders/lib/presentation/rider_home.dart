import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:la10_auth/la10_auth.dart';
import 'package:la10_data/la10_data.dart';

import 'fcm_service.dart';
import 'offer_alert_guard.dart';
import 'offer_ringtone.dart';
import 'online_mode_sheet.dart';
import 'rider_gps_tracker.dart';

/// Provider que registra el token FCM una vez, después del login del rider.
/// Idempotente: si ya está registrado, hace upsert sin efecto.
final _fcmRegisteredProvider = FutureProvider<void>((ref) async {
  await registerFcmToken();
});

final myRiderProvider = FutureProvider<Rider?>((ref) async {
  return RidersRepository.instance.me();
});

/// Stream del pedido activo del rider. Se usa para renderear el card
/// "Continuar pedido" en rider_home — escotilla de emergencia para
/// llegar a /r/orders/{id} cuando el callkit accept no logro navegar
/// (caso OEM agresivo / cache de eventos perdido / etc).
final _myActiveOrderProvider = StreamProvider<OrderRow?>((ref) async* {
  final rider = await RidersRepository.instance.me();
  if (rider == null) {
    yield null;
    return;
  }
  yield* OrdersRepository.instance.watchMyActive(rider.riderId);
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
                // Card de "Continuar pedido activo" — solo aparece si el
                // rider tiene una orden asignada o picked_up. Es el fallback
                // visible para llegar al detalle del pedido si por algun
                // motivo el callkit accept no logro navegar.
                const _ActiveOrderCard(),
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
                // Boton grande "Estoy en linea": abre el bottom sheet que
                // pide los permisos del SO para que el popup tipo llamada
                // funcione con el celu bloqueado / con otra app en foreground.
                // Si ya esta available, mostramos un "Pausar" mas chico.
                if (rider.status != 'available')
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(64),
                      backgroundColor: Colors.green,
                    ),
                    onPressed: () {
                      OfferRingtone.instance.warmUp();
                      showOnlineModeSheet(context, ref);
                    },
                    icon: const Icon(Icons.power_settings_new, size: 28),
                    label: const Text('Estoy en línea', style: TextStyle(fontSize: 20)),
                  )
                else
                  Card(
                    color: Colors.green.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green, size: 32),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'En línea — vas a recibir ofertas',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              await RidersRepository.instance.updateStatus('paused');
                              ref.invalidate(myRiderProvider);
                            },
                            child: const Text('Pausar'),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
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

/// Card prominente que aparece arriba de todo cuando el rider tiene
/// una orden activa (assigned o picked_up). Muestra direccion + monto
/// y un boton grande "Abrir pedido" que va a /r/orders/{id}.
/// Si no hay pedido activo, no renderiza nada (SizedBox.shrink).
class _ActiveOrderCard extends ConsumerWidget {
  const _ActiveOrderCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_myActiveOrderProvider);
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (order) {
        if (order == null) return const SizedBox.shrink();
        final money = order.totalAmountCents == null
            ? null
            : '\$${(order.totalAmountCents! / 100).toStringAsFixed(0)} ${order.currency ?? 'ARS'}';
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Card(
            color: Colors.amber.shade50,
            child: InkWell(
              onTap: () => context.push('/r/orders/${order.id}'),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: Colors.amber,
                          child: Icon(Icons.local_shipping, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                order.status == 'assigned'
                                    ? 'Pedido por retirar'
                                    : 'Pedido en camino',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              if (money != null)
                                Text(money, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Retirar en: ${order.pickupAddress}'),
                    Text('Entregar en: ${order.dropoffAddress}'),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        backgroundColor: Colors.amber.shade700,
                      ),
                      onPressed: () => context.push('/r/orders/${order.id}'),
                      icon: const Icon(Icons.navigation),
                      label: const Text('Abrir pedido', style: TextStyle(fontSize: 16)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
