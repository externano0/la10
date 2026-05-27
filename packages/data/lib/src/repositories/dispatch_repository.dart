import '../supabase/client.dart';

class DispatchRepository {
  DispatchRepository._();
  static final instance = DispatchRepository._();

  /// Forces an offer to a specific rider via edge fn `dispatch-order`.
  Future<Map<String, dynamic>> manualAssign({required String orderId, required String riderId}) async {
    final resp = await La10Supabase.client.functions.invoke(
      'dispatch-order',
      body: {'order_id': orderId, 'rider_id': riderId},
    );
    final data = (resp.data as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    if (data['error'] != null) {
      final err = data['error'] as Map<String, dynamic>;
      throw Exception('${err['code']}: ${err['message']}');
    }
    return data;
  }
}
