import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:la10_data/la10_data.dart';

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
  final _pickupAddr = TextEditingController(text: 'Local');
  final _pickupLat = TextEditingController(text: '-34.603');
  final _pickupLng = TextEditingController(text: '-58.387');
  final _dropoffAddr = TextEditingController();
  final _dropoffLat = TextEditingController(text: '-34.610');
  final _dropoffLng = TextEditingController(text: '-58.400');
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_customer, _phone, _pickupAddr, _pickupLat, _pickupLng, _dropoffAddr, _dropoffLat, _dropoffLng, _amount, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save({required bool submitNow}) async {
    if (!_form.currentState!.validate()) return;
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
        dropoffLat: double.parse(_dropoffLat.text),
        dropoffLng: double.parse(_dropoffLng.text),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva orden')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                  Text('Pickup', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _pickupAddr,
                    decoration: const InputDecoration(labelText: 'Dirección pickup'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  Row(
                    children: [
                      Expanded(child: _NumField(controller: _pickupLat, label: 'Lat')),
                      const SizedBox(width: 12),
                      Expanded(child: _NumField(controller: _pickupLng, label: 'Lng')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Dropoff', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _dropoffAddr,
                    decoration: const InputDecoration(labelText: 'Dirección dropoff'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  Row(
                    children: [
                      Expanded(child: _NumField(controller: _dropoffLat, label: 'Lat')),
                      const SizedBox(width: 12),
                      Expanded(child: _NumField(controller: _dropoffLng, label: 'Lng')),
                    ],
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
          ),
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
