/// Sirena fuerte sintetizada que avisa al rider de una oferta nueva.
/// Web usa Web Audio API; Android/iOS por ahora son no-op (la notificación
/// nativa se sumará cuando agreguemos push).

import 'offer_ringtone_stub.dart'
    if (dart.library.js_interop) 'offer_ringtone_web.dart' as impl;

class OfferRingtone {
  OfferRingtone._();
  static final instance = OfferRingtone._();

  /// Llamar tras un gesto del usuario para "despertar" el audio (solo web).
  void warmUp() => impl.warmUp();

  Future<void> play() => impl.play();
}
