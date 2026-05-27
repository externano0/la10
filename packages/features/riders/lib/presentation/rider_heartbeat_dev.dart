import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:la10_data/la10_data.dart';

class RiderHeartbeatDev extends StatefulWidget {
  const RiderHeartbeatDev({super.key});
  @override
  State<RiderHeartbeatDev> createState() => _RiderHeartbeatDevState();
}

class _RiderHeartbeatDevState extends State<RiderHeartbeatDev> {
  final _lat = TextEditingController(text: '-34.603');
  final _lng = TextEditingController(text: '-58.387');
  bool _busy = false;
  String? _msg;

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      await RidersRepository.instance.sendHeartbeat(
        lat: double.parse(_lat.text),
        lng: double.parse(_lng.text),
      );
      setState(() => _msg = '✅ Ubicación enviada');
    } catch (e) {
      setState(() => _msg = '❌ $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Heartbeat (dev)'),
        leading: BackButton(onPressed: () => context.go('/r/home')),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Mandar lat/lng manual contra la edge fn rider-heartbeat.'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _lat,
                    decoration: const InputDecoration(labelText: 'Lat'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _lng,
                    decoration: const InputDecoration(labelText: 'Lng'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _send,
              child: _busy
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Enviar heartbeat'),
            ),
            if (_msg != null) ...[
              const SizedBox(height: 16),
              Text(_msg!),
            ],
          ],
        ),
      ),
    );
  }
}
