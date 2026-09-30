import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

/// Dashboard summary tile — a large count with a caption and a coloured
/// rule down its left edge (Figma `196:571` and siblings).
///
/// Shared rather than dashboard-local because the same tile recurs on the
/// Damage Reports, Inventory and Personnel screens in later objectives.
class StatCard extends StatelessWidget {
  const StatCard({
    required this.label,
    required this.accent,
    super.key,
    this.value,
    this.valueText,
    this.definition,
    this.isLoading = false,
    this.hasError = false,
  });

  final String label;

  /// The count. Null renders a placeholder dash — used for the error state
  /// and while unset.
  final int? value;

  /// A pre-formatted value, for metrics that are not counts ("4.2h").
  /// Takes precedence over [value]; null falls back to it.
  final String? valueText;

  /// How the number is computed, shown as a tooltip on the card. Metrics
  /// whose definition is a judgement call — what "response time" measures
  /// from and to — should carry one, so the figure can be defended.
  final String? definition;

  final Color accent;
  final bool isLoading;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final card = _card();
    final text = definition;
    return text == null ? card : Tooltip(message: text, child: card);
  }

  Widget _card() => Container(
    height: 113,
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0x66000000)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x40000000),
          offset: Offset(0, 4),
          blurRadius: 4,
        ),
      ],
    ),
    child: Row(
      children: [
        // The coloured left rule, inset so the card's rounded corner is
        // not clipped by a square edge.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 7),
          child: Container(width: 5, color: accent),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _value(),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: AppTextStyles.statLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _value() {
    if (isLoading) {
      return const SizedBox(
        height: 30,
        width: 30,
        child: Padding(
          padding: EdgeInsets.all(4),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final text = valueText ?? (value == null ? null : '$value');
    if (hasError || text == null) {
      // A dash rather than a zero: "we could not read this" and "there are
      // none" are different facts, and showing 0 for the former would be a
      // lie the administrator acts on.
      return Text(
        '—',
        style: AppTextStyles.statValue.copyWith(color: AppColors.textFaint),
      );
    }
    return Text(text, style: AppTextStyles.statValue);
  }
}
