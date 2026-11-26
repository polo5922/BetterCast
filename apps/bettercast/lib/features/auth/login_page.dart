import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../ui/widgets.dart';

import '../../core/config.dart';
import '../../core/providers.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  late final String? _savedServer = ref.read(sessionProvider).serverUrl;
  late bool _customServer =
      _savedServer != null && _savedServer != normalizeServerUrl(kOfficialServer);
  late final _server = TextEditingController(text: _customServer ? _savedServer : '');
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).signIn(
            _customServer ? _server.text : kOfficialServer,
            _email.text.trim(),
            _password.text,
            register: _register,
            displayName: _register && _name.text.trim().isNotEmpty ? _name.text.trim() : null,
          );
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _form,
              child: AutofillGroup(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Center(child: BrandMark(size: 84)),
                  const SizedBox(height: 20),
                  Text('BetterCast',
                      textAlign: TextAlign.center, style: theme.textTheme.displaySmall),
                  const SizedBox(height: 6),
                  Text('Tous tes podcasts, publics et Patreon, au même endroit.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 36),
                  if (_customServer) ...[
                    TextFormField(
                      controller: _server,
                      decoration: const InputDecoration(
                        labelText: 'Ton serveur',
                        hintText: 'podcasts.mondomaine.fr',
                        prefixIcon: Icon(Icons.dns_outlined),
                      ),
                      keyboardType: TextInputType.url,
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Adresse du serveur requise' : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_register) ...[
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(
                          labelText: 'Nom (facultatif)', prefixIcon: Icon(Icons.person_outline)),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(
                        labelText: 'E-mail', prefixIcon: Icon(Icons.alternate_email)),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    validator: (v) => (v ?? '').contains('@') ? null : 'E-mail invalide',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Mot de passe', prefixIcon: Icon(Icons.lock_outline)),
                    autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                    validator: (v) =>
                        _register && (v ?? '').length < 8 ? '8 caractères minimum' : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_register ? 'Créer le compte' : 'Se connecter'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _register = !_register),
                    child: Text(_register ? "J'ai déjà un compte" : 'Créer un compte'),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.dns_outlined),
                    title: const Text('Utiliser mon propre serveur'),
                    subtitle: Text(_customServer
                        ? 'Tes données restent chez toi'
                        : 'Serveur officiel BetterCast'),
                    value: _customServer,
                    onChanged: _busy ? null : (v) => setState(() => _customServer = v),
                  ),
                  if (_customServer)
                    TextButton.icon(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Héberger son serveur (guide sur GitHub)'),
                      onPressed: () => launchUrl(Uri.parse(kSelfHostGuideUrl),
                          mode: LaunchMode.externalApplication),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
