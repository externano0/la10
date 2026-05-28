import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:la10_data/la10_data.dart';
import 'package:la10_geo/la10_geo.dart' as geo;

import 'offer_ringtone.dart';

/// Toggleable card that streams the device GPS and pushes heartbeats to
/// the rider-heartbeat edge fn, throttled by [RiderHeartbeatThrottle].
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

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _toggle(bool on) async {
    // Habilita audio aprovechando este gesto del usuario; el ringtone
    // de oferta lo necesita más tarde.
    OfferRingtone.instance.warmUp();
    if (on) {
      await _start();
    } else {
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

      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen(_onPosition, onError: (Object e) {
        setState(() => _error = '$e');
      });

      setState(() {
        _on = true;
        _starting = false;
      });
    } catch (e) {
      setState(() {
        _on = false;
        _starting = false;
        _error = '$e';
      });
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
                    _on ? 'GPS automático: encendido' : 'GPS automático: apagado',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_starting)
                  const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch(value: _on, onChanged: _toggle),
              ],
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
