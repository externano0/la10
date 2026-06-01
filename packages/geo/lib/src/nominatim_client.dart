/// Cliente HTTP para Nominatim — el geocoder gratuito de OpenStreetMap.
/// Usado para buscar direcciones desde el map picker / address field.
///
/// Notas importantes:
/// - No mandamos User-Agent custom. En el browser es un "forbidden header"
///   y queda dropeado (el browser manda el suyo). En nativo el default
///   `Dart/X.X` también funciona — Nominatim solo rechaza a abusers reales.
/// - Cualquier error de red o status ≠ 200 devuelve lista vacía — no rompe
///   la UI. Si la query falla por CORS o rate limit, el user solo no ve
///   sugerencias.
/// - Public API es ~1 req/seg de rate. Para uso productivo serio conviene
///   self-host. Para nuestro volumen actual alcanza.
/// Doc: https://nominatim.org/release-docs/latest/api/Search/

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lat_lng.dart';

class NominatimHit {
  const NominatimHit({
    required this.displayName,
    required this.lat,
    required this.lng,
  });

  factory NominatimHit.fromJson(Map<String, dynamic> j) => NominatimHit(
        displayName: j['display_name'] as String? ?? '',
        lat: double.tryParse('${j['lat']}') ?? 0,
        lng: double.tryParse('${j['lon']}') ?? 0,
      );

  final String displayName;
  final double lat;
  final double lng;

  LatLng get point => LatLng(lat, lng);
}

class NominatimClient {
  NominatimClient({String? baseUrl, http.Client? client, this.countryCodes = 'ar'})
      : baseUrl = baseUrl ?? 'https://nominatim.openstreetmap.org',
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  final String countryCodes;

  Future<List<NominatimHit>> search(String query, {int limit = 5}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final uri = Uri.parse('$baseUrl/search').replace(queryParameters: {
      'q': q,
      'format': 'jsonv2',
      'limit': '$limit',
      'countrycodes': countryCodes,
      'addressdetails': '0',
    });
    try {
      final res = await _client.get(uri);
      if (res.statusCode != 200) return const [];
      final list = jsonDecode(res.body) as List<dynamic>;
      return list.map((e) => NominatimHit.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }
}
