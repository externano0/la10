/// Servicio FCM para Android/iOS.
///
/// Flujo:
/// 1. `initFcm()` se llama en `main.dart` antes de `runApp`.
///    Inicializa Firebase y registra el handler de mensajes en background.
/// 2. `registerFcmToken()` se llama después del login del rider.
///    Pide permiso de notificaciones, obtiene el token del device y lo
///    upsertea en `public.fcm_tokens` (RLS lo limita a la fila del propio user).
/// 3. La edge fn `dispatch-order` llama a `send-push` que arma el payload FCM
///    y lo despacha. FCM se encarga de despertar al celu y mostrar la notif.

import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:la10_data/la10_data.dart';

bool _firebaseReady = false;

Future<void> initFcm() async {
  if (_firebaseReady) return;
  await Firebase.initializeApp();
  _firebaseReady = true;
  // Background handler — TIENE que ser top-level (no closure). Lo registramos
  // acá una vez; el dispatcher de Flutter lo despierta cuando llega un push
  // con la app cerrada.
  FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);
}

/// Top-level porque FCM lo invoca desde un isolate aparte cuando la app
/// está en background. NO puede capturar estado del isolate principal.
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  // Por ahora no hacemos nada custom; FCM ya muestra la heads-up.
  // En el futuro: setear estado local, prefetch de la orden, etc.
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
