import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/models/service_feedback.dart';

/// The word for a rating of [stars], as the Ratings screen writes it under
/// the stars (Figma 169:1797 shows "Very Good" at four). Chris chose the
/// rest of the scale (3.C): Poor, Fair, Good, Very Good, Excellent.
String ratingWord(int stars) => switch (stars) {
  1 => 'Poor',
  2 => 'Fair',
  3 => 'Good',
  4 => 'Very Good',
  5 => 'Excellent',
  _ => '',
};

/// Five stars, filled gold up to [value] and outlined in sand beyond it
/// (Figma 169:1797). Tappable when [onChanged] is given; each star is a
/// 48px target with its own label for screen readers.
class StarRating extends StatelessWidget {
  const StarRating({
    required this.value,
    required this.label,
    super.key,
    this.onChanged,
    this.size = 40,
  });

  /// 0 for not rated yet.
  final int value;

  /// What is being rated, for screen readers — "Response time".
  final String label;

  final ValueChanged<int>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final stars = [
      for (var star = 1; star <= ServiceFeedback.maxRating; star++)
        _Star(
          filled: star <= value,
          size: size,
          semanticLabel:
              '$label: $star of ${ServiceFeedback.maxRating}, '
              '${ratingWord(star)}',
          selected: star == value,
          onTap: onChanged == null ? null : () => onChanged!(star),
        ),
    ];

    if (onChanged == null) {
      return Semantics(
        label: value == 0
            ? '$label: not rated'
            : '$label: $value of ${ServiceFeedback.maxRating}, '
                  '${ratingWord(value)}',
        excludeSemantics: true,
        child: Row(mainAxisSize: MainAxisSize.min, children: stars),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: stars);
  }
}

class _Star extends StatelessWidget {
  const _Star({
    required this.filled,
    required this.size,
    required this.semanticLabel,
    required this.selected,
    this.onTap,
  });

  final bool filled;
  final double size;
  final String semanticLabel;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      filled ? Icons.star_rounded : Icons.star_outline_rounded,
      size: size,
      color: filled ? AppColors.accentGold : AppColors.trackingRail,
    );
    if (onTap == null) return icon;

    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: size * 0.7,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}
