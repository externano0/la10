/// Ding-dong corto que avisa al rider de un mensaje de chat nuevo.
/// Distinto del [OfferRingtone] para que el rider no confunda urgencia.

import 'chat_ringtone_stub.dart'
    if (dart.library.js_interop) 'chat_ringtone_web.dart' as impl;

class ChatRingtone {
  ChatRingtone._();
  static final instance = ChatRingtone._();

  void warmUp() => impl.warmUp();
  Future<void> play() => impl.play();
}
