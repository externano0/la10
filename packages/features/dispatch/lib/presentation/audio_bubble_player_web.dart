/// Burbuja de chat con audio: botón play/pause + duración.
///
/// Estrategia simple para v1:
///  - Cuando el usuario toca play, pedimos una signed URL al storage privado
///    y la pasamos a un HTMLAudioElement.
///  - Mientras suena cambiamos el ícono a pause.
///  - Cuando termina vuelve a play.
/// La progress bar y scrubbing se dejan para una próxima iteración.

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:la10_data/la10_data.dart';
import 'package:web/web.dart' as web;

class AudioBubblePlayer extends StatefulWidget {
  const AudioBubblePlayer({
    super.key,
    required this.message,
    required this.foreground,
  });

  final ChatMessage message;

  /// Color del texto y del ícono — depende de si la burbuja es propia o ajena.
  final Color foreground;

  @override
  State<AudioBubblePlayer> createState() => _AudioBubblePlayerState();
}

class _AudioBubblePlayerState extends State<AudioBubblePlayer> {
  web.HTMLAudioElement? _audio;
  bool _loading = false;
  bool _playing = false;
  String? _error;

  @override
  void dispose() {
    _audio?.pause();
    super.dispose();
  }

  Future<void> _toggle() async {
    final a = _audio;
    if (a != null) {
      if (_playing) {
        a.pause();
      } else {
        await a.play().toDart;
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final url = await ChatRepository.instance
          .signedAudioUrl(widget.message.audioUrl!);
      final audio = web.HTMLAudioElement();
      audio.src = url;
      audio.addEventListener('play', ((web.Event _) {
        if (mounted) setState(() => _playing = true);
      }).toJS);
      audio.addEventListener('pause', ((web.Event _) {
        if (mounted) setState(() => _playing = false);
      }).toJS);
      audio.addEventListener('ended', ((web.Event _) {
        if (mounted) setState(() => _playing = false);
      }).toJS);
      await audio.play().toDart;
      _audio = audio;
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDuration(int? ms) {
    if (ms == null) return '0:00';
    final d = Duration(milliseconds: ms);
    final mm = d.inMinutes.toString();
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          color: widget.foreground,
          onPressed: _loading ? null : _toggle,
          icon: _loading
              ? SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: widget.foreground,
                  ),
                )
              : Icon(_playing ? Icons.pause_circle : Icons.play_circle, size: 32),
        ),
        const SizedBox(width: 8),
        Icon(Icons.graphic_eq, color: widget.foreground.withValues(alpha: 0.7)),
        const SizedBox(width: 8),
        Text(
          _formatDuration(widget.message.audioDurationMs),
          style: TextStyle(color: widget.foreground),
        ),
        if (_error != null) ...[
          const SizedBox(width: 8),
          Icon(Icons.error_outline, color: Colors.red.shade300, size: 18),
        ],
      ],
    );
  }
}
