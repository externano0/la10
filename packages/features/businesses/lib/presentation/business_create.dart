/// Formulario para registrar un comercio nuevo.
/// El comercio carga su dirección UNA sola vez y queda como pickup default
/// de todas sus órdenes. Para marcar en el mapa abre [MapPickerScreen] —
/// no se piden números crudos de lat/lng al usuario.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:la10_data/la10_data.dart';
import 'package:latlong2/latlong.dart';

import 'businesses_home.dart';
import 'map_picker.dart';

class BusinessCreate extends ConsumerStatefulWidget {
  const BusinessCreate({super.key});
  @override
  ConsumerState<BusinessCreate> createState() => _BusinessCreateState();
}

class _BusinessCreateState extends ConsumerState<BusinessCreate> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  LatLng? _pickedLocation;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _openPicker() async {
    final result = await pickLocationOnMap(context, initial: _pickedLocation);
    if (result != null && mounted) {
      setState(() => _pickedLocation = result);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_pickedLocation == null) {
      setState(() => _error = 'Marcá tu local en el mapa.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await BusinessesRepository.instance.create(
        name: _name.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        address: _address.text.trim(),
        lat: _pickedLocation!.latitude,
        lng: _pickedLocation!.longitude,
      );
      ref.invalidate(myBusinessesProvider);
      if (mounted) context.go('/b/home');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo negocio')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Nombre del negocio'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phone,
                    decoration: const InputDecoration(labelText: 'Teléfono (opcional)'),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _address,
                    decoration: const InputDecoration(
                      labelText: 'Dirección',
                      hintText: 'Av. Corrientes 1234, CABA',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 16),
                  // Bloque para marcar en mapa — reemplaza lat/lng manuales.
                  Card(
                    color: cs.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _pickedLocation == null ? Icons.location_off : Icons.location_on,
                                color: _pickedLocation == null ? cs.outline : Colors.green,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _pickedLocation == null
                                      ? 'Sin ubicación marcada todavía'
                                      : 'Ubicación marcada ✓',
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _openPicker,
                            icon: const Icon(Icons.map),
                            label: Text(
                              _pickedLocation == null
                                  ? 'Marcar mi local en el mapa'
                                  : 'Cambiar ubicación',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: cs.error)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: _busy
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Guardar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
