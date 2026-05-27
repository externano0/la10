import 'dart:convert';
import 'package:http/http.dart' as http;
import 'lat_lng.dart';

class OsrmRoute {
  const OsrmRoute({required this.distanceM, required this.durationSec, required this.geometry});
  final double distanceM;
  final double durationSec;
  final List<LatLng> geometry;
}

class OsrmClient {
  OsrmClient({required this.baseUrl, http.Client? client}) : _client = client ?? http.Client();

  final String baseUrl; // e.g. https://router.project-osrm.org
  final http.Client _client;

  // Driving route. Use sparingly — public demo is rate-limited.
  Future<OsrmRoute?> route(LatLng from, LatLng to) async {
    final coords = '${from.lng},${from.lat};${to.lng},${to.lat}';
    final uri = Uri.parse('$baseUrl/route/v1/driving/$coords?overview=full&geometries=geojson');
    final res = await _client.get(uri);
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final routes = body['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) return null;
    final r = routes.first as Map<String, dynamic>;
    final coordsArr = ((r['geometry'] as Map<String, dynamic>)['coordinates'] as List<dynamic>)
        .map((p) {
          final c = p as List<dynamic>;
          return LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());
        })
        .toList(growable: false);
    return OsrmRoute(
      distanceM: (r['distance'] as num).toDouble(),
      durationSec: (r['duration'] as num).toDouble(),
      geometry: coordsArr,
    );
  }
}
