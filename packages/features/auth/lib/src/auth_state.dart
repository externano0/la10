import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:la10_data/la10_data.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile.dart';

/// Stream of the current Supabase session. Null when signed out.
///
/// IMPORTANTE: emitimos primero el `currentSession` ya restaurado por
/// Supabase.initialize, antes de suscribirnos a `onAuthStateChange`. Sin
/// esto, en cold start el stream queda "loading" hasta el primer auth
/// event y el router cree que no hay sesión y manda a /login.
final authSessionProvider = StreamProvider<Session?>((ref) async* {
  final auth = La10Supabase.auth;
  yield auth.currentSession;
  yield* auth.onAuthStateChange.map((event) => event.session).distinct(
        (a, b) => a?.user.id == b?.user.id,
      );
});

/// Convenience: current user or null.
final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authSessionProvider).maybeWhen(
        data: (session) => session?.user,
        orElse: () => null,
      );
});

/// Current profile row from `public.profiles`. Null when signed out.
final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  final res = await La10Supabase.client
      .from('profiles')
      .select()
      .eq('user_id', user.id)
      .maybeSingle();
  if (res == null) return null;
  return Profile.fromJson(res);
});

/// Derived: just the role. Null while loading or signed out.
final currentRoleProvider = Provider<AppRole?>((ref) {
  return ref.watch(currentProfileProvider).maybeWhen(
        data: (p) => p?.role,
        orElse: () => null,
      );
});

class AuthActions {
  AuthActions._();
  static final instance = AuthActions._();

  Future<void> signInWithPassword({required String email, required String password}) async {
    await La10Supabase.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signUpWithPassword({
    required String email,
    required String password,
    String? fullName,
  }) async {
    await La10Supabase.auth.signUp(
      email: email,
      password: password,
      data: fullName == null ? null : {'full_name': fullName},
    );
  }

  Future<void> signOut() async {
    await La10Supabase.auth.signOut();
  }
}
