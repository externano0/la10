import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:la10_data/la10_data.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Atrapamos cualquier error de init (típicamente SUPABASE_URL faltante)
  // y mostramos pantalla de error en vez de quedar pegados en el splash.
  try {
    await La10Supabase.init();
    runApp(const ProviderScope(child: La10MobileApp()));
  } catch (e, st) {
    runApp(_BootErrorApp(error: '$e', stack: '$st'));
  }
}

class _BootErrorApp extends StatelessWidget {
  const _BootErrorApp({required this.error, required this.stack});
  final String error;
  final String stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'La 10',
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'La app no pudo iniciar',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('Posibles causas: la build no tomó las variables de Supabase, '
                      'o no hay conexión a internet.'),
                  const SizedBox(height: 24),
                  const Text('Detalle:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(error, style: const TextStyle(fontFamily: 'monospace')),
                  ),
                  const SizedBox(height: 16),
                  const Text('Stack:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(stack, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
