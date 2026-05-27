import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../src/auth_state.dart';
import '../src/profile.dart';

/// Transitional landing page after login. Redirects to the role-specific home
/// as soon as the profile (and therefore role) loads.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final asyncProfile = ref.watch(currentProfileProvider);

    ref.listen<AsyncValue<Profile?>>(currentProfileProvider, (prev, next) {
      next.whenData((p) {
        if (p != null && context.mounted) {
          context.go(p.homeRoute());
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('La 10'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await AuthActions.instance.signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: asyncProfile.when(
              loading: () => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Cargando perfil…'),
                ],
              ),
              error: (e, _) => Text('Error: $e'),
              data: (p) {
                if (p == null) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber, size: 64, color: Colors.orange),
                      const SizedBox(height: 16),
                      Text(user?.email ?? '—'),
                      const SizedBox(height: 8),
                      const Text('Tu perfil no está creado todavía. Cerrá sesión y volvé a entrar.'),
                    ],
                  );
                }
                // Should immediately redirect via ref.listen above; show
                // brief transition state.
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, size: 64, color: Colors.green),
                    const SizedBox(height: 16),
                    Text(p.fullName ?? user?.email ?? '—'),
                    const SizedBox(height: 8),
                    Text('Rol: ${p.role.name}'),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => context.go(p.homeRoute()),
                      child: const Text('Continuar'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
