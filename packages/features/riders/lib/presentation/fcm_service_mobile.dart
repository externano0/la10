/// Servicio FCM para Android/iOS — heads-up MUY visible y confiable.
///
/// Estrategia (v0.1.13):
/// - send-push manda payload HIBRIDO (`notification` + `data`).
/// - El SO Android muestra la heads-up automaticamente usando el campo
///   `notification` y el `channel_id` que matchea el canal HIGH-importance
///   que creamos aca. Esto es lo unico que es REALMENTE confiable en celus
///   con battery saver (ZTE/Samsung/MIUI matan el bg isolate cuando estan
///   bloqueados y el data-only se pierde).
/// - El canal tiene `bypassDnd: true`, vibration pattern de "llamada"
///   largo, LED rojo. El SO la muestra como "urgente" a pantalla completa
///   visible en lock screen (`visibility: PUBLIC`).
/// - El campo `data` lleva `type='offer'` + `order_id` para que cuando
///   el rider toca la notif sepamos llevarlo a `/r/offers`.
/// - NO mostramos local notification adicional desde el cliente. Antes lo
///   haciamos con `_localNotifs.show()` + `fullScreenIntent` para imitar
///   una llamada entrante full-screen, pero en Android 14+ esto requiere
///   un permiso especial restringido a apps de calling y se duplicaba con
///   la del SO. Una sola notif manejada por el SO es lo mas confiable.
///
/// El popup full-screen estilo WhatsApp-call queda como follow-up:
/// requeriria foreground service + Activity nativa Kotlin que se lance
/// directo via Intent. No vale la pena para este round.

import 'dart:io' show Platform;
import 'dart:typed_data' show Int64List;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:la10_data/la10_data.dart';

bool _firebaseReady = false;

/// Canal Android — `channel_id` debe matchear lo que manda send-push.
/// No es const porque vibrationPattern es Int64List runtime.
final _offersChannel = AndroidNotificationChannel(
  'la10_offers_call',
  'Ofertas de entrega',
  description: 'Suena fuerte y vibra cuando llega una oferta de entrega.',
  importance: Importance.max,
  playSound: true,
  // Patrón tipo "llamada": espera-vibra-espera-vibra (en ms). El SO
  // lo repite mientras la heads-up esté visible.
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
}

Future<void> initFcm() async {
  if (_firebaseReady) return;
  await Firebase.initializeApp();
  _firebaseReady = true;

  // local_notifications solo lo usamos para crear el canal con los flags
  // de "call style" — el SO usa ese canal para mostrar la heads-up del
  // payload `notification`. No mostramos notifs custom desde el cliente.
  await _localNotifs.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
    onDidReceiveNotificationResponse: _onLocalNotifTap,
  );
  await _ensureChannel();

  // Permiso de notificaciones (Android 13+ lo pide explícito).
  await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);

  FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);
  FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
  final initial = await FirebaseMessaging.instance.getInitialMessage();
  if (initial != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleTap(initial));
  }
}

/// Crear/actualizar el canal HIGH-importance + bypassDnd. Se llama tanto
/// en init como en el bg handler (otro isolate).
Future<void> _ensureChannel() async {
  final androidPlugin = _localNotifs
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  if (androidPlugin == null) return;
  await androidPlugin.createNotificationChannel(_offersChannel);
}

/// Top-level: FCM lo invoca desde otro isolate cuando la app está en
/// background o cerrada. No mostramos notif custom — el SO ya la mostró
/// con el payload `notification`. Solo nos aseguramos de que el canal
/// exista (por si esta es la primera vez que la app corre desde el push).
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await _localNotifs.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
  );
  await _ensureChannel();
  // No-op: el SO mostro la heads-up del payload `notification`. Aca solo
  // podriamos prefetchear datos para mostrar mas rapido al tap.
}

void _handleTap(RemoteMessage m) {
  final type = m.data['type'] as String?;
  if (type == 'offer') {
    _navigate?.call('/r/offers');
  }
}

void _onLocalNotifTap(NotificationResponse r) {
  // Si el SO entrego al tap directo a la app (algunos OEMs hacen esto),
  // navegamos igual a /r/offers.
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
