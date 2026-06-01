/// Servicio FCM para Android/iOS con notificación tipo "llamada entrante".
///
/// Estrategia:
/// - send-push manda payload DATA-only (sin campo `notification`) para
///   que el SO no muestre la heads-up genérica de mensaje. El cliente
///   construye la notificación con flutter_local_notifications.
/// - Usamos categoría `call` + `fullScreenIntent: true` + canal HIGH
///   importance → en Android el SO pinta la pantalla completa estilo
///   "llamada entrante" si la app tiene el permiso USE_FULL_SCREEN_INTENT
///   (que ya pedimos en el sheet "Estoy en línea"). Si no, cae a heads-up
///   persistente con sonido fuerte y vibración.
/// - `ongoing: true` hace que la notificación no se pueda deslizar para
///   descartar — el rider tiene que tocar para entrar a /r/offers.
///
/// IMPORTANTE: el handler de background tiene que ser top-level (no closure)
/// y registrar Firebase + flutter_local_notifications en su propio isolate.

import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:la10_data/la10_data.dart';

bool _firebaseReady = false;

/// Canal Android — match con el `channel_id` que mandaba send-push antes,
/// pero ahora se crea desde el cliente con todos los flags de "call style".
const _offersChannel = AndroidNotificationChannel(
  'la10_offers_call',
  'Ofertas de entrega',
  description: 'Suena tipo llamada cuando llega una oferta de entrega.',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

final _localNotifs = FlutterLocalNotificationsPlugin();

/// Callback que el app inyecta para navegar cuando llega una notificación.
void Function(String path)? _navigate;

void setFcmNavigator(void Function(String path) navigate) {
  _navigate = navigate;
}

Future<void> initFcm() async {
  if (_firebaseReady) return;
  await Firebase.initializeApp();
  _firebaseReady = true;

  // Init local_notifications + creación del canal HIGH importance.
  await _localNotifs.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
    onDidReceiveNotificationResponse: _onLocalNotifTap,
  );
  await _localNotifs
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_offersChannel);

  // Permiso de notificaciones (Android 13+ lo pide explícito).
  await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);

  // Handlers de FCM.
  FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);
  FirebaseMessaging.onMessage.listen(_showOfferNotification);
  FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
  final initial = await FirebaseMessaging.instance.getInitialMessage();
  if (initial != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleTap(initial));
  }
}

/// Top-level: FCM lo invoca desde otro isolate cuando la app está en
/// background o cerrada. Re-inicializamos lo necesario.
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await _localNotifs.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
  );
  await _localNotifs
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_offersChannel);
  await _showOfferNotification(message);
}

Future<void> _showOfferNotification(RemoteMessage m) async {
  final type = m.data['type'] as String?;
  if (type != 'offer') return;
  final title = (m.data['title'] as String?) ?? '¡Nueva oferta!';
  final body = (m.data['body'] as String?) ?? 'Tenés una entrega esperando.';
  final orderId = m.data['order_id'] as String? ?? '';

  await _localNotifs.show(
    1001, // id fijo: una oferta nueva sobreescribe la anterior si hubiera.
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        _offersChannel.id,
        _offersChannel.name,
        channelDescription: _offersChannel.description,
        importance: Importance.max,
        priority: Priority.max,
        // Estos flags juntos disparan el popup full-screen estilo "llamada":
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
        visibility: NotificationVisibility.public,
        // Persistente: no se desliza, el rider tiene que tocar.
        ongoing: true,
        autoCancel: false,
        playSound: true,
        enableVibration: true,
        ticker: title,
        // Color rojo para resaltar como "urgente / llamada".
        color: const Color(0xFFD32F2F),
        colorized: true,
        styleInformation: BigTextStyleInformation(body, contentTitle: title),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    ),
    payload: orderId,
  );
}

void _handleTap(RemoteMessage m) {
  final type = m.data['type'] as String?;
  if (type == 'offer') {
    _navigate?.call('/r/offers');
  }
}

void _onLocalNotifTap(NotificationResponse r) {
  // Cuando el user toca la local notification que mostramos nosotros.
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
