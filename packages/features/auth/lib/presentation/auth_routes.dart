import 'package:go_router/go_router.dart';

import 'home_screen.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

final authRoutes = <RouteBase>[
  GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
  GoRoute(path: '/signup', builder: (context, state) => const SignupScreen()),
  GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
];
