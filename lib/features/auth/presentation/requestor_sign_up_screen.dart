import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/errors/failures.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/utils/result.dart';
import '../../user_management/data/models/department.dart';
import '../../user_management/presentation/department_providers.dart';
import 'mobile_login_screen.dart';
import 'sign_up_controller.dart';
import 'widgets/mobile_auth_layout.dart';

/// Create Account — faculty and staff self-registration (Figma `194:455`,
/// Objective 3.A).
///
/// The account it creates waits for an administrator's approval; on
/// success the person is returned to sign-in, which says so. The design's
/// validation and its "account created" state are not drawn; both are
/// plain, and flagged.
///
/// **2026-11-17:** the department or faculty, chosen from the list the
/// administrator keeps (required while the list has any), the password's
/// requirements ticked off as it is typed, and an eye on both password
/// fields. Not in the design frame; drawn in the card's own style. No
/// mobile number: the brief did not ask for one here, and the page has
/// to fit a phone (`test/widget/auth_fit_test.dart`); an administrator
/// adds one from User Accounts.
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
  String? _department;
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

  /// The departments to choose from, once they are known: none while
  /// loading or when they could not be read.
  List<Department> get _departments =>
      switch (ref.read(activeDepartmentsProvider)) {
        AsyncData(value: Success(:final value)) => value,
        _ => const [],
      };

  Future<void> _register() async {
    FocusScope.of(context).unfocus();
    final created = await _controller.register(
      fullName: _name.text,
      email: _email.text,
      password: _password.text,
      confirmPassword: _confirm.text,
      department: _department,
      departmentRequired: _departments.isNotEmpty,
    );
    if (!mounted || !created) return;
    context.go(
      Uri(
        path: RoutePaths.staffLogin,
        queryParameters: {MobileLoginScreen.registeredParam: '1'},
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
      Widget? below,
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
      below: below,
    );

    return MobileAuthLayout(
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
            const AuthGap(16),
            const Text(
              'Create Account',
              textAlign: TextAlign.center,
              style: AppTextStyles.signUpTitle,
            ),
            const AuthGap(8),
            const Text(
              'Create An Account and Report',
              textAlign: TextAlign.center,
              style: AppTextStyles.signUpText,
            ),
            if (form.errorMessage case final message?) ...[
              const AuthGap(20),
              AuthNotice(message: message),
            ],
            const AuthGap(32),
            field(
              SignUpField.fullName,
              'FULL NAME',
              _name,
              'e.g. Juan Dela Cruz',
              autofillHints: const [AutofillHints.name],
              capitalization: TextCapitalization.words,
            ),
            const AuthGap(24),
            field(
              SignUpField.email,
              'EMAIL',
              _email,
              'juan.dc@dorsu.edu.ph',
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
            ),
            const AuthGap(24),
            _DepartmentField(
              value: _department,
              error: form.errors[SignUpField.department],
              enabled: !busy,
              onChanged: (department) {
                setState(() => _department = department);
                _controller.clearError(SignUpField.department);
              },
            ),
            // The department field brings its own gap below, and none when
            // there is no list to show.
            field(
              SignUpField.password,
              'PASSWORD',
              _password,
              '••••••••',
              obscure: true,
              autofillHints: const [AutofillHints.newPassword],
              below: PasswordRequirements(controller: _password),
            ),
            const AuthGap(24),
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
            const AuthGap(40),
            AuthButton(
              label: 'REGISTER',
              color: AppColors.primary,
              height: 56,
              busy: busy,
              onPressed: _register,
            ),
            const AuthGap(32),
            const Divider(color: AppColors.signUpDivider, height: 1),
            const AuthGap(24),
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

/// DEPARTMENT / FACULTY: the list the administrator keeps, read from the
/// database when the form opens (2026-11-17). Four states, each said in
/// words: loading, with a spinner; the list; an empty list, which is not
/// an error (nothing to choose, so nothing is required, and the database
/// agrees); and a list that could not be read, with why and a Retry.
class _DepartmentField extends ConsumerWidget {
  const _DepartmentField({
    required this.value,
    required this.onChanged,
    this.error,
    this.enabled = true,
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final String? error;
  final bool enabled;

  /// What to tell the person when the list could not be read.
  static String failureMessage(Failure? failure) => switch (failure) {
    NetworkFailure(:final message) => message,
    _ =>
      'The list of departments is not available right now. Retry in a '
          "moment; if it keeps happening, tell the GSU Administrator's "
          'Office.',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final departments = ref.watch(activeDepartmentsProvider);
    final placeholder = AppTextStyles.authInput.copyWith(
      color: AuthFieldStyle.signUp.placeholder,
    );

    final List<Department> options;
    final Widget hint;
    String? note;
    var failed = false;
    switch (departments) {
      case AsyncData(value: Success(:final value)) when value.isNotEmpty:
        options = value;
        hint = Text(
          'Choose your department or faculty',
          overflow: TextOverflow.ellipsis,
          style: placeholder,
        );
      case AsyncData(value: Success()):
        options = const [];
        hint = Text(
          'No departments listed yet',
          overflow: TextOverflow.ellipsis,
          style: placeholder,
        );
        note =
            'GSU has not listed any departments or faculties yet. You can '
            'create your account without one.';
      case AsyncData(value: Error(:final failure)):
        options = const [];
        failed = true;
        hint = Text(
          'Departments unavailable',
          overflow: TextOverflow.ellipsis,
          style: placeholder,
        );
        note = failureMessage(failure);
      case AsyncError():
        options = const [];
        failed = true;
        hint = Text(
          'Departments unavailable',
          overflow: TextOverflow.ellipsis,
          style: placeholder,
        );
        note = failureMessage(null);
      default:
        options = const [];
        hint = Row(
          children: [
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.warmText,
                semanticsLabel: 'Loading departments',
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Loading departments…',
                overflow: TextOverflow.ellipsis,
                style: placeholder,
              ),
            ),
          ],
        );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text('DEPARTMENT / FACULTY', style: AppTextStyles.signUpLabel),
        ),
        SizedBox(height: AuthFieldStyle.signUp.labelGap),
        AuthFieldBox(
          style: AuthFieldStyle.signUp,
          hasError: error != null,
          child: DropdownButtonHideUnderline(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AuthFieldStyle.signUp.horizontalPadding,
              ),
              child: DropdownButton<String>(
                key: const ValueKey('sign-up-department'),
                value: value,
                isExpanded: true,
                hint: hint,
                disabledHint: hint,
                style: AppTextStyles.authInput,
                icon: const Icon(Icons.expand_more, color: AppColors.warmText),
                items: [
                  for (final department in options)
                    DropdownMenuItem(
                      value: department.name,
                      child: Text(
                        department.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: enabled && options.isNotEmpty ? onChanged : null,
              ),
            ),
          ),
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 6),
            child: Semantics(
              liveRegion: failed,
              child: Text(
                note,
                style: AppTextStyles.formError.copyWith(
                  color: failed ? AppColors.error : AppColors.warmText,
                ),
              ),
            ),
          ),
        if (failed)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => ref.invalidate(activeDepartmentsProvider),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ),
        if (error case final message?)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 6),
            child: Text(
              message,
              style: AppTextStyles.formError.copyWith(color: AppColors.error),
            ),
          ),
        const AuthGap(24),
      ],
    );
  }
}
