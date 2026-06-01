/// Bottom sheet "Activar modo en línea" para el rider.
///
/// Le pedimos los permisos que hacen falta para que el popup tipo llamada
/// suene con el celu bloqueado o con otra app en foreground:
///   - POST_NOTIFICATIONS (Android 13+)
///   - SYSTEM_ALERT_WINDOW ("Mostrar sobre otras apps") — sin esto la notif
///     no pinta pantalla completa con Instagram/banco abierto.
///   - SCHEDULE_EXACT_ALARM — para que la notif suene en el momento exacto
///     sin esperar la batch window de Doze.
///   - Ignore battery optimizations — sin esto MIUI/Xiaomi/Huawei/Samsung
///     matan FCM cuando la app está en background.
///   - Notification policy access (Android 14+) — el toggle de
///     "Notificaciones en pantalla completa" en settings.
///
/// Si todos están otorgados, el rider arranca "Disponible". Si falta alguno,
/// abrimos la pantalla de Settings correspondiente con instrucciones claras.
///
/// El bottom sheet se llama desde rider_home cuando el rider toca
/// "Estoy en línea / Recibir ofertas" o cuando toca "Disponible".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:la10_data/la10_data.dart';
import 'package:permission_handler/permission_handler.dart';

import 'rider_home.dart';

class _Perm {
  const _Perm(this.permission, this.title, this.subtitle);
  final Permission permission;
  final String title;
  final String subtitle;
}

const _required = <_Perm>[
  _Perm(
    Permission.notification,
    'Notificaciones',
    'Para mostrar la oferta cuando llega.',
  ),
  _Perm(
    Permission.systemAlertWindow,
    'Mostrar sobre otras apps',
    'Para que la oferta aparezca aunque estés en Instagram o el banco.',
  ),
  _Perm(
    Permission.scheduleExactAlarm,
    'Alarmas precisas',
    'Para que suene en el momento, sin demora.',
  ),
  _Perm(
    Permission.ignoreBatteryOptimizations,
    'Sin optimización de batería',
    'Sin esto, el celu mata la app después de un rato.',
  ),
];

Future<void> showOnlineModeSheet(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _OnlineModeSheet(),
  );
}

class _OnlineModeSheet extends ConsumerStatefulWidget {
  const _OnlineModeSheet();
  @override
  ConsumerState<_OnlineModeSheet> createState() => _OnlineModeSheetState();
}

class _OnlineModeSheetState extends ConsumerState<_OnlineModeSheet> {
  Map<Permission, PermissionStatus> _status = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = <Permission, PermissionStatus>{};
    for (final p in _required) {
      s[p.permission] = await p.permission.status;
    }
    if (mounted) setState(() => _status = s);
  }

  Future<void> _requestAll() async {
    setState(() => _busy = true);
    // El plugin abre prompts del SO de a uno. Algunos (overlay, ignore
    // battery, exact alarm) abren la pantalla de Settings y el user vuelve
    // a la app cuando termina.
    for (final p in _required) {
      final current = await p.permission.status;
      if (current.isGranted) continue;
      await p.permission.request();
    }
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _goOnline() async {
    await RidersRepository.instance.updateStatus('available');
    ref.invalidate(myRiderProvider);
    if (mounted) Navigator.of(context).pop();
  }

  bool get _allGranted => _status.values.every((s) => s.isGranted);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.green,
                  child: const Icon(Icons.notifications_active, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Modo en línea', style: Theme.of(context).textTheme.titleLarge),
                      Text(
                        'Para recibir ofertas con el celu bloqueado o estando en otra app, '
                        'autorizá estos permisos del sistema.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ..._required.map((p) {
              final granted = _status[p.permission]?.isGranted ?? false;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      granted ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: granted ? Colors.green : cs.outline,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.title,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(p.subtitle, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 20),
            if (!_allGranted)
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                onPressed: _busy ? null : _requestAll,
                icon: const Icon(Icons.lock_open),
                label: const Text('Autorizar todos'),
              )
            else
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: Colors.green,
                ),
                onPressed: _busy ? null : _goOnline,
                icon: const Icon(Icons.power_settings_new),
                label: const Text('Estoy en línea'),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : openAppSettings,
              child: const Text('Abrir ajustes de la app'),
            ),
          ],
        ),
      ),
    );
  }
}
