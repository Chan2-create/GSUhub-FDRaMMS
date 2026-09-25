import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/enums/date_range_filter.dart';
import '../analytics_providers.dart';

/// The top bar's "Last 30 Days" control, shown on the Analytics page only
/// (Figma `87:4308`). The period it sets drives every figure on the page
/// and the Export Data file.
class AnalyticsRangeSelect extends ConsumerWidget {
  const AnalyticsRangeSelect({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(analyticsRangeProvider);
    return PopupMenuButton<DateRangeFilter>(
      tooltip: 'Analytics period',
      position: PopupMenuPosition.under,
      initialValue: range,
      onSelected: ref.read(analyticsRangeProvider.notifier).set,
      itemBuilder: (context) => [
        for (final option in DateRangeFilter.values)
          PopupMenuItem(value: option, child: Text(option.label)),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(17, 9, 14, 9),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(range.label, style: AppTextStyles.rangeSelect),
            const SizedBox(width: 8),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: AppColors.textPrimary,
            ),
          ],
        ),
      ),
    );
  }
}
