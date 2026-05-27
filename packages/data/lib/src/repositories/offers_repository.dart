import '../supabase/client.dart';

class Offer {
  const Offer({
    required this.id,
    required this.orderId,
    required this.riderId,
    required this.score,
    required this.expiresAt,
    required this.response,
    this.respondedAt,
  });

  factory Offer.fromJson(Map<String, dynamic> j) => Offer(
        id: j['id'] as String,
        orderId: j['order_id'] as String,
        riderId: j['rider_id'] as String,
        score: (j['score'] as num).toDouble(),
        expiresAt: DateTime.parse(j['expires_at'] as String),
        response: j['response'] as String,
        respondedAt: j['responded_at'] == null ? null : DateTime.parse(j['responded_at'] as String),
      );

  final String id;
  final String orderId;
  final String riderId;
  final double score;
  final DateTime expiresAt;
  final String response;
  final DateTime? respondedAt;
}

class OffersRepository {
  OffersRepository._();
  static final instance = OffersRepository._();

  Stream<List<Offer>> watchMyPending() {
    final u = La10Supabase.auth.currentUser;
    if (u == null) return Stream.value(const []);
    return La10Supabase.client.from('dispatch_offers').stream(primaryKey: ['id']).eq('rider_id', u.id).map(
          (rows) => rows
              .map((e) => Offer.fromJson(e))
              .where((o) => o.response == 'pending' && o.expiresAt.isAfter(DateTime.now()))
              .toList(),
        );
  }

  Future<void> respond(String offerId, String response) async {
    final resp = await La10Supabase.client.functions.invoke(
      'offer-respond',
      body: {'offer_id': offerId, 'response': response},
    );
    final data = resp.data as Map<String, dynamic>?;
    if (data?['error'] != null) {
      final err = data!['error'] as Map<String, dynamic>;
      throw Exception('${err['code']}: ${err['message']}');
    }
  }
}
