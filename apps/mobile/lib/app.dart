import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:la10_auth/la10_auth.dart';
import 'package:la10_businesses/la10_businesses.dart';
import 'package:la10_data/la10_data.dart';
import 'package:la10_dispatch/la10_dispatch.dart';
import 'package:la10_orders/la10_orders.dart';
import 'package:la10_riders/la10_riders.dart';
import 'package:la10_tracking/la10_tracking.dart';
import 'package:la10_ui/la10_ui.dart';

String _homeForRole(AppRole role) => switch (role) {
      AppRole.superAdmin    => '/d/home',
      AppRole.dispatcher    => '/d/home',
      AppRole.businessOwner => '/b/home',
      AppRole.rider         => '/r/home',
    };

bool _allowedPrefix(AppRole role, String loc) {
  if (loc.startsWith('/r/')) return role == AppRole.rider;
  if (loc.startsWith('/b/')) return role == AppRole.businessOwner || role == AppRole.superAdmin;
  if (loc.startsWith('/d/')) return role == AppRole.dispatcher || role == AppRole.superAdmin;
  return true;
}

GoRouter _buildRouter(WidgetRef ref) {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: GoRouterRefreshListenable(ref),
    redirect: (context, state) {
      final session = La10Supabase.auth.currentSession;
      final loc = state.matchedLocation;
      final atAuth = loc == '/login' || loc == '/signup';

      if (session == null) return atAuth ? null : '/login';

      final role = ref.read(currentRoleProvider);
      if (role == null) return null;
      if (atAuth || loc == '/home') return _homeForRole(role);
      if (!_allowedPrefix(role, loc)) return _homeForRole(role);
      return null;
    },
    routes: [
      ...authRoutes,
      ...businessesRoutes,
      ...ordersRoutes,
      ...dispatchRoutes,
      ...ridersRoutes,
      ...trackingRoutes,
    ],
  );
}

class GoRouterRefreshListenable extends ChangeNotifier {
  GoRouterRefreshListenable(this._ref) {
    _ref.listen(authSessionProvider, (_, __) => notifyListeners());
    _ref.listen(currentProfileProvider, (_, __) => notifyListeners());
  }
  final WidgetRef _ref;
}

class La10MobileApp extends ConsumerWidget {
  const La10MobileApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = _buildRouter(ref);
    return MaterialApp.router(
      title: 'La 10',
      theme: la10LightTheme(),
      darkTheme: la10DarkTheme(),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
