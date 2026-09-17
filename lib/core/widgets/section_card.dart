import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

/// Bordered white panel with a heading and an optional trailing action —
/// the container shared by "Recent Reports", "Reports by Category",
/// "Recent Activity" and "Monthly Report Volume by Building".
class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.title,
    required this.child,
    super.key,
    this.subtitle,
    this.trailing,
    this.contentPadding = const EdgeInsets.all(24),
    this.headerPadding = const EdgeInsets.fromLTRB(24, 16, 24, 17),
    this.dividerUnderHeader = false,
  });

  final String title;
  final String? subtitle;

  /// Right-aligned header slot — "View All", a legend, a toggle.
  final Widget? trailing;

  final Widget child;
  final EdgeInsets contentPadding;
  final EdgeInsets headerPadding;

  /// The Recent Reports table rules off its header; the chart cards do
  /// not.
  final bool dividerUnderHeader;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0D000000),
          offset: Offset(0, 1),
          blurRadius: 1,
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: headerPadding,
          decoration: dividerUnderHeader
              ? const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppColors.borderSubtle),
                  ),
                )
              : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: AppTextStyles.sectionTitle),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle!, style: AppTextStyles.bodySmall),
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        Flexible(
          child: Padding(padding: contentPadding, child: child),
        ),
      ],
    ),
  );
}
