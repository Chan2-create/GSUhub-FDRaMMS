import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../analytics_summary.dart';

/// "Monthly Report Volume" (Figma `85:4027`): one bar per month, the last
/// six, the current month darkest.
///
/// The frame draws the month labels — NOV to APR, the last one darkened —
/// but no bars at all. The bars here follow the dashboard's volume chart
/// (2.A): primary navy with rounded ends, the current month at full
/// strength and earlier months lighter, echoing how the design's labels
/// already set the current month apart.
class MonthlyVolumeChart extends StatelessWidget {
  const MonthlyVolumeChart({required this.months, super.key});

  final List<MonthlyValue<int>> months;

  static const double _plotHeight = 146;

  @override
  Widget build(BuildContext context) {
    final peak = months.fold<int>(0, (max, m) => m.value > max ? m.value : max);
    final label = DateFormat('MMM');

    return Semantics(
      label:
          'Reports per month: '
          '${months.map((m) => '${label.format(m.month)} ${m.value}').join(', ')}',
      child: SizedBox(
        height: 192,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < months.length; i++)
              Expanded(
                child: _Bar(
                  label: label.format(months[i].month).toUpperCase(),
                  count: months[i].value,
                  fraction: peak == 0 ? 0 : months[i].value / peak,
                  isCurrent: i == months.length - 1,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.count,
    required this.fraction,
    required this.isCurrent,
  });

  final String label;
  final int count;
  final double fraction;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final emphasis = isCurrent ? AppColors.textPrimary : null;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          '$count',
          style: AppTextStyles.chartAxisLabel.copyWith(color: emphasis),
        ),
        const SizedBox(height: 4),
        Container(
          width: 32,
          // A zero-report month keeps a sliver, so the month reads as
          // "none" rather than as missing.
          height: (MonthlyVolumeChart._plotHeight * fraction).clamp(
            2,
            MonthlyVolumeChart._plotHeight,
          ),
          decoration: BoxDecoration(
            color: isCurrent
                ? AppColors.primary
                : AppColors.primary.withValues(alpha: 0.45),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: AppTextStyles.chartAxisLabel.copyWith(color: emphasis),
        ),
      ],
    );
  }
}
