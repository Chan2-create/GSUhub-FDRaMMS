import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../enums/priority_level.dart';

/// Priority pill for reports and work orders (Figma `196:1371`).
///
/// **Filled** when the priority is confirmed and **outlined** when it is
/// not. Until an administrator confirms a report's official priority
/// (Objective 4.C), the only value there is to show is the requestor's
/// own selection — and manuscript §1.2 is explicit that this "does not
/// solely determine the official priority level". Drawing the two
/// identically would present a requestor's guess as a GSU decision.
class PriorityChip extends StatelessWidget {
  const PriorityChip({
    required this.level,
    super.key,
    this.confirmed = true,
    this.dense = false,
  });

  final PriorityLevel level;

  /// False for a requestor's initial priority awaiting confirmation.
  final bool confirmed;

  /// Smaller pill for Kanban cards and queue cards.
  final bool dense;

  static const String unconfirmedTooltip =
      'Initial priority — pending administrator confirmation';

  static (Color, Color) paletteFor(PriorityLevel level) => switch (level) {
    PriorityLevel.low => (
      AppColors.priorityLowBackground,
      AppColors.priorityLowForeground,
    ),
    PriorityLevel.medium => (
      AppColors.priorityMediumBackground,
      AppColors.priorityMediumForeground,
    ),
    PriorityLevel.high => (
      AppColors.priorityHighBackground,
      AppColors.priorityHighForeground,
    ),
    PriorityLevel.critical => (
      AppColors.priorityCriticalBackground,
      AppColors.priorityCriticalForeground,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = paletteFor(level);

    // An outlined chip takes its colour from the level's *filled* colour so
    // CRITICAL — white text on red — does not become white-on-white.
    final outlineColor = level == PriorityLevel.critical
        ? background
        : foreground;

    final chip = Container(
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: confirmed ? background : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: confirmed ? null : Border.all(color: outlineColor),
      ),
      child: Text(
        confirmed ? level.label : '${level.label}*',
        style: (dense ? AppTextStyles.badgeText : AppTextStyles.priorityChip)
            .copyWith(color: confirmed ? foreground : outlineColor),
      ),
    );

    if (confirmed) return chip;
    return Tooltip(message: unconfirmedTooltip, child: chip);
  }
}
