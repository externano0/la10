/// Servicio FCM para Android/iOS.
///
/// Estrategia:
/// - Mandamos payload hibrido (`notification` + `data`) desde `send-push`.
/// - El SO Android muestra la heads-up con sonido + vibración via el campo
///   `notification` y el `channel_id` que matchea el canal creado acá.
///   Esto funciona incluso si la app está killed / MIUI mata el background.
/// - El campo `data` lo usamos para enrutar cuando el rider toca la notif
///   (vamos a `/r/offers` donde el guard de realtime levanta el popup).
/// - El popup full-screen de Flutter aparece dentro de la app cuando el
///   rider la abre — eso ya andaba antes y sigue.
///
/// Antes intentamos `flutter_local_notifications` con `fullScreenIntent`
/// para pintar pantalla completa estilo "llamada entrante", pero en
/// Android 14+ requiere un permiso especial restringido a apps de calling
/// y en MIUI/Xiaomi se traba con battery saver. Volvemos al payload hibrido
/// que sí llega siempre — sacrificamos el efecto "incoming call full-screen"
/// por garantía de que el rider se entera.

import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:la10_data/la10_data.dart';

bool _firebaseReady = false;

/// Canal Android que matchea `channel_id` que manda send-push.
const _offersChannel = AndroidNotificationChannel(
  'la10_offers_call',
  'Ofertas de entrega',
  description: 'Suena fuerte cuando llega una oferta.',
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

  // Solo necesitamos local_notifications para CREAR el canal HIGH importance
  // que después usa FCM al recibir el push. No mostramos notifs custom.
  await _localNotifs.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
  );
  await _localNotifs
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_offersChannel);

  // Permiso para mostrar notificaciones (Android 13+ lo pide explícito).
  await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);

  // App en background y el user tocó la notificación.
  FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

  // App estaba cerrada y se abrió por tocar la notif.
  final initial = await FirebaseMessaging.instance.getInitialMessage();
  if (initial != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleTap(initial));
  }
}

void _handleTap(RemoteMessage m) {
  final type = m.data['type'] as String?;
  if (type == 'offer') {
    _navigate?.call('/r/offers');
  }
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
