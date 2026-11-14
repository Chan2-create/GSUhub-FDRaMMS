import 'package:flutter/material.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_text_styles.dart';

/// One of the form's coloured panels — navy for the details and photos,
/// gold for the location (Figma `169:797`, `169:798`, `169:801`): 15px
/// corners, inset 5px from the screen's left edge.
class FormCard extends StatelessWidget {
  const FormCard({
    required this.color,
    required this.child,
    required this.padding,
    super.key,
    this.shadow = false,
  });

  final Color color;
  final Widget child;
  final EdgeInsets padding;

  /// Only the first panel casts one in the design.
  final bool shadow;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(5, 0, 5, 0),
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(15),
      boxShadow: shadow
          ? const [
              BoxShadow(
                color: Color(0x40000000),
                offset: Offset(0, 4),
                blurRadius: 4,
              ),
            ]
          : null,
    ),
    child: child,
  );
}

/// A field's label — "FACILITY / ISSUE TITLE", "BUILDING". Written in
/// sentence case and drawn in capitals, as the design's CSS does.
class FormLabel extends StatelessWidget {
  const FormLabel(this.text, {required this.color, super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: AppTextStyles.formLabel.copyWith(color: color),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}

/// A validation message under a field, in the colour that reads on the
/// panel behind it. Nothing when [message] is null.
class FieldError extends StatelessWidget {
  const FieldError(this.message, {required this.color, super.key});

  final String? message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Text(text, style: AppTextStyles.formError.copyWith(color: color)),
    );
  }
}

/// The gold-tinted text box behind the title and the description
/// (`169:674`, `169:707`).
class TintedTextBox extends StatelessWidget {
  const TintedTextBox({required this.child, super.key, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: AppColors.formFieldTint,
      border: Border.all(color: AppColors.borderStrong),
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0D000000),
          offset: Offset(0, 1),
          blurRadius: 2,
        ),
      ],
    ),
    child: child,
  );
}

/// Two fields side by side with the design's 16px gutter — DAMAGE TYPE and
/// URGENCY LEVEL, BUILDING and ROOM.
class FieldPair extends StatelessWidget {
  const FieldPair({required this.left, required this.right, super.key});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: left),
      const SizedBox(width: 16),
      Expanded(child: right),
    ],
  );
}

/// A label over its select, 8px apart (`169:679`).
class LabelledField extends StatelessWidget {
  const LabelledField({
    required this.label,
    required this.labelColor,
    required this.field,
    required this.errorColor,
    super.key,
    this.error,
  });

  final String label;
  final Color labelColor;
  final Widget field;
  final String? error;
  final Color errorColor;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 6),
        child: FormLabel(label, color: labelColor),
      ),
      const SizedBox(height: 8),
      field,
      FieldError(error, color: errorColor),
    ],
  );
}
