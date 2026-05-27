import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:la10_data/la10_data.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await La10Supabase.init();
  runApp(const ProviderScope(child: La10MobileApp()));
}
