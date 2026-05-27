/// Implementación Web del ringtone de oferta vía Web Audio API.

import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

web.AudioContext? _ctx;

void warmUp() {
  _ctx ??= web.AudioContext();
  if (_ctx?.state == 'suspended') _ctx?.resume();
}

Future<void> play() async {
  _ctx ??= web.AudioContext();
  final ctx = _ctx!;
  if (ctx.state == 'suspended') {
    try {
      await ctx.resume().toDart;
    } catch (_) {
      return;
    }
  }
  final now = ctx.currentTime;
  const beepDur = 0.18;
  const gap = 0.07;
  final freqs = <double>[880, 1320, 880, 1320];
  for (var i = 0; i < freqs.length; i++) {
    _beep(ctx: ctx, freq: freqs[i], start: now + i * (beepDur + gap), dur: beepDur);
  }
}

void _beep({
  required web.AudioContext ctx,
  required double freq,
  required double start,
  required double dur,
}) {
  final osc = ctx.createOscillator();
  osc.type = 'square';
  osc.frequency.value = freq;
  final gain = ctx.createGain();
  gain.gain
    ..setValueAtTime(0, start)
    ..linearRampToValueAtTime(0.55, start + 0.01)
    ..setValueAtTime(0.55, start + dur - 0.02)
    ..linearRampToValueAtTime(0, start + dur);
  osc.connect(gain);
  gain.connect(ctx.destination);
  osc.start(start);
  osc.stop(start + dur);
}
