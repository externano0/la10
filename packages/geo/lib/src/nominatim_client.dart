/// Cliente HTTP para Nominatim — el geocoder gratuito de OpenStreetMap.
/// Usado para buscar direcciones desde el map picker (el comercio escribe
/// "juarez celman 2871" y le mostramos resultados con su lat/lng aproximado).
///
/// Nominatim tiene una public API gratis pero pide un User-Agent identificable
/// y respeta rate limits (~1 req/seg). Para uso productivo serio conviene
/// self-host o pagar un proveedor; para nuestro volumen actual alcanza.
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

  /// Filtro por país (Argentina por default — la app es local). Si en el
  /// futuro hay agencias en otros países, lo movemos a Env.
  final String countryCodes;

  /// Busca direcciones con texto libre. Devuelve hasta [limit] resultados
  /// ordenados por relevancia. En error de red o status no-200 devuelve
  /// lista vacía (no rompe la UI).
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
      final res = await _client.get(uri, headers: {
        // Nominatim pide UA identificable; sin esto puede devolver 403.
        'User-Agent': 'la10-delivery-app/0.1 (https://github.com/externano0/la10)',
      });
      if (res.statusCode != 200) return const [];
      final list = jsonDecode(res.body) as List<dynamic>;
      return list.map((e) => NominatimHit.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }
}
