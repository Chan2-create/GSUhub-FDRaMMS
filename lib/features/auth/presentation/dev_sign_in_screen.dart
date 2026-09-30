import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/service_providers.dart';
import '../../../core/routing/route_paths.dart';
import 'auth_controller.dart';

/// A plain sign-in form for the faculty and staff app, for development
/// against the local Emulator Suite only (Objective 3.C).
///
/// It stands in until Objective 3.A builds the designed sign-in (Figma
/// `45:433` and `50:470`), so the report form can be reached and tested.
/// Deliberately undesigned, labelled as what it is, and carrying no
/// credentials: the seeded accounts are listed in docs/emulator_setup.md.
/// The router builds it only in debug builds, and it refuses to sign in
/// unless the app is pointed at the emulator.
class DevSignInScreen extends ConsumerStatefulWidget {
  const DevSignInScreen({super.key, this.redirectTo});

  /// Where to go after signing in, when the guard intercepted a deep link.
  final String? redirectTo;

  @override
  ConsumerState<DevSignInScreen> createState() => _DevSignInScreenState();
}

class _DevSignInScreenState extends ConsumerState<DevSignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final user = await ref
        .read(authControllerProvider.notifier)
        .signIn(email: _email.text.trim(), password: _password.text);
    if (!mounted || user == null) return;
    // The guard moves anyone who is not a requestor to their own area.
    context.go(widget.redirectTo ?? RoutePaths.staffSubmitReport);
  }

  @override
  Widget build(BuildContext context) {
    final onEmulator = ref.watch(appConfigProvider).useEmulator;
    final login = ref.watch(authControllerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Developer sign-in')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              onEmulator
                  ? 'Emulator only. This stands in for the Faculty & Staff '
                        'sign-in until Objective 3.A builds it. The seeded '
                        'accounts are listed in docs/emulator_setup.md.'
                  : 'Developer sign-in works only against the local '
                        'emulator. This build is pointed at the live '
                        'project.',
              style: theme.textTheme.bodyMedium,
            ),
            if (onEmulator) ...[
              const SizedBox(height: 24),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _signIn(),
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
              ),
              if (login.errorMessage case final message?) ...[
                const SizedBox(height: 16),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: login.isSubmitting ? null : _signIn,
                child: login.isSubmitting
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Sign in'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
