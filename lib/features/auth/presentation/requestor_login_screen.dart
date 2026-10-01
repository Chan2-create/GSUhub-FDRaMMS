import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/routing/route_paths.dart';
import 'auth_controller.dart';
import 'login_screen.dart' show validateEmail, validatePassword;
import 'widgets/requestor_auth_layout.dart';

/// The faculty and staff sign-in (Figma `193:310`, Objective 3.A).
///
/// Signs in through the same [AuthController] and `AuthService` as the
/// administrator console; only the page and where it leads differ. As on
/// 2.A's login, the design's "Username" is relabelled "Email": Firebase
/// Authentication signs in with an email address. A pending or deactivated
/// account is refused with its own message by the service.
class RequestorLoginScreen extends ConsumerStatefulWidget {
  const RequestorLoginScreen({
    super.key,
    this.redirectTo,
    this.justRegistered = false,
  });

  /// Where to go after signing in, when the guard intercepted a deep link.
  final String? redirectTo;

  /// Arrived from a completed sign-up: says the account awaits approval.
  final bool justRegistered;

  /// Query parameter the sign-up page sets on its way back here.
  static const String registeredParam = 'registered';

  @override
  ConsumerState<RequestorLoginScreen> createState() =>
      _RequestorLoginScreenState();
}

class _RequestorLoginScreenState extends ConsumerState<RequestorLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _emailError = validateEmail(_email.text);
      _passwordError = validatePassword(_password.text);
    });
    if (_emailError != null || _passwordError != null) return;

    final user = await ref
        .read(authControllerProvider.notifier)
        .signIn(email: _email.text.trim(), password: _password.text);
    if (!mounted || user == null) return;
    // The guard moves anyone who is not a requestor to their own area.
    context.go(widget.redirectTo ?? RoutePaths.staffHome);
  }

  @override
  Widget build(BuildContext context) {
    final login = ref.watch(authControllerProvider);
    final busy = login.isSubmitting;

    return RequestorAuthLayout(
      logoTop: 29,
      cardGap: 26,
      cardPadding: const EdgeInsets.fromLTRB(41, 41, 41, 42),
      footer: const Text(
        '© 2026 GSUhub. Excellence, Innovation, and Inclusion.',
        textAlign: TextAlign.center,
        style: AppTextStyles.authFooter,
      ),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Welcome back', style: AppTextStyles.authWelcome),
            const SizedBox(height: 8),
            const Text(
              'Please enter your credentials to access the system.',
              style: AppTextStyles.authSubtitle,
            ),
            if (login.errorMessage case final message?) ...[
              const SizedBox(height: 20),
              AuthNotice(message: message),
            ] else if (widget.justRegistered) ...[
              const SizedBox(height: 20),
              const AuthNotice(
                isError: false,
                message:
                    'Account created. A GSU administrator must approve it '
                    'before you can sign in.',
              ),
            ],
            const SizedBox(height: 40),
            AuthTextField(
              label: 'Email',
              labelStyle: AppTextStyles.authLabel,
              controller: _email,
              hint: 'e.g. juan.dc@dorsu.edu.ph',
              style: AuthFieldStyle.signIn,
              error: _emailError,
              enabled: !busy,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 20),
            AuthTextField(
              label: 'Password',
              labelStyle: AppTextStyles.authLabel,
              controller: _password,
              hint: '••••••••',
              style: AuthFieldStyle.signIn,
              error: _passwordError,
              enabled: !busy,
              obscure: true,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _signIn(),
            ),
            const SizedBox(height: 28),
            AuthButton(
              label: 'LOGIN TO DASHBOARD',
              color: AppColors.authSignInButton,
              busy: busy,
              onPressed: _signIn,
            ),
            const SizedBox(height: 20),
            AuthButton(
              label: 'CREATE ACCOUNT',
              color: AppColors.accentGold,
              onPressed: busy
                  ? null
                  : () {
                      // A failed attempt's message should not be waiting
                      // here after signing up.
                      ref.read(authControllerProvider.notifier).clearMessages();
                      context.go(RoutePaths.staffSignUp);
                    },
            ),
          ],
        ),
      ),
    );
  }
}
