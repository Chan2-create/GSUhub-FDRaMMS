import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/breakpoints.dart';
import '../../../core/routing/route_paths.dart';
import 'auth_controller.dart';

/// Admin login (Figma node `194:504`).
///
/// Layout: white logo bar, full-bleed campus photo under an indigo
/// overlay, university heading block on the left, translucent sign-in card
/// on the right.
///
/// There is deliberately no sign-up link — manuscript §1.5 limits access
/// to authorized accounts, and administrators are provisioned rather than
/// self-registered (see docs/firebase_setup.md §3.2).
class AdminLoginScreen extends ConsumerStatefulWidget {
  const AdminLoginScreen({super.key, this.redirectTo});

  /// Where to send the user after a successful sign-in. Set by the route
  /// guard when it intercepts a deep link, so pasting an admin URL while
  /// logged out lands on the intended page rather than the dashboard.
  final String? redirectTo;

  @override
  ConsumerState<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends ConsumerState<AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final user = await ref
        .read(authControllerProvider.notifier)
        .signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );

    if (!mounted || user == null) return;
    // The guard re-evaluates on the auth state change and will bounce a
    // non-admin away from /admin/*, so this can navigate unconditionally.
    context.go(widget.redirectTo ?? RoutePaths.adminDashboard);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.sidebarBackground,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _CampusBackdrop(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Below ~1000px the two columns stop fitting side by side,
                // so the card stacks under the heading rather than being
                // squeezed to an unusable width.
                final isWide = constraints.maxWidth >= 1000;
                return SingleChildScrollView(
                  padding: Breakpoints.isCompact(context)
                      ? const EdgeInsets.fromLTRB(16, 96, 16, 24)
                      : const EdgeInsets.fromLTRB(40, 100, 40, 40),
                  child: isWide
                      ? Row(
                          children: [
                            const Expanded(child: _HeadingBlock()),
                            const SizedBox(width: 48),
                            SizedBox(
                              width: 561,
                              child: _SignInCard(
                                formKey: _formKey,
                                emailController: _emailController,
                                passwordController: _passwordController,
                                passwordFocus: _passwordFocus,
                                obscurePassword: _obscurePassword,
                                onToggleObscure: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                state: state,
                                onSubmit: _submit,
                                onForgotPassword: _showPasswordReset,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _HeadingBlock(),
                            const SizedBox(height: 40),
                            _SignInCard(
                              formKey: _formKey,
                              emailController: _emailController,
                              passwordController: _passwordController,
                              passwordFocus: _passwordFocus,
                              obscurePassword: _obscurePassword,
                              onToggleObscure: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                              state: state,
                              onSubmit: _submit,
                              onForgotPassword: _showPasswordReset,
                            ),
                          ],
                        ),
                );
              },
            ),
          ),
          const _LogoBar(),
        ],
      ),
    );
  }

  Future<void> _showPasswordReset() async {
    final email = await showDialog<String>(
      context: context,
      builder: (_) => _PasswordResetDialog(initialEmail: _emailController.text),
    );

    if (email == null || !mounted) return;

    await ref.read(authControllerProvider.notifier).sendPasswordReset(email);
  }
}

/// Password-reset prompt, prefilled with whatever is already in the login
/// form's email field.
///
/// It owns its text controller rather than taking one from the caller: a
/// controller disposed the moment `showDialog` returns is still attached to
/// this field while the route animates out, and the field's caret-position
/// callback then runs against a detached render object.
class _PasswordResetDialog extends StatefulWidget {
  const _PasswordResetDialog({required this.initialEmail});

  final String initialEmail;

  @override
  State<_PasswordResetDialog> createState() => _PasswordResetDialogState();
}

class _PasswordResetDialogState extends State<_PasswordResetDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.initialEmail);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Reset your password'),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter your GSUhub email address and we will send you a '
            'reset link.',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
            validator: validateEmail,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_formKey.currentState?.validate() ?? false) {
            Navigator.of(context).pop(_controller.text.trim());
          }
        },
        child: const Text('Send link'),
      ),
    ],
  );
}

/// Shared email validation, also used by the reset dialog.
///
/// The Figma field is labelled "Username", but Firebase Authentication
/// signs in with an email address. Relabelled to "Email" and validated as
/// one — a user typing a bare username into a field that silently requires
/// an email gets an error they cannot act on. Noted in the fidelity report.
String? validateEmail(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) return 'Enter your email address.';
  // Deliberately permissive: the authoritative check is whether Firebase
  // accepts it. This only catches obvious typos before a network round
  // trip.
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
    return 'Enter a valid email address.';
  }
  return null;
}

String? validatePassword(String? value) {
  if (value == null || value.isEmpty) return 'Enter your password.';
  return null;
}

/// The campus photograph under the design's indigo wash.
///
/// The photograph is square (474 × 474: the graduates' monument, sky
/// above, plants below) and the page is wide, so `BoxFit.cover` showed
/// its top third at three times its size, which read as a zoomed-in
/// blur (Chris, 2026-11-15). Now the whole photograph is drawn, as
/// taken, as large as the page allows, its edges fading into the same
/// picture stretched to fill and softened behind it, so the page is
/// still full-bleed with no seam. Nothing is cropped, the monument is
/// whole, and the upscaling is less than two to one on a laptop. It
/// fades in on load; not under reduced motion.
class _CampusBackdrop extends StatelessWidget {
  const _CampusBackdrop();

  static const String _photo = 'assets/images/campus_background.png';

  /// Width over height of [_photo]. Replace both together.
  static const double _photoAspect = 1;

  @override
  Widget build(BuildContext context) => _Reveal(
    duration: const Duration(milliseconds: 700),
    child: RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: 0.4,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: 28,
                sigmaY: 28,
                tileMode: TileMode.mirror,
              ),
              child: Image.asset(_photo, fit: BoxFit.cover),
            ),
          ),
          Opacity(
            opacity: 0.6,
            child: Center(
              child: AspectRatio(
                aspectRatio: _photoAspect,
                child: _FadedEdges(
                  child: Image.asset(
                    _photo,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
          ),
          // The indigo wash the design lays over the photo so white type
          // stays legible against a busy image.
          const ColoredBox(color: Color(0x80241597)),
        ],
      ),
    ),
  );
}

/// Fades its child out towards all four edges, so a picture drawn
/// smaller than the page melts into what is behind it.
class _FadedEdges extends StatelessWidget {
  const _FadedEdges({required this.child});

  final Widget child;

  static Shader _fade(Rect bounds, {required bool across}) => LinearGradient(
    begin: across ? Alignment.centerLeft : Alignment.topCenter,
    end: across ? Alignment.centerRight : Alignment.bottomCenter,
    colors: const [
      Color(0x00FFFFFF),
      Color(0xFFFFFFFF),
      Color(0xFFFFFFFF),
      Color(0x00FFFFFF),
    ],
    stops: const [0, 0.16, 0.84, 1],
  ).createShader(bounds);

  @override
  Widget build(BuildContext context) => ShaderMask(
    blendMode: BlendMode.dstIn,
    shaderCallback: (bounds) => _fade(bounds, across: true),
    child: ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => _fade(bounds, across: false),
      child: child,
    ),
  );
}

/// Fades its child in, rising a little, once, when first built: the
/// page's entrance (Chris, 2026-11-15). Declarative, so it needs no
/// timer and settles in tests; and nothing moves when the person has
/// asked their system for reduced motion.
class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.child,
    this.duration = const Duration(milliseconds: 500),
    this.delay = Duration.zero,
    this.rise = 0,
  });

  final Widget child;
  final Duration duration;
  final Duration delay;

  /// How far below its place the child starts, in pixels.
  final double rise;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final total = delay + duration;
    final start = delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, rise * (1 - t)),
          child: child,
        ),
      ),
    );
  }
}

/// The gold rule along the top of the sign-in card, drawn from the left
/// as the card settles: the brand's accent, nothing more.
class _GoldAccent extends StatelessWidget {
  const _GoldAccent();

  @override
  Widget build(BuildContext context) {
    const rule = SizedBox(
      height: 4,
      child: ColoredBox(color: AppColors.accentGold),
    );
    if (MediaQuery.disableAnimationsOf(context)) return rule;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1100),
      curve: const Interval(0.45, 1, curve: Curves.easeOutCubic),
      builder: (context, t, _) => Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(widthFactor: t, child: rule),
      ),
    );
  }
}

class _LogoBar extends StatelessWidget {
  const _LogoBar();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: Container(
      height: 77,
      width: double.infinity,
      color: AppColors.surface,
      alignment: Alignment.centerLeft,
      // The logo is oversized and bleeds past the bar in the design;
      // clipping is avoided by letting it overflow its 77px row.
      child: OverflowBox(
        maxHeight: 148,
        alignment: Alignment.centerLeft,
        child: Image.asset(
          'assets/images/gsuhub_logo.png',
          height: 148,
          fit: BoxFit.contain,
        ),
      ),
    ),
  );
}

class _HeadingBlock extends StatelessWidget {
  const _HeadingBlock();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      // Scaled down, never broken mid-word, where the window is narrower
      // than the design's two lines.
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          'DAVAO ORIENTAL STATE\nUNIVERSITY',
          style: AppTextStyles.loginHeadline,
        ),
      ),
      SizedBox(height: 24),
      SizedBox(
        width: 434,
        child: Text(
          'GSUhub  Facility Damage Reporting and Maintenance '
          'Management System',
          style: AppTextStyles.loginSubtitle,
        ),
      ),
      SizedBox(height: 16),
      Text(
        'Excellence, Innovation, and Inclusion in Higher Education.',
        style: AppTextStyles.loginTagline,
      ),
    ],
  );
}

class _SignInCard extends StatelessWidget {
  const _SignInCard({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.passwordFocus,
    required this.obscurePassword,
    required this.onToggleObscure,
    required this.state,
    required this.onSubmit,
    required this.onForgotPassword,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final FocusNode passwordFocus;
  final bool obscurePassword;
  final VoidCallback onToggleObscure;
  final LoginState state;
  final Future<void> Function() onSubmit;
  final Future<void> Function() onForgotPassword;

  @override
  Widget build(BuildContext context) => _Reveal(
    delay: const Duration(milliseconds: 150),
    rise: 16,
    // The card used to be drawn at 80% opacity as a whole, type
    // included. Now only its fill is translucent (2026-11-15), so the
    // words and the fields stay fully legible over the photograph.
    child: Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0x99FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E0B1C30),
            offset: Offset(0, 16),
            blurRadius: 40,
          ),
          BoxShadow(
            color: Color(0x1F0B1C30),
            offset: Offset(0, 2),
            blurRadius: 6,
          ),
        ],
      ),
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _GoldAccent(),
            Padding(
              padding: Breakpoints.isCompact(context)
                  ? const EdgeInsets.fromLTRB(24, 28, 24, 32)
                  : const EdgeInsets.fromLTRB(80, 52, 80, 56),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Welcome back!',
                    style: AppTextStyles.loginCardTitle,
                  ),
                  const SizedBox(height: 40),
                  if (state.errorMessage != null) ...[
                    _Banner(
                      message: state.errorMessage!,
                      background: AppColors.statusPendingBackground,
                      foreground: AppColors.statusPendingForeground,
                      icon: Icons.error_outline,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (state.sessionNotice != null) ...[
                    _Banner(
                      message: state.sessionNotice!,
                      background: AppColors.statusNeutralBackground,
                      foreground: AppColors.statusNeutralForeground,
                      icon: Icons.timer_off_outlined,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (state.infoMessage != null) ...[
                    _Banner(
                      message: state.infoMessage!,
                      background: AppColors.statusResolvedBackground,
                      foreground: AppColors.statusResolvedForeground,
                      icon: Icons.mark_email_read_outlined,
                    ),
                    const SizedBox(height: 16),
                  ],
                  _Field(
                    controller: emailController,
                    hint: 'Email',
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    validator: validateEmail,
                    enabled: !state.isSubmitting,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => passwordFocus.requestFocus(),
                  ),
                  const SizedBox(height: 22),
                  _Field(
                    controller: passwordController,
                    focusNode: passwordFocus,
                    hint: 'Password',
                    obscureText: obscurePassword,
                    autofillHints: const [AutofillHints.password],
                    validator: validatePassword,
                    enabled: !state.isSubmitting,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => onSubmit(),
                    suffix: IconButton(
                      onPressed: onToggleObscure,
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 18,
                      ),
                      tooltip: obscurePassword
                          ? 'Show password'
                          : 'Hide password',
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 45,
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: state.isSubmitting ? null : onSubmit,
                      style:
                          FilledButton.styleFrom(
                            backgroundColor: AppColors.sidebarBackground,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
                            animationDuration: const Duration(
                              milliseconds: 150,
                            ),
                          ).copyWith(
                            // A touch of lift under the pointer, flat again
                            // while pressed: feedback, not decoration.
                            elevation: WidgetStateProperty.resolveWith(
                              (states) =>
                                  states.contains(WidgetState.hovered) &&
                                      !states.contains(WidgetState.pressed)
                                  ? 3
                                  : 0,
                            ),
                          ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        child: state.isSubmitting
                            ? const SizedBox(
                                key: ValueKey('busy'),
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.textOnDark,
                                ),
                              )
                            : const Text(
                                'LOGIN',
                                key: ValueKey('label'),
                                style: AppTextStyles.loginButton,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  TextButton(
                    onPressed: state.isSubmitting ? null : onForgotPassword,
                    child: const Text(
                      'Forget password?',
                      style: AppTextStyles.loginLink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.validator,
    required this.enabled,
    this.focusNode,
    this.obscureText = false,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.suffix,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final void Function(String)? onSubmitted;
  final Widget? suffix;
  final String? Function(String?) validator;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    focusNode: focusNode,
    obscureText: obscureText,
    keyboardType: keyboardType,
    autofillHints: autofillHints,
    textInputAction: textInputAction,
    onFieldSubmitted: onSubmitted,
    validator: validator,
    enabled: enabled,
    style: AppTextStyles.loginFieldValue,
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: AppTextStyles.loginFieldPlaceholder,
      filled: true,
      fillColor: AppColors.surface,
      // A faint indigo under the pointer; the border's own change to the
      // focused colour is animated by the field itself.
      hoverColor: const Color(0x0A241597),
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      border: _border(const Color(0x80000000)),
      enabledBorder: _border(const Color(0x80000000)),
      focusedBorder: _border(AppColors.sidebarBackground, width: 2),
      errorBorder: _border(AppColors.error),
      focusedErrorBorder: _border(AppColors.error, width: 2),
    ),
  );

  static OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(5),
        borderSide: BorderSide(color: color, width: width),
      );
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.message,
    required this.background,
    required this.foreground,
    required this.icon,
  });

  final String message;
  final Color background;
  final Color foreground;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: foreground),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: AppTextStyles.bodySmall.copyWith(color: foreground),
          ),
        ),
      ],
    ),
  );
}
