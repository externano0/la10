/// Reproductor de audio dentro de una burbuja de chat.
/// Web usa HTMLAudioElement; mobile muestra un placeholder por ahora.

export 'audio_bubble_player_stub.dart'
    if (dart.library.js_interop) 'audio_bubble_player_web.dart';
