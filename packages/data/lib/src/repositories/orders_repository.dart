import '../supabase/client.dart';

class OrderRow {
  const OrderRow({
    required this.id,
    required this.businessId,
    required this.customerName,
    this.customerPhone,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.status,
    this.assignedRiderId,
    this.totalAmountCents,
    this.currency,
    this.notes,
    required this.createdAt,
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
  });

  factory OrderRow.fromJson(Map<String, dynamic> j) => OrderRow(
        id: j['id'] as String,
        businessId: j['business_id'] as String,
        customerName: j['customer_name'] as String,
        customerPhone: j['customer_phone'] as String?,
        pickupAddress: j['pickup_address'] as String,
        dropoffAddress: j['dropoff_address'] as String,
        status: j['status'] as String,
        assignedRiderId: j['assigned_rider_id'] as String?,
        totalAmountCents: j['total_amount_cents'] as int?,
        currency: j['currency'] as String?,
        notes: j['notes'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
        pickupLat: (j['pickup_lat'] as num?)?.toDouble(),
        pickupLng: (j['pickup_lng'] as num?)?.toDouble(),
        dropoffLat: (j['dropoff_lat'] as num?)?.toDouble(),
        dropoffLng: (j['dropoff_lng'] as num?)?.toDouble(),
      );

  final String id;
  final String businessId;
  final String customerName;
  final String? customerPhone;
  final String pickupAddress;
  final String dropoffAddress;
  final String status;
  final String? assignedRiderId;
  final int? totalAmountCents;
  final String? currency;
  final String? notes;
  final DateTime createdAt;
  final double? pickupLat;
  final double? pickupLng;
  final double? dropoffLat;
  final double? dropoffLng;
}

class OrdersRepository {
  OrdersRepository._();
  static final instance = OrdersRepository._();

  Future<List<OrderRow>> listForBusiness(String businessId, {String? status}) async {
    var q = La10Supabase.client.from('orders').select().eq('business_id', businessId);
    if (status != null) q = q.eq('status', status);
    final res = await q.order('created_at', ascending: false);
    return (res as List).map((e) => OrderRow.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<OrderRow?> getById(String id) async {
    final res = await La10Supabase.client.from('orders').select().eq('id', id).maybeSingle();
    return res == null ? null : OrderRow.fromJson(res);
  }

  Future<OrderRow> create({
    required String businessId,
    required String customerName,
    String? customerPhone,
    required String pickupAddress,
    required double pickupLat,
    required double pickupLng,
    required String dropoffAddress,
    required double dropoffLat,
    required double dropoffLng,
    int? totalAmountCents,
    String? notes,
  }) async {
    final res = await La10Supabase.client.from('orders').insert({
      'business_id': businessId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'pickup_address': pickupAddress,
      'pickup_location': 'SRID=4326;POINT($pickupLng $pickupLat)',
      'dropoff_address': dropoffAddress,
      'dropoff_location': 'SRID=4326;POINT($dropoffLng $dropoffLat)',
      'total_amount_cents': totalAmountCents,
      'notes': notes,
      'status': 'draft',
    }).select().single();
    return OrderRow.fromJson(res);
  }

  /// Centralized state transition via edge fn `order-status`.
  Future<void> transition(String orderId, String to, {String? reason}) async {
    final resp = await La10Supabase.client.functions.invoke(
      'order-status',
      body: {'order_id': orderId, 'to': to, if (reason != null) 'reason': reason},
    );
    final data = resp.data as Map<String, dynamic>?;
    if (data?['error'] != null) {
      final err = data!['error'] as Map<String, dynamic>;
      throw Exception('${err['code']}: ${err['message']}');
    }
  }

  Stream<List<OrderRow>> watchAll() {
    return La10Supabase.client.from('orders').stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows.map((e) => OrderRow.fromJson(e)).toList());
  }

  Future<List<Map<String, dynamic>>> eventsFor(String orderId) async {
    final res = await La10Supabase.client.from('order_events').select().eq('order_id', orderId).order('created_at');
    return (res as List).cast<Map<String, dynamic>>();
  }
}
