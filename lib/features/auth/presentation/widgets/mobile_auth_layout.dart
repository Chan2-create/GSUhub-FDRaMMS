import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';

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
  static const double _minDensity = 0.35;

  /// The page is never made smaller than this.
  static const double _minScale = 0.85;

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
    if ((density - _density).abs() < 0.002 && (scale - _scale).abs() < 0.002) {
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
class AuthTextField extends StatelessWidget {
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
  });

  final String label;
  final TextStyle labelStyle;
  final TextEditingController controller;
  final String hint;
  final AuthFieldStyle style;
  final String? error;
  final bool obscure;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(label, style: labelStyle),
      ),
      SizedBox(height: style.labelGap),
      DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.authInputFill,
          borderRadius: BorderRadius.circular(12),
          border: style.border == null
              ? null
              : Border.all(
                  color: error == null ? style.border! : AppColors.error,
                ),
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
          child: Center(
            child: TextField(
              controller: controller,
              enabled: enabled,
              obscureText: obscure,
              keyboardType: keyboardType,
              autofillHints: autofillHints,
              textInputAction: textInputAction,
              textCapitalization: textCapitalization,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              style: AppTextStyles.authInput,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: AppTextStyles.authInput.copyWith(
                  color: style.placeholder,
                ),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: style.horizontalPadding,
                ),
              ),
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
  Widget build(BuildContext context) => SizedBox(
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
  );
}

/// An inline notice above a form — an error, or the confirmation after
/// signing up. Not in the design; plain, and flagged.
class AuthNotice extends StatelessWidget {
  const AuthNotice({required this.message, super.key, this.isError = true});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isError
            ? AppColors.statusPendingBackground
            : AppColors.statusResolvedBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: AppTextStyles.signUpText.copyWith(
          color: isError
              ? AppColors.statusPendingForeground
              : AppColors.statusResolvedForeground,
        ),
      ),
    ),
  );
}
