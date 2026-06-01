/// Picker de ubicación en mapa para marcar un local o un destino.
/// Reemplaza los campos manuales lat/lng que nadie sabía completar.
///
/// Flujo:
///   1. Centra el mapa en GPS del device si tiene permiso.
///   2. Banner de búsqueda arriba — el user escribe "juarez celman 2871" y
///      con Nominatim (OSM gratis) le devolvemos hasta 5 resultados. Tocar
///      uno mueve el mapa + marca el punto. Esto evita tener que pinchar
///      la cuadra a ojo.
///   3. Tocar el mapa permite ajustar la posición exacta (el geocoder suele
///      caer a media cuadra del número exacto).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:la10_geo/la10_geo.dart' as geo;
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
  final _searchCtl = TextEditingController();
  final _nominatim = geo.NominatimClient();
  LatLng? _selected;
  bool _locating = false;
  bool _searching = false;
  List<geo.NominatimHit> _results = const [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    if (_selected == null) _tryGps();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
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
    } catch (_) {/* sin GPS: el user puede tocar el mapa o usar el buscador */} finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _onSearchChanged(String value) {
    // Debounce simple: esperamos 400ms después del último tecleo para no
    // bombardear Nominatim (tiene rate limit de ~1 req/seg).
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 3) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    setState(() => _searching = true);
    final hits = await _nominatim.search(q, limit: 5);
    if (!mounted) return;
    setState(() {
      _results = hits;
      _searching = false;
    });
  }

  void _selectHit(geo.NominatimHit hit) {
    final point = LatLng(hit.lat, hit.lng);
    setState(() {
      _selected = point;
      _results = const [];
      _searchCtl.text = hit.displayName;
    });
    // Pequeño delay para que el setState termine antes de mover el mapa.
    WidgetsBinding.instance.addPostFrameCallback((_) => _ctl.move(point, 17));
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final center = _selected ?? const LatLng(-34.6037, -58.3816);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Marcá tu ubicación'),
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
          // Buscador arriba — typeahead con Nominatim.
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: _SearchBar(
              controller: _searchCtl,
              searching: _searching,
              results: _results,
              onChanged: _onSearchChanged,
              onHitTap: _selectHit,
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
            label: Text(_selected == null
                ? 'Buscá o tocá el mapa para elegir'
                : 'Confirmar ubicación'),
          ),
        ),
      ),
    );
  }
}

/// Caja de búsqueda + lista colapsable de resultados. La lista se muestra
/// flotando sobre el mapa para que el user pueda ver el contexto mientras
/// elige.
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.searching,
    required this.results,
    required this.onChanged,
    required this.onHitTap,
  });

  final TextEditingController controller;
  final bool searching;
  final List<geo.NominatimHit> results;
  final ValueChanged<String> onChanged;
  final void Function(geo.NominatimHit) onHitTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: 'Buscar dirección (calle y número)',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : (controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            controller.clear();
                            onChanged('');
                          },
                        )),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              filled: true,
            ),
          ),
          if (results.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: results.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final h = results[i];
                  return ListTile(
                    leading: const Icon(Icons.place),
                    title: Text(h.displayName, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => onHitTap(h),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
