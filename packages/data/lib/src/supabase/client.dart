import 'package:la10_core/la10_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps the Supabase singleton so the rest of the app does not import
/// `supabase_flutter` directly.
class La10Supabase {
  La10Supabase._();

  static Future<void> init() async {
    if (!Env.isConfigured) {
      throw const Failure('CONFIG', 'SUPABASE_URL / SUPABASE_ANON_KEY missing');
    }
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
      realtimeClientOptions: const RealtimeClientOptions(
        eventsPerSecond: 10,
      ),
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
  static GoTrueClient get auth => Supabase.instance.client.auth;
}
