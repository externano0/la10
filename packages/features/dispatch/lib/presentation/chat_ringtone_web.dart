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
  _tone(ctx: ctx, freq: 1568, start: now, dur: 0.18);
  _tone(ctx: ctx, freq: 1318, start: now + 0.22, dur: 0.22);
}

void _tone({
  required web.AudioContext ctx,
  required double freq,
  required double start,
  required double dur,
}) {
  final osc = ctx.createOscillator();
  osc.type = 'sine';
  osc.frequency.value = freq;
  final gain = ctx.createGain();
  gain.gain
    ..setValueAtTime(0, start)
    ..linearRampToValueAtTime(0.4, start + 0.02)
    ..setValueAtTime(0.4, start + dur - 0.04)
    ..linearRampToValueAtTime(0, start + dur);
  osc.connect(gain);
  gain.connect(ctx.destination);
  osc.start(start);
  osc.stop(start + dur);
}
