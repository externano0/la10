/// Picker de ubicación en mapa para que el comercio marque su local
/// tocando la pantalla. Reemplaza los campos manuales lat/lng que nadie sabía
/// completar. Centra el mapa en la ubicación del GPS si está disponible.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

/// Abre el picker como modal y devuelve el [LatLng] elegido, o null si cancela.
Future<LatLng?> pickLocationOnMap(BuildContext context, {LatLng? initial}) async {
  return Navigator.of(context).push<LatLng>(
    MaterialPageRoute(builder: (_) => MapPickerScreen(initial: initial)),
  );
}

class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key, this.initial});
  final LatLng? initial;

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final _ctl = MapController();
  LatLng? _selected;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    if (_selected == null) _tryGps();
  }

  Future<void> _tryGps() async {
    setState(() => _locating = true);
    try {
      final svc = await Geolocator.isLocationServiceEnabled();
      if (!svc) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      final l = LatLng(pos.latitude, pos.longitude);
      setState(() => _selected = l);
      WidgetsBinding.instance.addPostFrameCallback((_) => _ctl.move(l, 17));
    } catch (_) {/* sin GPS: el user puede tocar el mapa */} finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = _selected ?? const LatLng(-34.6037, -58.3816);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Marcá tu local'),
        leading: BackButton(onPressed: () => context.pop(null)),
        actions: [
          IconButton(
            tooltip: 'Usar mi ubicación',
            icon: _locating
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location),
            onPressed: _locating ? null : _tryGps,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _ctl,
            options: MapOptions(
              initialCenter: center,
              initialZoom: _selected != null ? 17 : 12,
              onTap: (_, p) => setState(() => _selected = p),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.la10.app',
                maxZoom: 19,
              ),
              if (_selected != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selected!,
                      width: 48,
                      height: 48,
                      child: const Icon(Icons.location_on, size: 48, color: Colors.red),
                    ),
                  ],
                ),
            ],
          ),
          // Banner de instrucción arriba.
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: const [
                    Icon(Icons.touch_app),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tocá el mapa donde está tu local. Podés arrastrar para ajustar.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: _selected == null ? null : () => context.pop(_selected),
            icon: const Icon(Icons.check),
            label: Text(_selected == null ? 'Tocá el mapa para elegir' : 'Confirmar ubicación'),
          ),
        ),
      ),
    );
  }
}
