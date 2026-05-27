import 'package:go_router/go_router.dart';
import 'package:la10_data/la10_data.dart';
import 'package:la10_dispatch/la10_dispatch.dart';

import 'rider_active_order.dart';
import 'rider_heartbeat_dev.dart';
import 'rider_home.dart';
import 'rider_offers.dart';

final ridersRoutes = <RouteBase>[
  GoRoute(path: '/r/home', builder: (context, state) => const RiderHome()),
  GoRoute(path: '/r/offers', builder: (context, state) => const RiderOffers()),
  // Detalle del pedido activo: mapa, dinero, acciones.
  GoRoute(
    path: '/r/orders/:id',
    builder: (context, state) =>
        RiderActiveOrder(orderId: state.pathParameters['id']!),
  ),
  // El rider abre su propio hilo de chat con el jefe.
  GoRoute(
    path: '/r/chat',
    builder: (context, state) {
      final uid = La10Supabase.auth.currentUser?.id ?? '';
      return ChatScreen(riderId: uid, title: 'Chat con el dispatch');
    },
  ),
  GoRoute(path: '/r/dev/heartbeat', builder: (context, state) => const RiderHeartbeatDev()),
];
