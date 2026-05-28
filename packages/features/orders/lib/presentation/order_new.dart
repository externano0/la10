/// Formulario de creación de orden desde el lado del comercio.
///
/// Pickup viene auto-cargado de la dirección registrada del comercio (con su
/// punto en el mapa). El comercio NO ve coordenadas crudas — si quiere cambiar
/// el punto de retiro para esta orden puntual usa el map picker (no se piden
/// lat/lng).
///
/// Dropoff: dirección a mano + un solo botón "Marcar en el mapa" que abre el
/// picker. La idea es que nadie tipee lat/lng nunca.

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
  final _dropoffAddr = TextEditingController();
  final _amount = TextEditingController();
  final _notes = TextEditingController();

  // Override del pickup solo si el comercio toca "Cambiar punto" — si no,
  // usa el del local. Se guarda como LatLng, nunca lat/lng numérico crudo.
  LatLng? _pickupOverride;
  LatLng? _dropoffPoint;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _customer.dispose();
    _phone.dispose();
    _dropoffAddr.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickPickup() async {
    final biz = await ref.read(_businessProvider(widget.businessId).future);
    final initial = _pickupOverride
        ?? (biz?.lat != null && biz?.lng != null ? LatLng(biz!.lat!, biz.lng!) : null);
    if (!mounted) return;
    final result = await pickLocationOnMap(context, initial: initial);
    if (result != null && mounted) {
      setState(() => _pickupOverride = result);
    }
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
    final biz = await ref.read(_businessProvider(widget.businessId).future);
    if (biz == null) {
      setState(() => _error = 'Negocio no encontrado');
      return;
    }
    // Pickup: prioridad override → punto del local. Si no hay nada, error.
    final pickup = _pickupOverride
        ?? (biz.lat != null && biz.lng != null ? LatLng(biz.lat!, biz.lng!) : null);
    if (pickup == null) {
      setState(() => _error = 'El local no tiene un punto marcado. Editalo desde "Negocios" y marcá su ubicación.');
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
        pickupAddress: biz.address ?? 'Local',
        pickupLat: pickup.latitude,
        pickupLng: pickup.longitude,
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
    final cs = Theme.of(context).colorScheme;
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
              final hasBizPoint = biz.lat != null && biz.lng != null;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Pickup: tarjeta read-only con la dir del local + botón
                      // de map picker si el comercio quiere cambiarlo solo
                      // para esta orden.
                      Card(
                        color: cs.surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: Colors.orange,
                                    child: const Icon(Icons.store, color: Colors.white),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Retirar en', style: Theme.of(context).textTheme.labelLarge),
                                        const SizedBox(height: 2),
                                        Text(biz.address ?? 'Local',
                                            style: Theme.of(context).textTheme.bodyLarge),
                                        if (_pickupOverride != null)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              '(Punto cambiado solo para esta orden)',
                                              style: TextStyle(color: cs.primary, fontStyle: FontStyle.italic),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (!hasBizPoint)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    'Este local no tiene punto marcado. Volvé a "Negocios" y editá su ubicación.',
                                    style: TextStyle(color: cs.error),
                                  ),
                                ),
                              TextButton.icon(
                                onPressed: _busy ? null : _pickPickup,
                                icon: const Icon(Icons.map),
                                label: Text(_pickupOverride == null
                                    ? 'Cambiar punto de retiro (solo esta orden)'
                                    : 'Cambiar otra vez'),
                              ),
                            ],
                          ),
                        ),
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
                                    _dropoffPoint == null ? Icons.location_off : Icons.location_on,
                                    color: _dropoffPoint == null ? cs.outline : Colors.green,
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
                        Text(_error!, style: TextStyle(color: cs.error)),
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
