/// Stub para web: en el browser no usamos FCM (es solo para mobile native).
/// En web ya tenemos realtime + ringtone vía Web Audio. Si quisiéramos push
/// real en web, habría que setup VAPID + service worker — out of scope.

Future<void> initFcm() async {}
Future<void> registerFcmToken() async {}
