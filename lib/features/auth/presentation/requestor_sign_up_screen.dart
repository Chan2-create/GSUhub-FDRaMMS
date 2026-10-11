import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/routing/route_paths.dart';
import 'requestor_login_screen.dart';
import 'sign_up_controller.dart';
import 'widgets/requestor_auth_layout.dart';

/// Create Account — faculty and staff self-registration (Figma `194:455`,
/// Objective 3.A).
///
/// The account it creates waits for an administrator's approval; on
/// success the person is returned to sign-in, which says so. The design's
/// validation and its "account created" state are not drawn; both are
/// plain, and flagged.
class RequestorSignUpScreen extends ConsumerStatefulWidget {
  const RequestorSignUpScreen({super.key});

  @override
  ConsumerState<RequestorSignUpScreen> createState() =>
      _RequestorSignUpScreenState();
}

class _RequestorSignUpScreenState extends ConsumerState<RequestorSignUpScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late final TapGestureRecognizer _loginLink = TapGestureRecognizer()
    ..onTap = () => context.go(RoutePaths.staffLogin);

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _loginLink.dispose();
    super.dispose();
  }

  SignUpController get _controller =>
      ref.read(signUpControllerProvider.notifier);

  Future<void> _register() async {
    FocusScope.of(context).unfocus();
    final created = await _controller.register(
      fullName: _name.text,
      email: _email.text,
      password: _password.text,
      confirmPassword: _confirm.text,
    );
    if (!mounted || !created) return;
    context.go(
      Uri(
        path: RoutePaths.staffLogin,
        queryParameters: {RequestorLoginScreen.registeredParam: '1'},
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final form = ref.watch(signUpControllerProvider);
    final busy = form.isSubmitting;

    Widget field(
      SignUpField name,
      String label,
      TextEditingController controller,
      String hint, {
      bool obscure = false,
      TextInputType? keyboardType,
      Iterable<String>? autofillHints,
      TextInputAction action = TextInputAction.next,
      TextCapitalization capitalization = TextCapitalization.none,
      ValueChanged<String>? onSubmitted,
    }) => AuthTextField(
      label: label,
      labelStyle: AppTextStyles.signUpLabel,
      controller: controller,
      hint: hint,
      style: AuthFieldStyle.signUp,
      error: form.errors[name],
      enabled: !busy,
      obscure: obscure,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      textInputAction: action,
      textCapitalization: capitalization,
      onChanged: (_) => _controller.clearError(name),
      onSubmitted: onSubmitted,
    );

    return RequestorAuthLayout(
      logoTop: 49,
      cardGap: 28,
      cardPadding: const EdgeInsets.fromLTRB(33, 33, 33, 33),
      footer: const Text(
        '© 2026 GSUHUB. EXCELLENCE, INNOVATION, AND INCLUSION.',
        textAlign: TextAlign.center,
        style: AppTextStyles.signUpFooter,
      ),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const Text(
              'Create Account',
              textAlign: TextAlign.center,
              style: AppTextStyles.signUpTitle,
            ),
            const SizedBox(height: 8),
            const Text(
              'Create An Account and Report',
              textAlign: TextAlign.center,
              style: AppTextStyles.signUpText,
            ),
            if (form.errorMessage case final message?) ...[
              const SizedBox(height: 20),
              AuthNotice(message: message),
            ],
            const SizedBox(height: 32),
            field(
              SignUpField.fullName,
              'FULL NAME',
              _name,
              'e.g. Juan Dela Cruz',
              autofillHints: const [AutofillHints.name],
              capitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 24),
            field(
              SignUpField.email,
              'EMAIL',
              _email,
              'juan.dc@dorsu.edu.ph',
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
            ),
            const SizedBox(height: 24),
            field(
              SignUpField.password,
              'PASSWORD',
              _password,
              '••••••••',
              obscure: true,
              autofillHints: const [AutofillHints.newPassword],
            ),
            const SizedBox(height: 24),
            field(
              SignUpField.confirmPassword,
              'CONFIRM PASSWORD',
              _confirm,
              '••••••••',
              obscure: true,
              autofillHints: const [AutofillHints.newPassword],
              action: TextInputAction.done,
              onSubmitted: (_) => _register(),
            ),
            const SizedBox(height: 40),
            AuthButton(
              label: 'REGISTER',
              color: AppColors.primary,
              height: 56,
              busy: busy,
              onPressed: _register,
            ),
            const SizedBox(height: 32),
            const Divider(color: AppColors.signUpDivider, height: 1),
            const SizedBox(height: 24),
            Text.rich(
              TextSpan(
                style: AppTextStyles.signUpText,
                children: [
                  const TextSpan(text: 'Already have an account?  '),
                  TextSpan(
                    text: 'Login',
                    style: AppTextStyles.signUpLink,
                    recognizer: busy ? null : _loginLink,
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
