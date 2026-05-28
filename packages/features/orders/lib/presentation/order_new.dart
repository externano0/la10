/// Formulario de creación de orden desde el lado del comercio.
///
/// El pickup se autocompleta con la dirección del comercio (cargada una sola
/// vez al registrarlo). El comercio solo carga datos del cliente, dirección
/// de entrega, monto y notas. El comercio puede igual sobreescribir el
/// pickup tocando "Cambiar pickup".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:la10_businesses/la10_businesses.dart';
import 'package:la10_data/la10_data.dart';
import 'package:latlong2/latlong.dart';

final _businessProvider = FutureProvider.family<Business?, String>((ref, id) async {
  return BusinessesRepository.instance.getById(id);
});

class OrderNew extends ConsumerStatefulWidget {
  const OrderNew({required this.businessId, super.key});
  final String businessId;
  @override
  ConsumerState<OrderNew> createState() => _OrderNewState();
}

class _OrderNewState extends ConsumerState<OrderNew> {
  final _form = GlobalKey<FormState>();
  final _customer = TextEditingController();
  final _phone = TextEditingController();
  final _pickupAddr = TextEditingController();
  final _pickupLat = TextEditingController();
  final _pickupLng = TextEditingController();
  final _dropoffAddr = TextEditingController();
  LatLng? _dropoffPoint;
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;
  bool _editPickup = false;
  bool _prefilled = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_customer, _phone, _pickupAddr, _pickupLat, _pickupLng,
        _dropoffAddr, _amount, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _prefillPickupFromBusiness(Business b) {
    if (_prefilled) return;
    _prefilled = true;
    _pickupAddr.text = b.address ?? 'Local';
    _pickupLat.text = b.lat?.toStringAsFixed(6) ?? '';
    _pickupLng.text = b.lng?.toStringAsFixed(6) ?? '';
  }

  Future<void> _pickDropoff() async {
    final result = await pickLocationOnMap(context, initial: _dropoffPoint);
    if (result != null && mounted) setState(() => _dropoffPoint = result);
  }

  Future<void> _save({required bool submitNow}) async {
    if (!_form.currentState!.validate()) return;
    if (_dropoffPoint == null) {
      setState(() => _error = 'Marcá la dirección de entrega en el mapa.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final order = await OrdersRepository.instance.create(
        businessId: widget.businessId,
        customerName: _customer.text.trim(),
        customerPhone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        pickupAddress: _pickupAddr.text.trim(),
        pickupLat: double.parse(_pickupLat.text),
        pickupLng: double.parse(_pickupLng.text),
        dropoffAddress: _dropoffAddr.text.trim(),
        dropoffLat: _dropoffPoint!.latitude,
        dropoffLng: _dropoffPoint!.longitude,
        totalAmountCents: _amount.text.isEmpty ? null : (double.parse(_amount.text) * 100).round(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      if (submitNow) {
        await OrdersRepository.instance.transition(order.id, 'pending_assignment');
      }
      if (mounted) context.go('/b/businesses/${widget.businessId}');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncBiz = ref.watch(_businessProvider(widget.businessId));
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva orden')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: asyncBiz.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (biz) {
              if (biz == null) return const Center(child: Text('Negocio no encontrado'));
              _prefillPickupFromBusiness(biz);
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PickupCard(
                        business: biz,
                        editPickup: _editPickup,
                        pickupAddr: _pickupAddr,
                        pickupLat: _pickupLat,
                        pickupLng: _pickupLng,
                        onToggleEdit: () => setState(() => _editPickup = !_editPickup),
                      ),
                      const SizedBox(height: 16),
                      Text('Cliente', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _customer,
                        decoration: const InputDecoration(labelText: 'Nombre del cliente'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phone,
                        decoration: const InputDecoration(labelText: 'Teléfono cliente (opcional)'),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 16),
                      Text('Entrega', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _dropoffAddr,
                        decoration: const InputDecoration(
                          labelText: 'Dirección de entrega',
                          hintText: 'Calle Falsa 123, CABA',
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                      ),
                      const SizedBox(height: 8),
                      // Reemplazamos los inputs Lat/Lng por un picker en mapa.
                      Card(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    _dropoffPoint == null ? Icons.location_off : Icons.location_on,
                                    color: _dropoffPoint == null ? Theme.of(context).colorScheme.outline : Colors.green,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _dropoffPoint == null
                                          ? 'Sin punto en el mapa todavía'
                                          : 'Punto marcado ✓',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                onPressed: _busy ? null : _pickDropoff,
                                icon: const Icon(Icons.map),
                                label: Text(_dropoffPoint == null ? 'Marcar en el mapa' : 'Cambiar punto'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _amount,
                        decoration: const InputDecoration(labelText: 'Monto (ARS, opcional)'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _notes,
                        decoration: const InputDecoration(labelText: 'Notas'),
                        maxLines: 3,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ],
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 12,
                        children: [
                          OutlinedButton(
                            onPressed: _busy ? null : () => _save(submitNow: false),
                            child: const Text('Guardar borrador'),
                          ),
                          FilledButton.icon(
                            onPressed: _busy ? null : () => _save(submitNow: true),
                            icon: const Icon(Icons.send),
                            label: const Text('Crear y enviar a dispatch'),
                          ),
                        ],
                      ),
                      if (_busy) ...[
                        const SizedBox(height: 16),
                        const LinearProgressIndicator(),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Card del pickup que muestra la dirección guardada del comercio y un
/// botón para editar puntualmente esta orden (sin cambiar el default).
class _PickupCard extends StatelessWidget {
  const _PickupCard({
    required this.business,
    required this.editPickup,
    required this.pickupAddr,
    required this.pickupLat,
    required this.pickupLng,
    required this.onToggleEdit,
  });

  final Business business;
  final bool editPickup;
  final TextEditingController pickupAddr;
  final TextEditingController pickupLat;
  final TextEditingController pickupLng;
  final VoidCallback onToggleEdit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(backgroundColor: Colors.orange, child: const Icon(Icons.store, color: Colors.white)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Retirar en', style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 2),
                      Text(
                        editPickup ? 'Editando esta orden' : (business.address ?? 'Local'),
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: onToggleEdit,
                  child: Text(editPickup ? 'Usar dirección del local' : 'Cambiar'),
                ),
              ],
            ),
            if (editPickup) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: pickupAddr,
                decoration: const InputDecoration(labelText: 'Dirección de retiro'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              Row(
                children: [
                  Expanded(child: _NumField(controller: pickupLat, label: 'Lat')),
                  const SizedBox(width: 12),
                  Expanded(child: _NumField(controller: pickupLng, label: 'Lng')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NumField extends StatelessWidget {
  const _NumField({required this.controller, required this.label});
  final TextEditingController controller;
  final String label;
  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        validator: (v) => double.tryParse(v ?? '') == null ? 'Inválido' : null,
      );
}
