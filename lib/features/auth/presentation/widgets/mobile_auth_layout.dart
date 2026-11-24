import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/utils/account_validation.dart';
import '../../../../core/widgets/press_scale.dart';

/// What the faculty and staff sign-in and sign-up pages share (Figma
/// `193:310`, `194:455`): the GSUhub mark, "DAVAO ORIENTAL STATE
/// UNIVERSITY", a rounded card holding the form, and a footer line.
///
/// **Fitted to the phone.** As drawn the two pages are taller than most
/// phones (sign-up runs to 1046px), so they used to scroll. Now the page
/// is fitted to the screen it is on (2026-11-13), in two steps and in
/// this order:
///
/// 1. the vertical spacing ([AuthGap]s, the card's top and bottom
///    padding, the mark's size) is tightened, as far as [_minDensity] of
///    what the design draws;
/// 2. if that is not enough, the whole page is made a little smaller,
///    never below [_minScale], so type and fields stay usable.
///
/// A phone too short even for that scrolls, as before. With the keyboard
/// up the fit is left as it was and the page scrolls, so the field being
/// typed in comes into view rather than the page shrinking under the
/// thumb. On a tall phone or a tablet nothing changes: the page is as
/// drawn, centred at the design's 342px card width.
class MobileAuthLayout extends StatefulWidget {
  const MobileAuthLayout({
    required this.logoTop,
    required this.cardGap,
    required this.cardPadding,
    required this.footer,
    required this.child,
    super.key,
  });

  /// Space above the mark — 29 on sign-in, 49 on sign-up.
  final double logoTop;

  /// Space between the university line and the card.
  final double cardGap;

  final EdgeInsets cardPadding;

  /// The line under the card; each page sets its own type.
  final Widget footer;

  /// The card's contents. Its vertical spacing is given as [AuthGap]s,
  /// so it can be tightened with the rest.
  final Widget child;

  /// The card's width in the design.
  static const double cardWidth = 342;

  @override
  State<MobileAuthLayout> createState() => _MobileAuthLayoutState();
}

class _MobileAuthLayoutState extends State<MobileAuthLayout> {
  /// How much of the design's vertical spacing is kept: 1 is as drawn.
  double _density = 1;

  /// The page's size once its spacing is as tight as it goes: 1 is full.
  double _scale = 1;

  final _content = GlobalKey();

  /// Spacing is never tightened past this share of the design's.
  ///
  /// 0.35 until 2026-11-17, when Create Account gained the department
  /// field and no longer fitted a 640px phone; both limits came down a
  /// step. A field is still 45px tall at the smallest, a tap target's
  /// height. 0.25 until 2026-11-25, when the terms box came: the spacing
  /// gives way rather than the type, which had just been made larger.
  static const double _minDensity = 0.2;

  /// The page is never made smaller than this (0.85 until 2026-11-17).
  static const double _minScale = 0.8;

  /// Fits the page to a screen [viewport] tall, from what was just laid
  /// out: its height, and how much of that height is spacing.
  void _fit(double viewport) {
    if (!mounted) return;
    final box = _content.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;

    var spacing = 0.0;
    void visit(RenderObject node) {
      if (node is _RenderAuthGap) spacing += node.designHeight;
      node.visitChildren(visit);
    }

    visit(box);
    if (spacing <= 0) return;

    // Height is linear in the density, so one measurement solves it.
    final fixed = box.size.height - _density * spacing;
    final density = ((viewport - fixed) / spacing).clamp(_minDensity, 1.0);
    final height = fixed + density * spacing;
    final scale = height <= viewport
        ? 1.0
        : (viewport / height).clamp(_minScale, 1.0);
    // Settled once another pass would move the page by under a tenth of a
    // pixel. A share of the spacing (0.002 until 2026-11-25) could stop
    // nearly a pixel short on sign-up, whose spacing is some 450px, and
    // leave it a hair to scroll.
    if (((density - _density) * spacing).abs() < 0.1 &&
        ((scale - _scale) * height).abs() < 0.1) {
      return;
    }
    setState(() {
      _density = density;
      _scale = scale;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Read above the Scaffold, which hides the keyboard from its body.
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      backgroundColor: AppColors.mobilePageBackground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (!keyboardUp && constraints.hasBoundedHeight) {
              // A pixel spare, so rounding never leaves a hair to scroll.
              final viewport = constraints.maxHeight - 1;
              SchedulerBinding.instance.addPostFrameCallback(
                (_) => _fit(viewport),
              );
            }
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                // Takes the scaled page's height, so nothing is left to
                // scroll below it.
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: _scale,
                  child: Transform.scale(
                    scale: _scale,
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: MobileAuthLayout.cardWidth,
                      ),
                      child: AuthDensity(
                        value: _density,
                        child: Column(
                          key: _content,
                          children: [
                            AuthGap(widget.logoTop),
                            const _Mark(),
                            const Text(
                              'DAVAO ORIENTAL STATE UNIVERSITY',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.authUniversity,
                            ),
                            AuthGap(widget.cardGap),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppColors.authCard,
                                borderRadius: BorderRadius.circular(32),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x141E1B4B),
                                    blurRadius: 40,
                                    offset: Offset(0, 20),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: EdgeInsets.only(
                                  left: widget.cardPadding.left,
                                  right: widget.cardPadding.right,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    AuthGap(widget.cardPadding.top),
                                    widget.child,
                                    AuthGap(widget.cardPadding.bottom),
                                  ],
                                ),
                              ),
                            ),
                            const AuthGap(40),
                            widget.footer,
                            const AuthGap(24),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// How much of the design's vertical spacing the sign-in and sign-up
/// pages keep on this screen: 1 as drawn, less on a short phone. Set by
/// [MobileAuthLayout]; read by [AuthGap].
class AuthDensity extends InheritedWidget {
  const AuthDensity({required this.value, required super.child, super.key});

  final double value;

  /// The density here, or 1 outside a fitted page.
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuthDensity>()?.value ?? 1;

  @override
  bool updateShouldNotify(AuthDensity old) => old.value != value;
}

/// A vertical space on the sign-in and sign-up pages: [height] as the
/// design draws it, less where the phone is too short for the page.
class AuthGap extends StatelessWidget {
  const AuthGap(this.height, {super.key});

  /// The space in the design.
  final double height;

  @override
  Widget build(BuildContext context) => _AuthGapMarker(
    designHeight: height,
    child: SizedBox(height: height * AuthDensity.of(context)),
  );
}

/// The GSUhub mark. The exported image carries transparent margins: its
/// 148px box runs under the university line, which the design places
/// 114px below the box's top. On a short phone it is drawn smaller, down
/// to 70px of the 114.
class _Mark extends StatelessWidget {
  const _Mark();

  static const double _designHeight = 114;
  static const double _compactHeight = 70;
  static const double _designBox = 148;

  @override
  Widget build(BuildContext context) {
    final height =
        _compactHeight +
        (_designHeight - _compactHeight) * AuthDensity.of(context);
    final box = _designBox * height / _designHeight;
    return _AuthGapMarker(
      designHeight: _designHeight - _compactHeight,
      child: SizedBox(
        height: height,
        child: OverflowBox(
          maxHeight: box,
          alignment: Alignment.topCenter,
          child: Image(
            image: const AssetImage('assets/images/gsuhub_logo.png'),
            width: box,
            height: box,
            semanticLabel: 'GSUhub',
          ),
        ),
      ),
    );
  }
}

/// Marks [designHeight] of its child's height as spacing the page may
/// tighten, for [MobileAuthLayout] to add up after layout.
class _AuthGapMarker extends SingleChildRenderObjectWidget {
  const _AuthGapMarker({required this.designHeight, super.child});

  final double designHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAuthGap(designHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderAuthGap renderObject) {
    renderObject.designHeight = designHeight;
  }
}

class _RenderAuthGap extends RenderProxyBox {
  _RenderAuthGap(this.designHeight);

  double designHeight;
}

/// A labelled input on either card. The two cards draw their boxes
/// differently — sign-in raised on a shadow, sign-up outlined — so the
/// look comes in through [style].
///
/// A password field ([obscure]) has an eye at its end that shows and
/// hides what was typed (2026-11-17), as the console's sign-in does: the
/// same icons, the same tooltips. It is a button of its own beside the
/// text, so it neither takes the typing nor submits the form.
class AuthTextField extends StatefulWidget {
  const AuthTextField({
    required this.label,
    required this.labelStyle,
    required this.controller,
    required this.hint,
    required this.style,
    super.key,
    this.error,
    this.obscure = false,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.below,
    this.maxLength,
    this.inputFormatters,
    this.focusNode,
  });

  final String label;
  final TextStyle labelStyle;
  final TextEditingController controller;
  final String hint;
  final AuthFieldStyle style;
  final String? error;

  /// A password: hidden as typed, with the eye to show it.
  final bool obscure;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  /// Shown under the box, above any error: the password requirements.
  final Widget? below;

  /// The most characters the field takes (2026-11-25): more are not let
  /// in, and a count, "5/12", sits at the end of the label's line, where
  /// it costs the form no height.
  final int? maxLength;

  /// Applied to what is typed or pasted, before [maxLength].
  final List<TextInputFormatter>? inputFormatters;

  final FocusNode? focusNode;

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  /// Whether a password is hidden right now.
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final error = widget.error;
    final hidden = widget.obscure && _hidden;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: switch (widget.maxLength) {
            null => Text(widget.label, style: widget.labelStyle),
            final max => Row(
              children: [
                Expanded(child: Text(widget.label, style: widget.labelStyle)),
                _CharacterCount(controller: widget.controller, max: max),
              ],
            ),
          },
        ),
        SizedBox(height: style.labelGap),
        AuthFieldBox(
          style: style,
          hasError: error != null,
          // The eye sits beside the text, not inside its decoration: a
          // suffix in a collapsed field makes the field as tall as the
          // icon's tap area and pins the text to its top, 13px above the
          // box's middle (2026-11-17). Beside it, the text is laid out as
          // every other field's is, and the row centres both.
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  enabled: widget.enabled,
                  inputFormatters: [
                    ...?widget.inputFormatters,
                    if (widget.maxLength case final max?)
                      LengthLimitingTextInputFormatter(max),
                  ],
                  obscureText: hidden,
                  enableSuggestions: !widget.obscure,
                  autocorrect: !widget.obscure,
                  keyboardType: widget.keyboardType,
                  autofillHints: widget.autofillHints,
                  textInputAction: widget.textInputAction,
                  textCapitalization: widget.textCapitalization,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  style: AppTextStyles.authInput,
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: AppTextStyles.authInput.copyWith(
                      color: style.placeholder,
                    ),
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: EdgeInsets.only(
                      left: style.horizontalPadding,
                      right: widget.obscure ? 4 : style.horizontalPadding,
                    ),
                  ),
                ),
              ),
              if (widget.obscure)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: IconButton(
                    onPressed: widget.enabled
                        ? () => setState(() => _hidden = !_hidden)
                        : null,
                    icon: Icon(
                      _hidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                      color: AppColors.warmText,
                    ),
                    tooltip: _hidden ? 'Show password' : 'Hide password',
                  ),
                ),
            ],
          ),
        ),
        ?widget.below,
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

/// The box an input sits in, as [style] draws it: [AuthTextField]'s, and
/// the department dropdown's on the Create Account card.
class AuthFieldBox extends StatelessWidget {
  const AuthFieldBox({
    required this.style,
    required this.child,
    super.key,
    this.hasError = false,
  });

  final AuthFieldStyle style;
  final bool hasError;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.authInputFill,
      borderRadius: BorderRadius.circular(12),
      border: style.border == null
          ? null
          : Border.all(color: hasError ? AppColors.error : style.border!),
      boxShadow: style.raised
          ? const [
              BoxShadow(
                color: Color(0x2E1E1B4B),
                blurRadius: 6,
                offset: Offset(0, 3),
              ),
            ]
          : null,
    ),
    child: SizedBox(
      height: style.height,
      child: Center(child: child),
    ),
  );
}

/// Under a new password: what it must have, each ticked off as it is
/// typed (2026-11-17). The rules are [PasswordPolicy]'s.
///
/// Shown from the first character: by then the keyboard is up and the
/// page scrolls, so the list costs the form nothing at rest, when it has
/// to fit the phone. Sending the form with the field empty says what the
/// password needs in the field's error.
///
/// **2026-11-25:** also shown while the field has the focus, before the
/// first character, each rule with its empty circle; the keyboard is up
/// by then, so it still costs the form nothing at rest.
class PasswordRequirements extends StatelessWidget {
  const PasswordRequirements({
    required this.controller,
    this.focusNode,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, ?focusNode]),
    builder: (context, _) {
      final password = controller.text;
      final focused = focusNode?.hasFocus ?? false;
      if (password.isEmpty && !focused) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(left: 4, top: 8),
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: 'Password requirements',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final rule in PasswordPolicy.rules)
                _Requirement(label: rule.label, met: rule.isMetBy(password)),
            ],
          ),
        ),
      );
    },
  );
}

/// Under Confirm Password (2026-11-25): whether it matches the password
/// above, as it is typed into either. Nothing until something is typed
/// here; the form's own error takes its place once the form is sent.
class PasswordMatch extends StatelessWidget {
  const PasswordMatch({
    required this.password,
    required this.confirm,
    super.key,
  });

  final TextEditingController password;
  final TextEditingController confirm;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([password, confirm]),
    builder: (context, _) {
      if (confirm.text.isEmpty) return const SizedBox.shrink();
      final matches = confirm.text == password.text;
      return Padding(
        padding: const EdgeInsets.only(left: 4, top: 8),
        child: _Requirement(
          label: matches ? 'Passwords match' : 'The passwords do not match.',
          met: matches,
          failed: !matches,
          semanticsLabel: matches
              ? 'Passwords match'
              : 'The passwords do not match',
        ),
      );
    },
  );
}

/// "5/12": how many characters of the most a field takes.
class _CharacterCount extends StatelessWidget {
  const _CharacterCount({required this.controller, required this.max});

  final TextEditingController controller;
  final int max;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: controller,
    builder: (context, value, _) {
      final count = value.text.characters.length;
      return Semantics(
        label: '$count of $max characters',
        excludeSemantics: true,
        child: Text(
          '$count/$max',
          style: AppTextStyles.formError.copyWith(
            color: AppColors.warmText,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      );
    },
  );
}

class _Requirement extends StatelessWidget {
  const _Requirement({
    required this.label,
    required this.met,
    this.failed = false,
    this.semanticsLabel,
  });

  final String label;
  final bool met;

  /// Drawn as an error rather than as a rule not yet met.
  final bool failed;

  /// What a screen reader says, when not "[label]: met / not yet".
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final color = met
        ? AppColors.accountActive
        : failed
        ? AppColors.error
        : AppColors.warmText;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      // A line of its own for a screen reader: which rule, and whether it
      // is met yet.
      child: Semantics(
        container: true,
        label: semanticsLabel ?? '$label: ${met ? 'met' : 'not yet'}',
        excludeSemantics: true,
        child: Row(
          children: [
            Icon(
              met
                  ? Icons.check_circle
                  : failed
                  ? Icons.error_outline
                  : Icons.radio_button_unchecked,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: AppTextStyles.formError.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How one card draws its input boxes.
class AuthFieldStyle {
  const AuthFieldStyle({
    required this.height,
    required this.labelGap,
    required this.horizontalPadding,
    required this.placeholder,
    this.border,
    this.raised = false,
  });

  /// Sign-in (`193:367`): 58px, on a shadow, no outline.
  static const signIn = AuthFieldStyle(
    height: 58,
    labelGap: 6,
    horizontalPadding: 21,
    placeholder: AppColors.authPlaceholder,
    raised: true,
  );

  /// Sign-up (`194:417`): 56px, outlined in sand.
  static const signUp = AuthFieldStyle(
    height: 56,
    labelGap: 6,
    horizontalPadding: 17,
    placeholder: AppColors.signUpPlaceholder,
    border: AppColors.signUpInputBorder,
  );

  final double height;
  final double labelGap;
  final double horizontalPadding;
  final Color placeholder;
  final Color? border;
  final bool raised;
}

/// LOGIN TO DASHBOARD, CREATE ACCOUNT, REGISTER: full width, rounded, on a
/// soft shadow, with a spinner in place of the label while [busy].
class AuthButton extends StatelessWidget {
  const AuthButton({
    required this.label,
    required this.color,
    required this.onPressed,
    super.key,
    this.height = 52,
    this.busy = false,
  });

  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final double height;
  final bool busy;

  @override
  Widget build(BuildContext context) => PressScale(
    child: SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FilledButton(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: color,
            disabledBackgroundColor: color.withValues(alpha: 0.7),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              // One line, whatever the room: a label that wrapped ran out
              // of the button's 52px.
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: AppTextStyles.authButton,
                  ),
                ),
        ),
      ),
    ),
  );
}

/// An inline notice above a form — an error, the confirmation after
/// signing up, or ([neutral]) why the session ended. Not in the design;
/// plain, and flagged.
class AuthNotice extends StatelessWidget {
  const AuthNotice({
    required this.message,
    super.key,
    this.isError = true,
    this.neutral = false,
  });

  final String message;
  final bool isError;

  /// Neither an error nor good news: grey, as a sign-out notice reads.
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = neutral
        ? (AppColors.statusNeutralBackground, AppColors.statusNeutralForeground)
        : isError
        ? (AppColors.statusPendingBackground, AppColors.statusPendingForeground)
        : (
            AppColors.statusResolvedBackground,
            AppColors.statusResolvedForeground,
          );
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          message,
          style: AppTextStyles.signUpText.copyWith(color: foreground),
        ),
      ),
    );
  }
}
