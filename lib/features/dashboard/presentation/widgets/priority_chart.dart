import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/widgets/priority_chip.dart';
import '../dashboard_providers.dart';

/// "Open Reports by Priority" (§35): one bar per level, Critical first,
/// in the level's own colour, the same the chips use in every table.
///
/// Bars are scaled against the busiest level, so the longest fills the
/// track and the levels compare at a glance. The solid part of a bar is
/// the reports whose priority an administrator has confirmed; the pale
/// part still carries the system's recommendation or the requestor's own
/// choice, which the manuscript has confirmed before work-order
/// assignment (§1.5), so what waits for a decision shows as well as how
/// much is open.
class PriorityChart extends StatelessWidget {
  const PriorityChart({required this.counts, super.key});

  final List<PriorityCount> counts;

  @override
  Widget build(BuildContext context) {
    final busiest = counts
        .map((count) => count.total)
        .fold<int>(1, (a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, count) in counts.indexed) ...[
          if (i > 0) const SizedBox(height: 20),
          _Bar(count: count, busiest: busiest),
        ],
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.count, required this.busiest});

  final PriorityCount count;
  final int busiest;

  @override
  Widget build(BuildContext context) {
    final colour = PriorityChip.inkFor(count.level);
    final total = count.total;
    return Semantics(
      container: true,
      label:
          '${count.level.title}: $total open '
          'report${total == 1 ? '' : 's'}'
          '${count.unconfirmed == 0 ? '' : ', ${count.unconfirmed} awaiting confirmation'}',
      excludeSemantics: true,
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Align(
              alignment: Alignment.centerLeft,
              child: PriorityChip(level: count.level),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 10,
                child: ColoredBox(
                  color: AppColors.trackBackground,
                  child: Row(
                    children: [
                      if (count.confirmed > 0)
                        Flexible(
                          flex: count.confirmed,
                          child: ColoredBox(
                            color: colour,
                            child: const SizedBox.expand(),
                          ),
                        ),
                      if (count.unconfirmed > 0)
                        Flexible(
                          flex: count.unconfirmed,
                          child: ColoredBox(
                            color: colour.withValues(alpha: 0.35),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      // The rest of the track, so a quiet level's bar is
                      // visibly shorter than a busy one's.
                      if (busiest > total)
                        Flexible(
                          flex: busiest - total,
                          child: const SizedBox.shrink(),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 32,
            child: Text(
              '$total',
              style: AppTextStyles.barLabel,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

/// The key in the card's header: what the solid and the pale parts of a
/// bar mean. Drawn in a neutral dark rather than any one level's colour.
class PriorityChartLegend extends StatelessWidget {
  const PriorityChartLegend({super.key});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      const _LegendKey(color: AppColors.textPrimary, label: 'CONFIRMED'),
      _LegendKey(
        color: AppColors.textPrimary.withValues(alpha: 0.35),
        label: 'AWAITING CONFIRMATION',
      ),
    ],
  );
}

class _LegendKey extends StatelessWidget {
  const _LegendKey({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label, style: AppTextStyles.legendKeyUpper),
    ],
  );
}
