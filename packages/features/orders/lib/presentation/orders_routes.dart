import 'package:go_router/go_router.dart';

import 'order_new.dart';

final ordersRoutes = <RouteBase>[
  GoRoute(
    path: '/b/businesses/:id/orders/new',
    builder: (context, state) => OrderNew(businessId: state.pathParameters['id']!),
  ),
];
