import 'package:la10_core/la10_core.dart';
import 'package:la10_geo/la10_geo.dart';

/// Decides whether the rider client should send a new heartbeat upsert,
/// based on time-since-last and movement thresholds (see ENVIRONMENT.md).
class RiderHeartbeatThrottle {
  RiderHeartbeatThrottle({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  DateTime? _lastSent;
  LatLng? _lastPos;

  bool shouldSend(LatLng current) {
    final now = _now();
    final last = _lastSent;
    final lastPos = _lastPos;

    final minSec = Env.riderHeartbeatMinIntervalSec;
    final maxSec = Env.riderHeartbeatMaxIntervalSec;
    final minM   = Env.riderHeartbeatMinDistanceM;

    if (last == null || lastPos == null) return true;

    final elapsedSec = now.difference(last).inSeconds;
    if (elapsedSec >= maxSec) return true;
    if (elapsedSec < minSec) return false;

    final moved = haversineMeters(lastPos, current);
    return moved >= minM;
  }

  void markSent(LatLng pos) {
    _lastSent = _now();
    _lastPos = pos;
  }
}
