import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:la10_auth/la10_auth.dart';
import 'package:la10_data/la10_data.dart';

final myBusinessesProvider = FutureProvider<List<Business>>((ref) async {
  return BusinessesRepository.instance.listMine();
});

class BusinessesHome extends ConsumerWidget {
  const BusinessesHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myBusinessesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis negocios'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              await AuthActions.instance.signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/b/businesses/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo negocio'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.storefront_outlined, size: 64),
                    const SizedBox(height: 12),
                    const Text('Aún no tenés negocios cargados'),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () => context.push('/b/businesses/new'),
                      icon: const Icon(Icons.add),
                      label: const Text('Crear el primero'),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final b = list[i];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.storefront),
                  title: Text(b.name),
                  subtitle: Text(b.address ?? 'Sin dirección'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/b/businesses/${b.id}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
