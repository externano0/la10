/// Placeholder no-web del reproductor de audio del chat.
/// Muestra "🎤 Audio (no soportado todavía en mobile)".

import 'package:flutter/material.dart';
import 'package:la10_data/la10_data.dart';

class AudioBubblePlayer extends StatelessWidget {
  const AudioBubblePlayer({
    super.key,
    required this.message,
    required this.foreground,
  });

  final ChatMessage message;
  final Color foreground;

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
        Icon(Icons.mic, color: foreground),
        const SizedBox(width: 8),
        Text(
          '🎤 ${_formatDuration(message.audioDurationMs)} · escuchá desde la web',
          style: TextStyle(color: foreground, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}
