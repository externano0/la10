import 'package:go_router/go_router.dart';

import 'business_create.dart';
import 'business_detail.dart';
import 'businesses_home.dart';

final businessesRoutes = <RouteBase>[
  GoRoute(path: '/b/home', builder: (context, state) => const BusinessesHome()),
  GoRoute(path: '/b/businesses/new', builder: (context, state) => const BusinessCreate()),
  GoRoute(
    path: '/b/businesses/:id',
    builder: (context, state) => BusinessDetail(id: state.pathParameters['id']!),
  ),
];
