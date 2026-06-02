/// Campo de dirección con autocomplete inline + mini-mapa embedded.
///
/// Flujo:
/// 1. El user escribe la dirección.
/// 2. Debajo aparecen sugerencias de Nominatim. Toca una → primer pin
///    queda colocado automáticamente.
/// 3. Alternativa: Enter o el botón lupa busca y agarra el primer hit.
/// 4. Aparece el mini-mapa con el pin rojo. El user puede:
///    - **Tocar otro punto del mapa** → el pin salta ahí.
///    - **Arrastrar** el mapa para moverse, **pinch-zoom** para acercar.
///    - Usar los **botones +/-** para zoom preciso.
///    - Botón **target** para recentrar el mapa sobre el pin actual.
/// 5. Si NO eligió de las sugerencias, queda el botón "Elegir en mapa"
///    para abrir el picker grande.

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
  // Recordamos el último punto que vino del autocomplete para el botón
  // "volver a la dirección" — si el user se perdió arrastrando puede
  // recentrar al lugar original.
  LatLng? _lastAutocompletePoint;
  // Por si en algún futuro volvemos a setear controller.text — flag
  // para no disparar onChanged en cascada.
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
    // NO overwriteamos el text que tipeó el user. Nominatim a veces
    // devuelve "Juarez Celman, Cordoba" sin número aunque el user puso
    // "Juarez Celman 2871" — ahi perdemos el número de la casa. Mantenemos
    // lo del user como source of truth y solo usamos las coords del hit.
    setState(() {
      _picked = point;
      _lastAutocompletePoint = point;
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
        // Mini-mapa estilo Google Maps:
        // 1. Pin rojo se coloca solo en la dirección que vino del autocomplete.
        // 2. Click en cualquier lado del mapa → el pin salta ahí.
        // 3. Botones +/-/centrar a la derecha.
        // El pin es un Container custom (no Icon de Material) porque el
        // font de Material Icons en cache del browser estaba pisando
        // los íconos nuevos. Container con BoxDecoration es 100% confiable.
        if (_picked != null) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 240,
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _picked!,
                      initialZoom: 16,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.pinchZoom |
                            InteractiveFlag.drag |
                            InteractiveFlag.doubleTapZoom |
                            InteractiveFlag.scrollWheelZoom,
                      ),
                      // Tap (click) en el mapa → pin salta a ese punto.
                      onTap: (tapPos, point) {
                        setState(() => _picked = point);
                        widget.onPicked(point);
                      },
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
                            width: 28,
                            height: 28,
                            // Default alignment.center → el centro del
                            // circulo cae sobre la coord exacta.
                            child: const _RedDotPin(),
                          ),
                        ],
                      ),
                    ],
                  ),
                  // Botones flotantes a la derecha. Usamos Text con
                  // simbolos universales (+ − ⊙) en vez de Material
                  // Icons para que rendereen aunque el font de iconos
                  // esté cacheado viejo.
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Column(
                      children: [
                        _MapCtrlButton(
                          label: '+',
                          tooltip: 'Acercar',
                          onTap: () {
                            final cam = _mapController.camera;
                            _mapController.move(cam.center, (cam.zoom + 1).clamp(1, 19));
                          },
                        ),
                        const SizedBox(height: 6),
                        _MapCtrlButton(
                          label: '−',
                          tooltip: 'Alejar',
                          onTap: () {
                            final cam = _mapController.camera;
                            _mapController.move(cam.center, (cam.zoom - 1).clamp(1, 19));
                          },
                        ),
                        const SizedBox(height: 6),
                        _MapCtrlButton(
                          label: '⊙',
                          tooltip: 'Volver a la dirección',
                          onTap: () {
                            if (_lastAutocompletePoint != null) {
                              _mapController.move(_lastAutocompletePoint!, 16);
                              setState(() => _picked = _lastAutocompletePoint);
                              widget.onPicked(_lastAutocompletePoint!);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Text(
                          'Clic en el mapa para mover el pin',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ],
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

/// Botón circular blanco que flota sobre el mini-mapa.
/// Renderiza un símbolo de texto (no Material Icon) para evitar
/// problemas con el font cacheado del browser.
class _MapCtrlButton extends StatelessWidget {
  const _MapCtrlButton({
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pin rojo estilo "spot marker" (circulo lleno con borde blanco).
/// Es un widget puro de Container — no depende del font de Material
/// Icons que puede estar cacheado viejo en el browser → garantiza
/// que se renderea siempre desde el primer frame.
class _RedDotPin extends StatelessWidget {
  const _RedDotPin();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFEA4335), // rojo Google Maps
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
    );
  }
}
