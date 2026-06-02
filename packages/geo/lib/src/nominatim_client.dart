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
    this.hasHouseNumber = false,
    this.placeRank = 0,
  });

  factory NominatimHit.fromJson(Map<String, dynamic> j) {
    final address = j['address'] as Map<String, dynamic>?;
    return NominatimHit(
      displayName: j['display_name'] as String? ?? '',
      lat: double.tryParse('${j['lat']}') ?? 0,
      lng: double.tryParse('${j['lon']}') ?? 0,
      // Nominatim devuelve `house_number` solo cuando matcheo el numero
      // especifico. Si no esta = solo matcheo la calle = el lat/lng es
      // un centroide aproximado (a veces hasta 2 cuadras off).
      hasHouseNumber: address != null && address['house_number'] != null,
      // place_rank mas alto = mas especifico (10 = country, 30 = building).
      // Usamos esto como tiebreaker cuando varios resultados matchean.
      placeRank: (j['place_rank'] as num?)?.toInt() ?? 0,
    );
  }

  final String displayName;
  final double lat;
  final double lng;
  final bool hasHouseNumber;
  final int placeRank;

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
    // Pedimos addressdetails=1 para poder ver si cada hit incluye
    // house_number → asi priorizamos los que matchearon el numero
    // exacto sobre los que solo matchearon la calle.
    // Pedimos el doble de hits que mostramos al user para tener margen
    // de re-sort: tomamos los top N con house_number primero.
    final fetchLimit = (limit * 2).clamp(5, 20);
    final uri = Uri.parse('$baseUrl/search').replace(queryParameters: {
      'q': q,
      'format': 'jsonv2',
      'limit': '$fetchLimit',
      'countrycodes': countryCodes,
      'addressdetails': '1',
    });
    try {
      final res = await _client.get(uri);
      if (res.statusCode != 200) return const [];
      final list = jsonDecode(res.body) as List<dynamic>;
      final hits = list
          .map((e) => NominatimHit.fromJson(e as Map<String, dynamic>))
          .toList();
      // Sort: hits con house_number primero, despues por placeRank desc.
      // Esto sube el resultado exacto (la casa especifica) por encima
      // de la calle "Juarez Celman" sin numero que viene como centroide.
      hits.sort((a, b) {
        if (a.hasHouseNumber != b.hasHouseNumber) {
          return a.hasHouseNumber ? -1 : 1;
        }
        return b.placeRank.compareTo(a.placeRank);
      });
      return hits.take(limit).toList();
    } catch (_) {
      return const [];
    }
  }
}
