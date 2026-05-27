/// Mobile: tono notification + vibración corta.
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:vibration/vibration.dart';

void warmUp() {}

Future<void> play() async {
  try {
    final hasVibrator = (await Vibration.hasVibrator()) ?? false;
    if (hasVibrator) await Vibration.vibrate(duration: 300);
  } catch (_) {}
  try {
    FlutterRingtonePlayer().play(
      android: AndroidSounds.notification,
      ios: IosSounds.glass,
      looping: false,
      volume: 0.8,
    );
  } catch (_) {}
}
