/// Campo de dirección con autocomplete inline.
///
/// El usuario escribe la dirección y debajo le aparecen los resultados de
/// Nominatim (OSM). Toca uno y queda fijado: nos da [LatLng] sin necesidad
/// de abrir el mapa.
///
/// Si querés ajustar más fino, el botón "Ajustar en el mapa" abre el
/// [MapPickerScreen] partiendo del punto elegido.
///
/// Esto reemplaza al flujo viejo de "TextField → botón Marcar en mapa →
/// picker → tap → vuelta" que era confuso. La idea: 90% de las veces el
/// comercio escribe la dirección, toca el primer hit, listo.

import 'dart:async';

import 'package:flutter/material.dart';
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

  /// Texto editable de la dirección (lo guardás en tu form como string libre).
  final TextEditingController controller;

  /// Se invoca cuando el user elige un resultado del autocomplete o ajusta
  /// el punto desde el mapa. Pasamos `null` si limpia el resultado.
  final ValueChanged<LatLng?> onPicked;

  /// Punto inicial — si lo tenés (ej. editando un negocio existente).
  final LatLng? initial;

  final String labelText;
  final String? hintText;
  final String? Function(String?)? validator;

  @override
  State<AddressField> createState() => _AddressFieldState();
}

class _AddressFieldState extends State<AddressField> {
  final _nominatim = geo.NominatimClient();
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

  void _select(geo.NominatimHit hit) {
    final point = LatLng(hit.lat, hit.lng);
    _suppressNext = true;
    widget.controller.text = hit.displayName;
    setState(() {
      _picked = point;
      _hits = const [];
    });
    widget.onPicked(point);
    FocusScope.of(context).unfocus();
  }

  Future<void> _openPickerForFineTune() async {
    final result = await pickLocationOnMap(context, initial: _picked);
    if (result != null && mounted) {
      setState(() => _picked = result);
      widget.onPicked(result);
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
          validator: widget.validator,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText ?? 'Av. Corrientes 1234, CABA',
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : null,
          ),
        ),
        // Lista de sugerencias del autocomplete.
        if (_hits.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top: 4),
            child: Column(
              children: _hits.map((h) {
                return ListTile(
                  leading: const Icon(Icons.place),
                  dense: true,
                  title: Text(h.displayName, maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => _select(h),
                );
              }).toList(),
            ),
          ),
        // Estado de la ubicación + botón de ajuste fino.
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Icon(
                _picked != null ? Icons.location_on : Icons.location_off,
                size: 16,
                color: _picked != null ? Colors.green : cs.outline,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _picked != null
                      ? 'Punto fijado — podés ajustar con el mapa si hace falta'
                      : 'Escribí la dirección y elegí un resultado.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton.icon(
                onPressed: _openPickerForFineTune,
                icon: const Icon(Icons.map, size: 18),
                label: Text(_picked != null ? 'Ajustar' : 'Elegir en mapa'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
