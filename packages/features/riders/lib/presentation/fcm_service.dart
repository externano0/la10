/// Wrapper que delega a la implementación mobile (Android/iOS) o stub (web).
export 'fcm_service_stub.dart'
    if (dart.library.io) 'fcm_service_mobile.dart';
