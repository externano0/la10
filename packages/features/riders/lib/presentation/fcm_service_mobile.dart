/// Servicio FCM para Android/iOS con popup tipo llamada entrante real.
///
/// Estrategia (v0.1.14):
/// - send-push manda payload HIBRIDO (`notification` + `data`).
/// - El campo `notification` garantiza heads-up del SO aun con la app
///   matada por battery saver — ese heads-up es el fallback.
/// - El campo `data` (`type='offer'`, `order_id`, `pickup`, `dropoff`,
///   `amount`) lo lee el FCM bg handler para llamar a
///   `FlutterCallkitIncoming.showCallkitIncoming(...)` y abrir el
///   popup FULL-SCREEN tipo llamada entrante (foreground service +
///   Activity nativa que se muestra sobre el lock screen). Eso es lo
///   que el user pidio: que aparezca como una llamada y que suene
///   fuerte aunque este bloqueado, en Instagram o en el banco.
/// - El plugin maneja su propio foreground service → mantiene viva la
///   conexion y la heads-up incluso cuando el SO mata el resto.
/// - Si el bg handler no se dispara (caso extremo de OEM agresivo),
///   queda el fallback del heads-up del SO. Sigue siendo MUY visible
///   porque el canal `la10_offers_call` tiene Importance.MAX +
///   vibrationPattern de llamada + LED rojo.
/// - Eventos del popup: ACCEPT → router lleva al rider a `/r/offers`.
///   DECLINE → llama a la API de decline.

import 'dart:io' show Platform;
import 'dart:typed_data' show Int64List;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:la10_data/la10_data.dart';

/// Pending order_id que vino de un accept de callkit que ocurrió antes
/// de que el navegador estuviese listo. Lo procesamos en cuanto el app
/// inyecta el navigator via [setFcmNavigator].
String? _pendingNavOrderId;

bool _firebaseReady = false;

/// Canal Android — `channel_id` debe matchear lo que manda send-push.
/// Es el fallback si flutter_callkit_incoming no logra abrir el popup
/// full-screen (algunos OEMs muy agresivos).
final _offersChannel = AndroidNotificationChannel(
  'la10_offers_call',
  'Ofertas de entrega',
  description: 'Suena fuerte y vibra cuando llega una oferta de entrega.',
  importance: Importance.max,
  playSound: true,
  vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
  enableVibration: true,
  enableLights: true,
  ledColor: const Color(0xFFD32F2F),
);

final _localNotifs = FlutterLocalNotificationsPlugin();

/// Callback que el app inyecta para navegar cuando llega una notificación.
void Function(String path)? _navigate;

void setFcmNavigator(void Function(String path) navigate) {
  _navigate = navigate;
  // Si el callkit accept disparó antes de que el navegador esté listo
  // (caso app matada → callkit launches MainActivity → boot toma 1-2s →
  // accept event llega antes que el listener), drenamos el pending acá.
  final pending = _pendingNavOrderId;
  if (pending != null) {
    _pendingNavOrderId = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigate('/r/orders/$pending');
    });
  }
}

Future<void> initFcm() async {
  if (_firebaseReady) return;
  await Firebase.initializeApp();
  _firebaseReady = true;

  await _localNotifs.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
    onDidReceiveNotificationResponse: _onLocalNotifTap,
  );
  await _ensureChannel();

  await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);

  FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);
  FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
  final initial = await FirebaseMessaging.instance.getInitialMessage();
  if (initial != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleTap(initial));
  }

  // Eventos del popup callkit (ACCEPT/DECLINE/TIMEOUT). El popup vive
  // en otra Activity → cuando el rider toca "aceptar" emitimos un
  // evento que el app principal escucha para navegar.
  FlutterCallkitIncoming.onEvent.listen(_onCallkitEvent);

  // Caso "app matada → callkit Activity → user accept": el broadcast
  // receiver del plugin manda el evento via MethodChannel pero como el
  // Flutter engine NO estaba vivo cuando se aceptó, el evento se pierde.
  // Workaround: al bootear, consultamos activeCalls(). Si hay una con
  // order_id, asumimos que el user accepto antes y navegamos ahi.
  await _drainAcceptedCallOnBoot();
}

/// Lee llamadas activas al bootear y si encuentra una con order_id la
/// procesa (respond accepted + navigate + endCall). Cubre el caso
/// "user accepto mientras la app estaba matada".
Future<void> _drainAcceptedCallOnBoot() async {
  try {
    final result = await FlutterCallkitIncoming.activeCalls();
    if (result is! List || result.isEmpty) return;
    final call = result.first;
    if (call is! Map) return;
    final extra = call['extra'];
    if (extra is! Map) return;
    final orderId = extra['order_id']?.toString() ?? '';
    final offerId = extra['offer_id']?.toString() ?? '';
    if (orderId.isEmpty) return;
    if (offerId.isNotEmpty) {
      try {
        await OffersRepository.instance.respond(offerId, 'accepted');
      } catch (_) {/* no rompe el flow */}
    }
    _pendingNavOrderId = orderId;
    final callId = call['id']?.toString();
    if (callId != null) {
      try {
        await FlutterCallkitIncoming.endCall(callId);
      } catch (_) {/* idem */}
    }
  } catch (_) {/* no callkit / no calls */}
}

/// Crear/actualizar el canal HIGH-importance. Se llama tanto en init
/// como en el bg handler (otro isolate).
Future<void> _ensureChannel() async {
  final androidPlugin = _localNotifs
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  if (androidPlugin == null) return;
  await androidPlugin.createNotificationChannel(_offersChannel);
}

/// Top-level: FCM lo invoca desde otro isolate cuando la app esta en
/// background o cerrada. Si el `data` indica oferta, abrimos el popup
/// full-screen tipo llamada via flutter_callkit_incoming. El plugin
/// maneja foreground service + Activity con showWhenLocked.
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await _ensureChannel();
  await _maybeShowOfferCall(message);
}

Future<void> _handleForegroundMessage(RemoteMessage message) async {
  await _maybeShowOfferCall(message);
}

/// Si el payload trae `type=offer`, mostramos el popup tipo llamada.
/// El popup tiene su propio ringtone + vibration; el SO igual mostro
/// heads-up del `notification` del payload — flutter_callkit_incoming
/// la pisa con su propia notif persistente del foreground service.
Future<void> _maybeShowOfferCall(RemoteMessage message) async {
  final type = message.data['type'] as String?;
  if (type != 'offer') return;
  final orderId = (message.data['order_id'] ?? message.data['orderId'] ?? '').toString();
  final pickup = (message.data['pickup'] ?? message.data['from'] ?? 'Retiro').toString();
  final dropoff = (message.data['dropoff'] ?? message.data['to'] ?? 'Entrega').toString();
  final amount = (message.data['amount'] ?? message.data['monto'] ?? '').toString();

  final offerId = (message.data['offer_id'] ?? message.data['offerId'] ?? '').toString();
  final params = CallKitParams(
    id: orderId.isEmpty ? DateTime.now().millisecondsSinceEpoch.toString() : orderId,
    nameCaller: 'Oferta de entrega',
    appName: 'La 10',
    // En vez de numero de telefono mostramos el monto. Si no hay monto,
    // mostramos pickup → dropoff truncado.
    handle: amount.isNotEmpty ? '\$$amount' : '$pickup → $dropoff',
    type: 0, // 0 = audio call (no video).
    duration: 30000, // El popup se cierra solo a los 30s si el rider no contesta.
    textAccept: 'Aceptar',
    textDecline: 'Rechazar',
    missedCallNotification: const NotificationParams(
      showNotification: false,
      isShowCallback: false,
      subtitle: 'Perdiste una oferta',
    ),
    extra: {
      // offer_id es CRITICO — el accept handler lo usa para postear
      // respond('accepted') a la API. Si falta, la oferta queda pending
      // y el rider tiene que ir a /r/offers a aceptar manualmente.
      'offer_id': offerId,
      'order_id': orderId,
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
      audioSessionMode: 'default',
      audioSessionActive: true,
      audioSessionPreferredSampleRate: 44100.0,
      audioSessionPreferredIOBufferDuration: 0.005,
      supportsDTMF: false,
      supportsHolding: false,
      supportsGrouping: false,
      supportsUngrouping: false,
      ringtonePath: 'system_ringtone_default',
    ),
  );
  await FlutterCallkitIncoming.showCallkitIncoming(params);
}

Future<void> _onCallkitEvent(CallEvent? event) async {
  if (event == null) return;
  // El plugin envia el body con `extra` (el Map que pasamos a CallKitParams)
  // y con `id` (el field id del CallKitParams). Nosotros seteamos `id`
  // = orderId, asi que si por algun motivo el extra no deserializa bien
  // (HashMap Bundle → MethodChannel a veces se pierde en Android 13+),
  // tenemos el orderId via el id de la call como fallback confiable.
  final extra = event.body['extra'] as Map?;
  final offerId = extra?['offer_id']?.toString() ?? '';
  String orderId = extra?['order_id']?.toString() ?? '';
  if (orderId.isEmpty) {
    final id = event.body['id']?.toString() ?? '';
    // Filtramos el caso del id auto-generado por timestamp (cuando el push
    // no traia orderId — escenario edge, no deberia pasar en prod).
    if (id.isNotEmpty && int.tryParse(id) == null) {
      orderId = id;
    }
  }
  switch (event.event) {
    case Event.actionCallAccept:
      // El rider acepto desde el popup. Hacemos dos cosas:
      // 1. POST al backend respond('accepted') para marcar la offer.
      // 2. Navegar al detalle del pedido /r/orders/{orderId} con toda
      //    la info (mapa, direcciones, monto, botones de cambio de
      //    estado). Esa es la pantalla principal del rider mientras
      //    lleva el pedido.
      if (offerId.isNotEmpty) {
        try {
          await OffersRepository.instance.respond(offerId, 'accepted');
        } catch (_) {
          // No rompe el flow — si la API falla el rider lo vera en /r/offers.
        }
      }
      if (orderId.isNotEmpty) {
        if (_navigate != null) {
          _navigate!('/r/orders/$orderId');
        } else {
          // App todavia esta booteando (caso "fue lanzada por el callkit
          // accept"). Guardamos pendiente — setFcmNavigator lo dispara.
          _pendingNavOrderId = orderId;
        }
      }
      break;
    case Event.actionCallDecline:
      if (offerId.isNotEmpty) {
        try {
          await OffersRepository.instance.respond(offerId, 'declined');
        } catch (_) {/* idem */}
      }
      break;
    case Event.actionCallTimeout:
    case Event.actionCallEnded:
      break;
    default:
      break;
  }
}

void _handleTap(RemoteMessage m) {
  final type = m.data['type'] as String?;
  if (type == 'offer') {
    _navigate?.call('/r/offers');
  }
}

void _onLocalNotifTap(NotificationResponse r) {
  _navigate?.call('/r/offers');
}

Future<void> registerFcmToken() async {
  if (!_firebaseReady) return;
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(alert: true, badge: true, sound: true);
  final token = await messaging.getToken();
  if (token == null) return;
  final user = La10Supabase.auth.currentUser;
  if (user == null) return;
  final platform = Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'unknown');
  await La10Supabase.client.from('fcm_tokens').upsert({
    'user_id': user.id,
    'token': token,
    'platform': platform,
  });
  messaging.onTokenRefresh.listen((newToken) async {
    final u = La10Supabase.auth.currentUser;
    if (u == null) return;
    await La10Supabase.client.from('fcm_tokens').upsert({
      'user_id': u.id,
      'token': newToken,
      'platform': platform,
    });
  });
}
