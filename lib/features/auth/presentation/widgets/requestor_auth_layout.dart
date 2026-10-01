import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';

/// What the faculty and staff sign-in and sign-up pages share (Figma
/// `193:310`, `194:455`): the GSUhub mark, "DAVAO ORIENTAL STATE
/// UNIVERSITY", a rounded card holding the form, and a footer line.
///
/// Laid out in a scroll view centred at the design's 342px card width, so
/// a short phone scrolls and a tablet does not stretch the form.
class RequestorAuthLayout extends StatelessWidget {
  const RequestorAuthLayout({
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

  /// The card's contents.
  final Widget child;

  /// The card's width in the design.
  static const double cardWidth = 342;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.mobilePageBackground,
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: cardWidth),
            child: Column(
              children: [
                SizedBox(height: logoTop),
                // The exported mark carries transparent margins: its 148px
                // box runs under the university line, which the design
                // places 114px below the box's top.
                const SizedBox(
                  height: 114,
                  child: OverflowBox(
                    maxHeight: 148,
                    alignment: Alignment.topCenter,
                    child: Image(
                      image: AssetImage('assets/images/gsuhub_logo.png'),
                      width: 148,
                      height: 148,
                      semanticLabel: 'GSUhub',
                    ),
                  ),
                ),
                const Text(
                  'DAVAO ORIENTAL STATE UNIVERSITY',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.authUniversity,
                ),
                SizedBox(height: cardGap),
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
                  child: Padding(padding: cardPadding, child: child),
                ),
                const SizedBox(height: 40),
                footer,
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    ),
  );
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
            : Text(label, style: AppTextStyles.authButton),
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
