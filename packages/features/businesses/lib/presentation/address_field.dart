/// Campo de dirección con autocomplete inline + mini-mapa embedded.
///
/// Flujo:
/// 1. El user escribe la dirección.
/// 2. Debajo aparecen sugerencias de Nominatim. Toca una → punto fijado.
/// 3. Alternativa: Enter o el botón lupa busca y agarra el primer hit.
/// 4. Cuando hay punto fijado, aparece **un mini-mapa debajo** mostrando
///    la ubicación. Si querés ajustar, tocás el mapa y abre el picker en
///    pantalla completa para mover el marker con precisión.
///
/// Filosofía: 90% de los comercios escriben la dirección y listo. El mapa
/// es solo confirmación visual + ajuste opcional.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:la10_geo/la10_geo.dart' as geo;
import 'package:latlong2/latlong.dart';

import 'map_picker.dart';

class AddressField extends StatefulWidget {
  const AddressField({
    super.key,
    required this.controller,
    required this.onPicked,
    this.initial,
    this.labelText = 'Dirección',
    this.hintText,
    this.validator,
  });

  final TextEditingController controller;
  final ValueChanged<LatLng?> onPicked;
  final LatLng? initial;
  final String labelText;
  final String? hintText;
  final String? Function(String?)? validator;

  @override
  State<AddressField> createState() => _AddressFieldState();
}

class _AddressFieldState extends State<AddressField> {
  final _nominatim = geo.NominatimClient();
  final _mapController = MapController();
  Timer? _debounce;
  List<geo.NominatimHit> _hits = const [];
  bool _searching = false;
  LatLng? _picked;
  // Para no re-buscar cuando el cambio en el controller vino de seleccionar
  // un hit (que setea el text con el display_name de Nominatim).
  bool _suppressNext = false;

  @override
  void initState() {
    super.initState();
    _picked = widget.initial;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    if (_suppressNext) {
      _suppressNext = false;
      return;
    }
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 3) {
      setState(() => _hits = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    final hits = await _nominatim.search(q, limit: 5);
    if (!mounted) return;
    setState(() {
      _hits = hits;
      _searching = false;
    });
  }

  /// Submit (Enter o botón lupa) — agarra el primer hit y lo deja fijado.
  /// NO abre el picker — el user lo abre si quiere ajustar tocando el
  /// mini-mapa que aparece abajo.
  Future<void> _onSubmit() async {
    _debounce?.cancel();
    final q = widget.controller.text.trim();
    if (q.isEmpty) return;
    var hits = _hits;
    if (hits.isEmpty) {
      setState(() => _searching = true);
      hits = await _nominatim.search(q, limit: 5);
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _searching = false;
      });
    }
    if (hits.isEmpty) return;
    _selectHit(hits.first);
  }

  void _selectHit(geo.NominatimHit hit) {
    final point = LatLng(hit.lat, hit.lng);
    _suppressNext = true;
    widget.controller.text = hit.displayName;
    setState(() {
      _picked = point;
      _hits = const [];
    });
    widget.onPicked(point);
    FocusScope.of(context).unfocus();
    // Si el mapa ya estaba renderizado, lo movemos al nuevo punto. El
    // postFrameCallback espera a que el MapController esté listo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _mapController.move(point, 16);
      } catch (_) {/* mapa todavía no renderizado, se centra solo al build */}
    });
  }

  Future<void> _openPickerForFineTune() async {
    final result = await pickLocationOnMap(context, initial: _picked);
    if (result != null && mounted) {
      setState(() => _picked = result);
      widget.onPicked(result);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _mapController.move(result, 16);
        } catch (_) {/* idem */}
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: widget.controller,
          onChanged: _onChanged,
          onFieldSubmitted: (_) => _onSubmit(),
          textInputAction: TextInputAction.search,
          validator: widget.validator,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText ?? 'Av. Corrientes 1234, CABA',
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    tooltip: 'Buscar dirección',
                    icon: const Icon(Icons.search),
                    onPressed: _onSubmit,
                  ),
          ),
        ),
        // Sugerencias del autocomplete.
        if (_hits.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top: 4),
            child: Column(
              children: _hits.map((h) {
                return ListTile(
                  leading: const Icon(Icons.place),
                  dense: true,
                  title: Text(h.displayName, maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => _selectHit(h),
                );
              }).toList(),
            ),
          ),
        // Mini-mapa embedded — solo aparece cuando hay un punto fijado.
        // Tap → abre picker fullscreen para ajustar.
        if (_picked != null) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _openPickerForFineTune,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 180,
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _picked!,
                        initialZoom: 16,
                        // Desactivamos drag/zoom adentro del mini-mapa porque
                        // el tap arriba lo usamos para abrir el picker. Si
                        // querés mover, abrís el picker.
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.none,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.la10.app',
                          maxZoom: 19,
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _picked!,
                              width: 48,
                              height: 48,
                              child: const Icon(Icons.location_on, size: 48, color: Colors.red),
                            ),
                          ],
                        ),
                      ],
                    ),
                    // Overlay con hint de "tocá para ajustar".
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.touch_app, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'Tocá para ajustar',
                              style: TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        // Status text — fallback cuando no hay punto todavía.
        if (_picked == null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Icon(Icons.location_off, size: 16, color: cs.outline),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Escribí la dirección y elegí una sugerencia.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: _openPickerForFineTune,
                  icon: const Icon(Icons.map, size: 18),
                  label: const Text('Elegir en mapa'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
