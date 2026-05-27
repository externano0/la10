import 'dart:math' as math;
import 'lat_lng.dart';

const double _earthRadiusM = 6371000.0;

// Haversine distance in meters.
double haversineMeters(LatLng a, LatLng b) {
  final dLat = _radians(b.lat - a.lat);
  final dLng = _radians(b.lng - a.lng);
  final lat1 = _radians(a.lat);
  final lat2 = _radians(b.lat);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2)
      + math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * _earthRadiusM * math.asin(math.min(1, math.sqrt(h)));
}

double _radians(double deg) => deg * math.pi / 180;
