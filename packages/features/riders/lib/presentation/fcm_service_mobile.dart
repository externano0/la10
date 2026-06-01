/// Servicio FCM para Android/iOS con notificaciones estilo "llamada entrante".
///
/// Flujo:
/// 1. `initFcm()` (main.dart) inicializa Firebase, crea el canal high-importance
///    en Android y registra los handlers (background + tap + foreground).
/// 2. `registerFcmToken()` después del login del rider — pide permiso, upserta
///    el token en `public.fcm_tokens`.
/// 3. Edge fn `dispatch-order` llama `send-push` con `data-only` (no campo
///    `notification`) — así el cliente controla la UI 100%.
/// 4. Llega un push:
///    - App foreground → `onMessage`: el guard de realtime ya levanta el popup,
///      no duplicamos.
///    - App background / cerrada → `_fcmBackgroundHandler`: mostramos una
///      local notification con `fullScreenIntent: true` + canal `la10_offers`
///      (HIGH importance, sonido, vibración) → Android pinta la pantalla
///      completa estilo "llamada entrante" si el celu está bloqueado.
/// 5. Tap en la notif → `onMessageOpenedApp` (o `getInitialMessage` si la app
///    estaba cerrada) → navegamos a `/r/offers`, donde el guard despierta el
///    popup full-screen de Flutter automáticamente.

import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:la10_data/la10_data.dart';

bool _firebaseReady = false;

/// Canal Android para las ofertas — high importance para que se vea heads-up
/// y se pueda combinar con fullScreenIntent. El id tiene que coincidir con
/// el `channel_id` que manda `send-push`.
const _offersChannel = AndroidNotificationChannel(
  'la10_offers',
  'Ofertas de entrega',
  description: 'Suena fuerte cuando llega una oferta de entrega.',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

final _localNotifs = FlutterLocalNotificationsPlugin();

/// Callback que el app inyecta para navegar cuando llega una notificación.
/// Lo usamos en vez de un GlobalKey porque MaterialApp.router maneja su
/// propio Navigator interno (GoRouter) y un GlobalKey externo no tiene
/// acceso. El app llama `setFcmNavigator((path) => router.go(path))` en
/// startup.
void Function(String path)? _navigate;

void setFcmNavigator(void Function(String path) navigate) {
  _navigate = navigate;
}

Future<void> initFcm() async {
  if (_firebaseReady) return;
  await Firebase.initializeApp();
  _firebaseReady = true;

  // Init de local notifications + creación del canal.
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

  FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);

  // Foreground: el guard de realtime ya levanta el popup, así que acá no
  // duplicamos UI — pero mostramos también el notification por si el rider
  // bajó la app a background entre el push y el onMessage.
  FirebaseMessaging.onMessage.listen(_showOfferNotification);

  // App en background y el user tocó la notificación.
  FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

  // App estaba cerrada y se abrió por tocar la notif.
  final initial = await FirebaseMessaging.instance.getInitialMessage();
  if (initial != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleTap(initial));
  }
}

/// Top-level porque FCM lo invoca desde un isolate aparte cuando la app
/// está en background. NO puede capturar estado del isolate principal.
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  // Necesitamos re-init de Firebase + plugin acá (otro isolate).
  await Firebase.initializeApp();
  await _localNotifs.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
  );
  await _showOfferNotification(message);
}

Future<void> _showOfferNotification(RemoteMessage m) async {
  final type = m.data['type'] as String?;
  if (type != 'offer') return;
  final title = (m.notification?.title ?? m.data['title'] as String?) ?? '¡Nueva oferta!';
  final body = (m.notification?.body ?? m.data['body'] as String?) ?? 'Tenés una entrega esperando.';
  final payload = m.data['order_id'] as String? ?? '';

  await _localNotifs.show(
    // Un id fijo así si llega otra oferta se sobreescribe la anterior.
    1001,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        _offersChannel.id,
        _offersChannel.name,
        channelDescription: _offersChannel.description,
        importance: Importance.max,
        priority: Priority.max,
        // Esto es lo que dispara el popup pantalla completa estilo llamada.
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
        visibility: NotificationVisibility.public,
        ongoing: false,
        autoCancel: true,
        playSound: true,
        enableVibration: true,
        ticker: title,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    ),
    payload: payload,
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

  // Permiso (Android 13+ lo pide explícito; iOS siempre).
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

  // Si Firebase rota el token, lo re-upserteamos.
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
