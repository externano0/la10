import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:la10_data/la10_data.dart';

import '../src/auth_state.dart';
import '../src/profile.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  // En web por default arrancamos en "comercio". Es la única opción visible
  // ahí (los riders usan el APK). En mobile arrancamos en "rider".
  AppRole _selectedRole = kIsWeb ? AppRole.businessOwner : AppRole.rider;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthActions.instance.signUpWithPassword(
        email: _email.text.trim(),
        password: _password.text,
        fullName: _fullName.text.trim().isEmpty ? null : _fullName.text.trim(),
      );
      final user = La10Supabase.auth.currentUser;
      if (user != null && _selectedRole != AppRole.rider) {
        // Update role away from default 'rider' if user picked another.
        await La10Supabase.client.from('profiles').update({
          'role': _roleToDb(_selectedRole),
        }).eq('user_id', user.id);
      }
      if (_selectedRole == AppRole.rider) {
        // Pre-create the rider row con teléfono cargado en el signup, para que
        // el jefe pueda llamarlo desde el primer minuto.
        try {
          await RidersRepository.instance.ensureSelf(
            displayName: _fullName.text.trim().isEmpty ? 'Rider' : _fullName.text.trim(),
            phone: _phone.text.trim(),
          );
        } catch (_) {/* ignore — user can press Activarme manually */}
      }
      // Force profile reload so the router re-evaluates with the new role.
      ref.invalidate(currentProfileProvider);
      if (mounted) {
        // Tiny delay so currentProfileProvider has a chance to refire.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (mounted) context.go('/home');
      }
    } catch (e) {
      setState(() => _error = _humanize(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _roleToDb(AppRole r) => switch (r) {
        AppRole.rider         => 'rider',
        AppRole.businessOwner => 'business_owner',
        AppRole.dispatcher    => 'dispatcher',
        AppRole.superAdmin    => 'super_admin',
      };

  String _humanize(Object e) {
    final s = e.toString();
    final m = RegExp(r'message:\s*([^,)]+)').firstMatch(s);
    final raw = m?.group(1)?.trim() ?? s;
    if (raw.toLowerCase().contains('already')) return 'Ese email ya está registrado. Probá ingresar.';
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('La 10 — Crear cuenta'),
        leading: BackButton(onPressed: () => context.go('/login')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // En web solo mostramos "Soy comercio" — los riders se
                  // registran desde el APK y se confundía a los comercios.
                  // En mobile mostramos ambas cards.
                  if (kIsWeb) ...[
                    Text('Cuenta de comercio', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Los riders se registran desde la app del celular.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    _RoleCard(
                      icon: Icons.storefront,
                      label: 'Soy comercio',
                      subtitle: 'Genero pedidos',
                      selected: true,
                      onTap: null,
                    ),
                  ] else ...[
                    Text('¿Cómo vas a usar La 10?', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _RoleCard(
                            icon: Icons.two_wheeler,
                            label: 'Soy rider',
                            subtitle: 'Hago entregas',
                            selected: _selectedRole == AppRole.rider,
                            onTap: _busy ? null : () => setState(() => _selectedRole = AppRole.rider),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _RoleCard(
                            icon: Icons.storefront,
                            label: 'Soy comercio',
                            subtitle: 'Genero pedidos',
                            selected: _selectedRole == AppRole.businessOwner,
                            onTap: _busy ? null : () => setState(() => _selectedRole = AppRole.businessOwner),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _fullName,
                    decoration: const InputDecoration(labelText: 'Nombre completo (opcional)'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.newUsername, AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (v) => (v == null || !v.contains('@')) ? 'Email inválido' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(labelText: 'Contraseña'),
                    validator: (v) => (v == null || v.length < 6) ? 'Mínimo 6 caracteres' : null,
                  ),
                  // Teléfono: obligatorio si elige rider (para que el jefe pueda llamarlo).
                  // Para comercio queda opcional.
                  if (_selectedRole == AppRole.rider) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      decoration: const InputDecoration(
                        labelText: 'Teléfono',
                        hintText: '+54 9 11 1234 5678',
                      ),
                      validator: (v) {
                        if (_selectedRole != AppRole.rider) return null;
                        final s = (v ?? '').trim();
                        // Mínimo realista: 8 dígitos sin separadores.
                        final digits = s.replaceAll(RegExp(r'\D'), '');
                        if (digits.length < 8) return 'Ingresá un teléfono válido';
                        return null;
                      },
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Crear cuenta'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : () => context.go('/login'),
                    child: const Text('Ya tengo cuenta'),
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

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 36, color: selected ? cs.primary : cs.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: selected ? cs.primary : null)),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
