import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:la10_data/la10_data.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await La10Supabase.init();
  // Refresh del token guardado para evitar queries colgadas con token vencido.
  if (La10Supabase.auth.currentSession != null) {
    try {
      await La10Supabase.auth.refreshSession()
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      await La10Supabase.auth.signOut().catchError((_) {});
    }
  }
  runApp(const ProviderScope(child: La10WebDesktopApp()));
}
