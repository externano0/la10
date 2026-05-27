/// Placeholder no-web del grabador de audio: muestra un ícono deshabilitado.
/// Cuando agreguemos `record` package para mobile esto se reemplaza.

import 'package:flutter/material.dart';

class AudioRecorderButton extends StatelessWidget {
  const AudioRecorderButton({super.key, required this.riderId});
  final String riderId;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Grabar audio: por ahora solo desde la web'),
          ),
        );
      },
      icon: const Icon(Icons.mic_off),
      tooltip: 'Audio solo disponible en web',
    );
  }
}
