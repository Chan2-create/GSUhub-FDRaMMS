import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/utils/account_validation.dart';
import 'mobile_login_screen.dart';
import 'sign_up_controller.dart';
import 'widgets/mobile_auth_layout.dart';
import 'widgets/terms_notice.dart';

/// Create Account — self-registration from the phone app (Figma `194:455`,
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
///
/// **2026-11-25:** the password is 8 to 12 characters with no spaces
/// ([PasswordPolicy.pattern]): spaces are not let in, nor a thirteenth
/// character, and a count sits beside the label. The requirements show
/// as soon as the field is entered, Confirm Password says whether it
/// matches as it is typed, and an account is created only once the
/// Terms of Use and Privacy Notice are accepted ([TermsNotice], a draft).
///
/// **2026-11-26** (the adviser's consultation): the department step is
/// gone. In its place the person says what they are, Faculty or Utility,
/// which decides the app they open once an administrator approves them
/// (the faculty and staff app, or the maintenance app). Choosing grants
/// nothing by itself: the account still waits for approval.
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
  final _passwordFocus = FocusNode();
  UserRole? _role;
  bool _acceptedTerms = false;
  late final TapGestureRecognizer _loginLink = TapGestureRecognizer()
    ..onTap = () => context.go(RoutePaths.staffLogin);

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _passwordFocus.dispose();
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
      role: _role,
      acceptedTerms: _acceptedTerms,
    );
    if (!mounted || !created) return;
    context.go(
      Uri(
        path: RoutePaths.staffLogin,
        queryParameters: {MobileLoginScreen.registeredParam: '1'},
      ).toString(),
    );
  }

  void _setAccepted(bool accepted) {
    setState(() => _acceptedTerms = accepted);
    if (accepted) _controller.clearError(SignUpField.terms);
  }

  Future<void> _openTerms() async {
    final agreed = await showTermsNotice(context);
    if (agreed ?? false) _setAccepted(true);
  }

  /// Spaces are not let into a new password's fields.
  static final _noSpaces = FilteringTextInputFormatter.deny(RegExp(r'\s'));

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
      int? maxLength,
      List<TextInputFormatter>? inputFormatters,
      FocusNode? focusNode,
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
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      focusNode: focusNode,
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
            _RoleField(
              value: _role,
              error: form.errors[SignUpField.role],
              enabled: !busy,
              onChanged: (role) {
                setState(() => _role = role);
                _controller.clearError(SignUpField.role);
              },
            ),
            const AuthGap(24),
            field(
              SignUpField.password,
              'PASSWORD',
              _password,
              '••••••••',
              obscure: true,
              autofillHints: const [AutofillHints.newPassword],
              maxLength: PasswordPolicy.maxLength,
              inputFormatters: [_noSpaces],
              focusNode: _passwordFocus,
              below: PasswordRequirements(
                controller: _password,
                focusNode: _passwordFocus,
              ),
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
              inputFormatters: [
                _noSpaces,
                LengthLimitingTextInputFormatter(PasswordPolicy.maxLength),
              ],
              // The form's own error replaces it once the form is sent.
              below: form.errors[SignUpField.confirmPassword] == null
                  ? PasswordMatch(password: _password, confirm: _confirm)
                  : null,
            ),
            // The 40 the button had below Confirm Password, shared.
            const AuthGap(16),
            _TermsBox(
              accepted: _acceptedTerms,
              enabled: !busy,
              error: form.errors[SignUpField.terms],
              onChanged: _setAccepted,
              onOpen: _openTerms,
            ),
            const AuthGap(24),
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

/// "I agree to the Terms of Use and Privacy Notice"
/// (2026-11-25): a box to tick, and the notice's name to tap to read it,
/// whose I Agree ticks the box too.
class _TermsBox extends StatefulWidget {
  const _TermsBox({
    required this.accepted,
    required this.onChanged,
    required this.onOpen,
    this.error,
    this.enabled = true,
  });

  final bool accepted;
  final ValueChanged<bool> onChanged;
  final VoidCallback onOpen;
  final String? error;
  final bool enabled;

  @override
  State<_TermsBox> createState() => _TermsBoxState();
}

class _TermsBoxState extends State<_TermsBox> {
  late final TapGestureRecognizer _link = TapGestureRecognizer()
    ..onTap = () => widget.onOpen();

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox.square(
              dimension: 32,
              child: Checkbox(
                key: const ValueKey('sign-up-terms'),
                value: widget.accepted,
                onChanged: widget.enabled
                    ? (value) => widget.onChanged(value ?? false)
                    : null,
                activeColor: AppColors.primary,
                side: BorderSide(
                  color: error != null ? AppColors.error : AppColors.warmText,
                  width: 1.5,
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                semanticLabel: 'I agree to the ${TermsNotice.title}',
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text.rich(
                TextSpan(
                  // One line on the card, so the form still fits a phone
                  // (test/widget/auth_fit_test.dart).
                  style: AppTextStyles.formError.copyWith(
                    color: AppColors.warmText,
                  ),
                  children: [
                    const TextSpan(text: 'I agree to the '),
                    TextSpan(
                      text: 'Terms and Privacy Notice',
                      style: AppTextStyles.formError.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: widget.enabled ? _link : null,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (error case final message?)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 6),
            child: Text(
              message,
              style: AppTextStyles.formError.copyWith(color: AppColors.error),
            ),
          ),
      ],
    );
  }
}

/// I AM A: Faculty or Utility (2026-11-26), in place of the department.
/// What the person is decides the app they open once approved: Faculty
/// the faculty and staff app, Utility the maintenance app. The
/// administrator reads it on the request before approving.
class _RoleField extends StatelessWidget {
  const _RoleField({
    required this.value,
    required this.onChanged,
    this.error,
    this.enabled = true,
  });

  final UserRole? value;
  final ValueChanged<UserRole?> onChanged;
  final String? error;
  final bool enabled;

  /// What each choice means, under its name in the list.
  static String hintFor(UserRole role) => switch (role) {
    UserRole.maintenancePersonnel => 'Maintenance and utility staff of GSU',
    _ => 'Faculty and staff who report damage',
  };

  @override
  Widget build(BuildContext context) {
    final placeholder = AppTextStyles.authInput.copyWith(
      color: AuthFieldStyle.signUp.placeholder,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text('I AM A', style: AppTextStyles.signUpLabel),
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
              child: DropdownButton<UserRole>(
                key: const ValueKey('sign-up-role'),
                value: value,
                isExpanded: true,
                hint: Text(
                  'Choose Faculty or Utility',
                  overflow: TextOverflow.ellipsis,
                  style: placeholder,
                ),
                style: AppTextStyles.authInput,
                icon: const Icon(Icons.expand_more, color: AppColors.warmText),
                selectedItemBuilder: (context) => [
                  for (final role in UserRole.signUpChoices)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        role.signUpLabel,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                items: [
                  for (final role in UserRole.signUpChoices)
                    DropdownMenuItem(
                      value: role,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(role.signUpLabel),
                          Text(
                            hintFor(role),
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.formError.copyWith(
                              color: AppColors.warmText,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: enabled ? onChanged : null,
              ),
            ),
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
      ],
    );
  }
}
