import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// geolocator re-exporta AndroidSettings + ForegroundNotificationConfig
// desde el platform-specific geolocator_android, no hace falta importar
// el package aparte.
import 'package:geolocator/geolocator.dart';
import 'package:la10_data/la10_data.dart';
import 'package:la10_geo/la10_geo.dart' as geo;

import 'offer_ringtone.dart';
import 'rider_home.dart' show myRiderProvider;

/// Tracker de GPS del rider. Se auto-arranca cuando el estado del rider
/// en la DB es `available` (asi reabrir la app NO te obliga a tocar el
/// switch otra vez) y usa un foreground service en Android para que la
/// lectura de GPS y los heartbeats sigan funcionando con la app en
/// segundo plano. Mientras corre, aparece una notif persistente
/// "La 10 — en linea" que el usuario reconoce.
class RiderGpsTracker extends ConsumerStatefulWidget {
  const RiderGpsTracker({super.key});

  @override
  ConsumerState<RiderGpsTracker> createState() => _RiderGpsTrackerState();
}

class _RiderGpsTrackerState extends ConsumerState<RiderGpsTracker> {
  StreamSubscription<Position>? _sub;
  final _throttle = RiderHeartbeatThrottle();
  bool _on = false;
  bool _starting = false;
  String? _error;
  Position? _last;
  int _sent = 0;
  String? _lastSyncedRiderStatus;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Sincroniza el tracker con el estado del rider en la DB.
  /// - status='available' → si no esta corriendo, lo arranca.
  /// - cualquier otro estado → si esta corriendo, lo apaga.
  /// Se llama desde build() solo cuando el status cambio (guardamos
  /// `_lastSyncedRiderStatus` para no re-disparar en cada rebuild).
  Future<void> _syncWithRiderStatus(String? riderStatus) async {
    if (_lastSyncedRiderStatus == riderStatus) return;
    _lastSyncedRiderStatus = riderStatus;
    if (riderStatus == 'available' && !_on && !_starting) {
      await _start();
    } else if (riderStatus != 'available' && _on) {
      await _stop();
    }
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        throw StateError('El servicio de ubicación está apagado.');
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw StateError('Permiso de ubicación denegado.');
      }

      // En Android usamos AndroidSettings con foregroundNotificationConfig
      // para que el GPS siga corriendo en segundo plano sin que el SO
      // mate la app. El user ve una notif "La 10 — en linea" persistente.
      // En iOS/web caemos al LocationSettings basico.
      final settings = Platform.isAndroid
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
              foregroundNotificationConfig: const ForegroundNotificationConfig(
                notificationTitle: 'La 10 — en línea',
                notificationText: 'Estás recibiendo ofertas. Tu ubicación se comparte.',
                enableWakeLock: true,
                setOngoing: true,
              ),
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
            );

      _sub = Geolocator.getPositionStream(locationSettings: settings)
          .listen(_onPosition, onError: (Object e) {
        if (mounted) setState(() => _error = '$e');
      });

      if (mounted) {
        setState(() {
          _on = true;
          _starting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _on = false;
          _starting = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
    if (mounted) setState(() => _on = false);
  }

  Future<void> _onPosition(Position p) async {
    final pos = geo.LatLng(p.latitude, p.longitude);
    if (!_throttle.shouldSend(pos)) {
      if (mounted) setState(() => _last = p);
      return;
    }
    try {
      await RidersRepository.instance.sendHeartbeat(
        lat: p.latitude,
        lng: p.longitude,
        heading: p.heading,
        speed: p.speed,
        accuracy: p.accuracy,
      );
      _throttle.markSent(pos);
      if (mounted) {
        setState(() {
          _last = p;
          _sent += 1;
          _error = null;
        });
      }
    } catch (e) {
      // Errores típicos: red caída momentánea (`SocketException`/`Failed host lookup`).
      // No bloqueamos el tracking — el próximo position dispara un retry
      // automático y si funciona el `_error` se limpia. Mostramos un mensaje
      // corto para no llenar la pantalla con el stack trace de Dart.
      if (!mounted) return;
      final friendly = e.toString().contains('SocketException') ||
              e.toString().contains('Failed host lookup')
          ? 'Sin internet — reintentando…'
          : '$e';
      setState(() => _error = friendly);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Cada vez que rebuild, sincronizamos el tracker con el estado del
    // rider. Si el rider esta available y el tracker no esta corriendo,
    // arranca. Si el rider se pauso, lo apagamos.
    final rider = ref.watch(myRiderProvider).value;
    final status = rider?.status;
    // postFrame para no llamar setState durante build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncWithRiderStatus(status);
    });
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.gps_fixed, color: _on ? cs.primary : cs.outline),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _on ? 'Ubicación compartiéndose' : 'Ubicación: detenida',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_starting)
                  const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _on
                  ? 'Sigue activa con la app cerrada o el celu bloqueado.'
                  : 'Se activa sola cuando tocás "Estoy en línea".',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_last != null) ...[
              const SizedBox(height: 8),
              Text(
                'Última: ${_last!.latitude.toStringAsFixed(5)}, '
                '${_last!.longitude.toStringAsFixed(5)} · ±${_last!.accuracy.toStringAsFixed(0)} m',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                'Heartbeats enviados: $_sent',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  OfferRingtone.instance.warmUp();
                  OfferRingtone.instance.play();
                },
                icon: const Icon(Icons.volume_up),
                label: const Text('Probar sonido de oferta'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: cs.error)),
            ],
          ],
        ),
      ),
    );
  }
}
