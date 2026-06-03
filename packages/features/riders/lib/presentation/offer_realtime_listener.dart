/// Listener global que escucha ofertas nuevas via websocket Supabase y
/// dispara el popup tipo llamada SIN pasar por FCM.
///
/// Para qué sirve:
/// En OEMs agresivos (ZTE Nubia / MIUI / Samsung) el FCM se vuelve poco
/// confiable cuando la app no está usándose activamente — aún con todos
/// los permisos en orden el SO bloquea la entrega de pushes. El user
/// terminaba reportando "el pop solo anda la primera vez".
///
/// Esta solucion bypassea FCM totalmente:
/// 1. Mientras el rider esta "available", el foreground service del
///    GPS (geolocator) mantiene viva el proceso Dart del app.
/// 2. Este listener mantiene un subscribe a `dispatch_offers` filtrado
///    por `rider_id = self` (websocket Supabase, no FCM).
/// 3. Cuando llega un INSERT con una oferta nueva, fetcheamos el detalle
///    de la orden y disparamos `showCallkitIncoming` con todos los datos.
/// 4. El plugin callkit dedupea por `id`, asi que si llega tambien por
///    FCM (caso fallback que igual sigue activo) no se duplica.
///
/// La FCM queda como red de seguridad para casos donde el websocket caiga
/// (pierde red, etc), pero el camino principal es realtime.

import 'dart:async';

import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:la10_data/la10_data.dart';

StreamSubscription<List<Offer>>? _offersSub;
StreamSubscription? _authSub;
final _seenOfferIds = <String>{};
bool _primed = false;

/// Arranca el listener al boot del app (despues de Supabase.init).
/// Es idempotente — segundo call no hace nada.
void startOfferRealtimeListener() {
  // Si el user esta logueado al boot, suscribir inmediatamente.
  if (La10Supabase.auth.currentUser != null) {
    _subscribe();
  }
  // Y re-suscribir cuando cambia el auth state (login / logout).
  _authSub ??= La10Supabase.auth.onAuthStateChange.listen((event) {
    final user = event.session?.user;
    if (user != null) {
      _subscribe();
    } else {
      _unsubscribe();
    }
  });
}

void _subscribe() {
  // Si ya estamos subscritos, no hacer nada.
  if (_offersSub != null) return;
  _primed = false;
  _seenOfferIds.clear();
  _offersSub = OffersRepository.instance
      .watchMyPending()
      .listen(_onOffersSnapshot, onError: (_) {
    // El stream puede caerse por red; el cliente Supabase reconecta solo.
  });
}

void _unsubscribe() {
  _offersSub?.cancel();
  _offersSub = null;
  _primed = false;
  _seenOfferIds.clear();
}

/// Procesa cada snapshot del stream:
/// - Primera vez: marcamos todo como "ya visto" (para no disparar el popup
///   con ofertas viejas que ya existian en la DB cuando arrancaste).
/// - Despues: cualquier ID que no estaba antes = oferta nueva → callkit.
Future<void> _onOffersSnapshot(List<Offer> offers) async {
  if (!_primed) {
    _primed = true;
    _seenOfferIds.addAll(offers.map((o) => o.id));
    return;
  }
  for (final offer in offers) {
    if (_seenOfferIds.add(offer.id)) {
      await _showCallForOffer(offer);
    }
  }
}

Future<void> _showCallForOffer(Offer offer) async {
  // Fetcheamos el detalle del order para mostrar monto + pickup + dropoff
  // adentro del popup callkit.
  String pickup = 'Retiro';
  String dropoff = 'Entrega';
  String amount = '';
  try {
    final order = await OrdersRepository.instance.getById(offer.orderId);
    if (order != null) {
      pickup = order.pickupAddress;
      dropoff = order.dropoffAddress;
      if (order.totalAmountCents != null) {
        amount = (order.totalAmountCents! / 100).toStringAsFixed(0);
      }
    }
  } catch (_) {/* sin info de orden, igual lanzamos el popup */}

  final params = CallKitParams(
    // El id se usa para dedupe — si el push FCM tambien dispara, el plugin
    // ve que es el mismo id y no muestra otro popup.
    id: offer.orderId,
    nameCaller: 'Oferta de entrega',
    appName: 'La 10',
    handle: amount.isNotEmpty ? '\$$amount' : '$pickup → $dropoff',
    type: 0,
    duration: 30000,
    textAccept: 'Aceptar',
    textDecline: 'Rechazar',
    missedCallNotification: const NotificationParams(
      showNotification: false,
      isShowCallback: false,
      subtitle: 'Perdiste una oferta',
    ),
    extra: {
      'offer_id': offer.id,
      'order_id': offer.orderId,
      'pickup': pickup,
      'dropoff': dropoff,
      'amount': amount,
    },
    android: const AndroidParams(
      isCustomNotification: true,
      isShowLogo: true,
      ringtonePath: 'system_ringtone_default',
      backgroundColor: '#D32F2F',
      actionColor: '#4CAF50',
      incomingCallNotificationChannelName: 'la10_offers_call',
    ),
    ios: const IOSParams(
      iconName: 'CallKitLogo',
      handleType: 'generic',
      supportsVideo: false,
      maximumCallGroups: 1,
      maximumCallsPerCallGroup: 1,
      ringtonePath: 'system_ringtone_default',
    ),
  );
  await FlutterCallkitIncoming.showCallkitIncoming(params);
}

