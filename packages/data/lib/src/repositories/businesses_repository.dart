import '../supabase/client.dart';

class Business {
  const Business({
    required this.id,
    required this.name,
    this.phone,
    this.address,
    this.lat,
    this.lng,
    required this.ownerId,
    required this.isActive,
  });

  factory Business.fromJson(Map<String, dynamic> j) {
    final loc = j['location'] as String?;
    double? lat;
    double? lng;
    if (loc != null) {
      // PostGIS may return GeoJSON or hex EWKB; the REST API converts geography
      // to GeoJSON-ish only if requested. We accept null and re-fetch via RPC
      // when we need precise coords. For dashboard display address is enough.
    }
    return Business(
      id: j['id'] as String,
      name: j['name'] as String,
      phone: j['phone'] as String?,
      address: j['address'] as String?,
      lat: lat,
      lng: lng,
      ownerId: j['owner_id'] as String,
      isActive: (j['is_active'] as bool?) ?? true,
    );
  }

  final String id;
  final String name;
  final String? phone;
  final String? address;
  final double? lat;
  final double? lng;
  final String ownerId;
  final bool isActive;
}

class BusinessesRepository {
  BusinessesRepository._();
  static final instance = BusinessesRepository._();

  Future<List<Business>> listMine() async {
    final res = await La10Supabase.client
        .from('businesses')
        .select()
        .filter('deleted_at', 'is', null)
        .order('created_at');
    return (res as List).map((e) => Business.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Business> create({
    required String name,
    String? phone,
    String? address,
    required double lat,
    required double lng,
  }) async {
    final user = La10Supabase.auth.currentUser;
    if (user == null) throw StateError('not authenticated');
    final res = await La10Supabase.client.from('businesses').insert({
      'owner_id': user.id,
      'name': name,
      'phone': phone,
      'address': address,
      'location': 'SRID=4326;POINT($lng $lat)',
    }).select().single();
    return Business.fromJson(res);
  }

  Future<Business?> getById(String id) async {
    final res = await La10Supabase.client.from('businesses').select().eq('id', id).maybeSingle();
    return res == null ? null : Business.fromJson(res);
  }
}
