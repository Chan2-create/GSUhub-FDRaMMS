import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../constants/breakpoints.dart';

/// How every console page opens (§36): its name, one line of what it is
/// for, and, at the right, the page's primary action when it has one.
///
/// Side by side, as the designs draw them, or the action under the title
/// on a phone, so the title is never squeezed into breaking mid-word.
/// The first block of the page follows at [gapBelow].
class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.title,
    this.subtitle,
    this.action,
    super.key,
  });

  /// The page's name, as the sidebar and the top bar give it.
  final String title;

  /// One line of purpose, under the name.
  final String? subtitle;

  /// The page's button, at the right of the title: a [PageActionButton]
  /// or a control of the page's own.
  final Widget? action;

  /// From the header to the first block of the page, on every page.
  static const double gapBelow = 24;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: AppTextStyles.pageTitle),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle, style: AppTextStyles.pageSubtitle),
        ],
      ],
    );
    final action = this.action;
    if (action == null) return heading;
    return Breakpoints.isCompact(context)
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 16), action],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: heading),
              const SizedBox(width: 16),
              action,
            ],
          );
  }
}

/// A page's primary action, the same on every page that has one: the
/// brand's navy, square corners, the design's 16 px label, with or
/// without an icon; [outlined] for the secondary kind (Print all labels,
/// Mark All as Read) beside the filled kind (Add Personnel).
class PageActionButton extends StatelessWidget {
  const PageActionButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.outlined = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool outlined;

  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: 24,
    vertical: 12,
  );

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
    );
    final text = Text(label, style: AppTextStyles.ctaLabel);
    final icon = this.icon;
    if (outlined) {
      final style = OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        padding: _padding,
        shape: shape,
      );
      return icon == null
          ? OutlinedButton(onPressed: onPressed, style: style, child: text)
          : OutlinedButton.icon(
              onPressed: onPressed,
              icon: icon,
              label: text,
              style: style,
            );
    }
    final style = FilledButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.textOnDark,
      padding: _padding,
      shape: shape,
    );
    return icon == null
        ? FilledButton(onPressed: onPressed, style: style, child: text)
        : FilledButton.icon(
            onPressed: onPressed,
            icon: icon,
            label: text,
            style: style,
          );
  }
}
