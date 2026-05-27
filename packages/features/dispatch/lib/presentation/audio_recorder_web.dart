/// Botón de "press-and-hold" (o tap-to-toggle) que graba audio del micrófono
/// vía Web MediaRecorder y lo envía como mensaje de chat.
///
/// Flujo:
///  1. Tap → pide permiso y empieza a grabar (botón rojo pulsando).
///  2. Tap de nuevo → corta la grabación, sube el blob a Storage y crea el
///     mensaje. El listener realtime se encarga de mostrarlo en la burbuja.
///
/// Implementación: usa Web APIs vía `package:web`. Solo funciona en browser
/// (web build). En mobile nativo habría que swap a `record` package, pero
/// como hoy solo deployamos a web, lo dejamos así.

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:la10_data/la10_data.dart';
import 'package:web/web.dart' as web;

class AudioRecorderButton extends StatefulWidget {
  const AudioRecorderButton({super.key, required this.riderId});

  /// Identificador del hilo. Coincide con el rider al que apunta el chat.
  final String riderId;

  @override
  State<AudioRecorderButton> createState() => _AudioRecorderButtonState();
}

class _AudioRecorderButtonState extends State<AudioRecorderButton> {
  web.MediaRecorder? _rec;
  web.MediaStream? _stream;
  final _chunks = <web.Blob>[];
  DateTime? _startedAt;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  bool _busy = false;
  String? _error;

  bool get _recording => _rec != null;

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final constraints = web.MediaStreamConstraints(audio: true.toJS);
      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(constraints)
          .toDart;
      final supported = _pickSupportedMime();
      final opts = web.MediaRecorderOptions(mimeType: supported);
      final rec = web.MediaRecorder(stream, opts);
      rec.ondataavailable = (web.BlobEvent e) {
        if (e.data.size > 0) _chunks.add(e.data);
      }.toJS;
      rec.start();
      _rec = rec;
      _stream = stream;
      _startedAt = DateTime.now();
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted || _startedAt == null) return;
        setState(() => _elapsed = DateTime.now().difference(_startedAt!));
      });
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'No se pudo grabar: $e';
        });
      }
    }
  }

  /// Mime type que la mayoría de browsers soportan; fallback a vacío.
  String _pickSupportedMime() {
    const candidates = ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4'];
    for (final c in candidates) {
      if (web.MediaRecorder.isTypeSupported(c)) return c;
    }
    return '';
  }

  Future<void> _stopAndSend() async {
    final rec = _rec;
    if (rec == null) return;
    setState(() => _busy = true);

    final completer = Completer<void>();
    rec.onstop = ((web.Event _) => completer.complete()).toJS;
    rec.stop();
    await completer.future;

    // Parar los tracks del micrófono.
    for (final t in _stream?.getTracks().toDart ?? const <web.MediaStreamTrack>[]) {
      t.stop();
    }
    _ticker?.cancel();
    final durationMs = _elapsed.inMilliseconds;
    _resetState();

    if (_chunks.isEmpty) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      // Junta los chunks en un único Blob y lo lee como bytes.
      final type = _chunks.first.type;
      final all = web.Blob(_chunks.toJS, web.BlobPropertyBag(type: type));
      final buf = await all.arrayBuffer().toDart;
      final bytes = buf.toDart.asUint8List();
      await ChatRepository.instance.sendAudio(
        riderId: widget.riderId,
        bytes: Uint8List.fromList(bytes),
        durationMs: durationMs,
        contentType: type.isNotEmpty ? type : 'audio/webm',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'No se pudo enviar: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _resetState() {
    _chunks.clear();
    _rec = null;
    _stream = null;
    _startedAt = null;
    if (mounted) setState(() => _elapsed = Duration.zero);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    if (_recording) {
      return Row(
        children: [
          IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: Colors.red),
            onPressed: _busy ? null : _stopAndSend,
            icon: const Icon(Icons.stop),
            tooltip: 'Detener y enviar',
          ),
          const SizedBox(width: 8),
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(_fmt(_elapsed)),
        ],
      );
    }
    return Tooltip(
      message: _error ?? 'Grabar audio',
      child: IconButton(
        onPressed: _busy ? null : _start,
        icon: _busy
            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.mic),
      ),
    );
  }
}
