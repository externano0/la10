/// Botón para grabar y enviar audios en el chat.
/// La implementación real vive en `audio_recorder_web.dart` (Web MediaRecorder).
/// En mobile se muestra un placeholder hasta que integremos `record` package.

export 'audio_recorder_stub.dart'
    if (dart.library.js_interop) 'audio_recorder_web.dart';
