/// Implementación mobile (Android/iOS) del aviso de oferta nueva.
///
/// Estrategia:
///  - Vibración fuerte: tres pulsos largos. Esto despierta al rider incluso
///    en silencio.
///  - Sonido del sistema (ringtone de alarma). Es ALTO y se diferencia de
///    cualquier notificación común.
/// Como NO es push real, esto solo funciona si la app está corriendo
/// (foreground o background reciente). Push real requiere FCM, próxima
/// iteración.

import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:vibration/vibration.dart';

void warmUp() {/* nada que warmupear en mobile */}

Future<void> play() async {
  // Vibración prioritaria: aunque el celu esté en silencio se siente.
  try {
    final hasVibrator = (await Vibration.hasVibrator()) ?? false;
    if (hasVibrator) {
      // 0ms espera + 600ms vibra + 200ms pausa + 600ms vibra + 200ms pausa + 600ms vibra
      await Vibration.vibrate(pattern: [0, 600, 200, 600, 200, 600], intensities: [0, 255, 0, 255, 0, 255]);
    }
  } catch (_) {/* algunos devices no soportan pattern; ignoramos */}

  // Ringtone de alarma del sistema: alto y distinto de una notificación.
  try {
    FlutterRingtonePlayer().play(
      android: AndroidSounds.alarm,
      ios: IosSounds.alarm,
      looping: false,
      volume: 1.0,
      asAlarm: true,
    );
  } catch (_) {}
}
