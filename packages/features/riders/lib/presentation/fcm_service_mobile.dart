/// Servicio FCM para Android/iOS.
///
/// Flujo:
/// 1. `initFcm()` se llama en `main.dart` antes de `runApp`.
///    Inicializa Firebase y registra los handlers de push (background + tap).
/// 2. `registerFcmToken()` se llama después del login del rider.
///    Pide permiso de notificaciones, obtiene el token del device y lo
///    upsertea en `public.fcm_tokens` (RLS lo limita a la fila del propio user).
/// 3. La edge fn `dispatch-order` llama a `send-push` que arma el payload FCM
///    y lo despacha. FCM se encarga de despertar al celu y mostrar la notif.
/// 4. Cuando el rider toca la notificación (app en background o cerrada) la
///    abrimos en `/r/offers` — ahí el guard del rider levanta el popup
///    full-screen vía el stream realtime de Supabase.

import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:la10_data/la10_data.dart';

bool _firebaseReady = false;

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
  FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);

  // App en background y el user tocó la notificación.
  FirebaseMessaging.onMessageOpenedApp.listen((m) {
    _handleTap(m);
  });
  // App estaba cerrada y se abrió por tocar la notif.
  final initial = await FirebaseMessaging.instance.getInitialMessage();
  if (initial != null) {
    // Damos tiempo a que el navigator esté listo antes de navegar.
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleTap(initial));
  }
}

void _handleTap(RemoteMessage m) {
  final type = m.data['type'] as String?;
  // Por ahora solo manejamos 'offer'; en el futuro 'chat', 'order_update', etc.
  if (type == 'offer') {
    _navigate?.call('/r/offers');
  }
}

/// Top-level porque FCM lo invoca desde un isolate aparte cuando la app
/// está en background. NO puede capturar estado del isolate principal.
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  // FCM ya muestra la heads-up. En el futuro acá podemos usar
  // flutter_local_notifications para mostrar full-screen intent estilo
  // llamada entrante (USE_FULL_SCREEN_INTENT). Ahora dependemos del popup
  // que se levanta dentro de la app cuando el rider la abre.
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
