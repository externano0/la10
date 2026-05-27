import '../supabase/client.dart';

class Rider {
  const Rider({
    required this.userId,
    required this.displayName,
    this.phone,
    required this.vehicleType,
    required this.status,
    required this.isActive,
  });

  factory Rider.fromJson(Map<String, dynamic> j) => Rider(
        userId: j['user_id'] as String,
        displayName: j['display_name'] as String,
        phone: j['phone'] as String?,
        vehicleType: j['vehicle_type'] as String? ?? 'motorcycle',
        status: j['status'] as String? ?? 'offline',
        isActive: (j['is_active'] as bool?) ?? true,
      );

  final String userId;
  final String displayName;
  final String? phone;
  final String vehicleType;
  final String status;
  final bool isActive;
}

class RiderLocation {
  const RiderLocation({
    required this.riderId,
    required this.lat,
    required this.lng,
    this.heading,
    this.speedMs,
    this.accuracyM,
    required this.recordedAt,
  });

  factory RiderLocation.fromJson(Map<String, dynamic> j) => RiderLocation(
        riderId: j['rider_id'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        heading: (j['heading'] as num?)?.toDouble(),
        speedMs: (j['speed_ms'] as num?)?.toDouble(),
        accuracyM: (j['accuracy_m'] as num?)?.toDouble(),
        recordedAt: DateTime.parse(j['recorded_at'] as String),
      );

  final String riderId;
  final double lat;
  final double lng;
  final double? heading;
  final double? speedMs;
  final double? accuracyM;
  final DateTime recordedAt;
}

class RidersRepository {
  RidersRepository._();
  static final instance = RidersRepository._();

  Future<Rider?> me() async {
    final u = La10Supabase.auth.currentUser;
    if (u == null) return null;
    final res = await La10Supabase.client.from('riders').select().eq('user_id', u.id).maybeSingle();
    return res == null ? null : Rider.fromJson(res);
  }

  Future<Rider> ensureSelf({
    required String displayName,
    String? phone,
  }) async {
    final res = await La10Supabase.client.rpc('ensure_rider_row', params: {
      'p_display_name': displayName,
      if (phone != null && phone.trim().isNotEmpty) 'p_phone': phone.trim(),
    });
    return Rider.fromJson(res as Map<String, dynamic>);
  }

  Future<void> updateStatus(String status) async {
    final u = La10Supabase.auth.currentUser;
    if (u == null) throw StateError('not authenticated');
    await La10Supabase.client.from('riders').update({'status': status}).eq('user_id', u.id);
  }

  Future<List<Rider>> listAll() async {
    final res = await La10Supabase.client.from('riders').select().order('display_name');
    return (res as List).map((e) => Rider.fromJson(e as Map<String, dynamic>)).toList();
  }

  Stream<List<Rider>> watchAll() {
    return La10Supabase.client.from('riders').stream(primaryKey: ['user_id']).map(
          (rows) => rows.map((e) => Rider.fromJson(e)).toList(),
        );
  }

  Stream<List<RiderLocation>> watchAllLocations() {
    return La10Supabase.client
        .from('rider_locations')
        .stream(primaryKey: ['rider_id'])
        .map((rows) => rows
            .where((e) => e['lat'] != null && e['lng'] != null)
            .map((e) => RiderLocation.fromJson(e))
            .toList());
  }

  Future<void> sendHeartbeat({
    required double lat,
    required double lng,
    double? heading,
    double? speed,
    double? accuracy,
    String? orderId,
  }) async {
    final resp = await La10Supabase.client.functions.invoke(
      'rider-heartbeat',
      body: {
        'lat': lat,
        'lng': lng,
        if (heading != null) 'heading': heading,
        if (speed != null) 'speed': speed,
        if (accuracy != null) 'accuracy_m': accuracy,
        if (orderId != null) 'order_id': orderId,
      },
    );
    final data = resp.data as Map<String, dynamic>?;
    if (data?['error'] != null) {
      final err = data!['error'] as Map<String, dynamic>;
      throw Exception('${err['code']}: ${err['message']}');
    }
  }
}
