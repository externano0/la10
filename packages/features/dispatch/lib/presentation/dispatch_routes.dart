import 'package:go_router/go_router.dart';

import 'chat_screen.dart';
import 'dispatch_home.dart';
import 'dispatch_map.dart';
import 'order_detail.dart';
import 'riders_list.dart';

final dispatchRoutes = <RouteBase>[
  GoRoute(path: '/d/home', builder: (context, state) => const DispatchHome()),
  GoRoute(path: '/d/map', builder: (context, state) => const DispatchMap()),
  // Mapa centrado en un rider específico (botón "Localizar").
  GoRoute(
    path: '/d/map/rider/:id',
    builder: (context, state) => DispatchMap(focusRiderId: state.pathParameters['id']),
  ),
  GoRoute(path: '/d/riders', builder: (context, state) => const RidersList()),
  // Chat 1-a-1 con un rider. Mismo widget que usa el rider en /r/chat.
  GoRoute(
    path: '/d/chat/:id',
    builder: (context, state) => ChatScreen(
      riderId: state.pathParameters['id']!,
      title: state.uri.queryParameters['name'] ?? 'Rider',
    ),
  ),
  GoRoute(
    path: '/d/orders/:id',
    builder: (context, state) => OrderDetail(id: state.pathParameters['id']!),
  ),
];
