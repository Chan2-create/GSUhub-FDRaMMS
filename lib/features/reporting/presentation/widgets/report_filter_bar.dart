import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/constants/damage_categories.dart';
import '../../../../core/enums/priority_level.dart';
import '../../../../core/enums/report_status.dart';
import '../../../../core/widgets/filter_select.dart';
import '../report_providers.dart';

/// Damage Type / Priority / Status filters and "Clear all filters"
/// (Figma `198:2794`).
///
/// The damage types are the manuscript's seven categories, not the
/// mockup's "HVAC / Furniture / Mechanical" — those are placeholders, and
/// a filter offering a category no report can carry would never match.
class ReportFilterBar extends ConsumerWidget {
  const ReportFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(reportsViewProvider);
    final controller = ref.read(reportsViewProvider.notifier);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.borderStrong),
          left: BorderSide(color: AppColors.borderStrong),
          right: BorderSide(color: AppColors.borderStrong),
          bottom: BorderSide(color: AppColors.borderStrong),
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 13),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 24,
        runSpacing: 12,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(
                'assets/icons/filter_list.svg',
                width: 18,
                height: 12,
                colorFilter: const ColorFilter.mode(
                  AppColors.textSecondary,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 12),
              const Text('Filters:', style: AppTextStyles.filterLabel),
            ],
          ),
          FilterSelect<DamageCategory>(
            placeholder: 'Damage Type',
            value: view.category,
            onChanged: controller.setCategory,
            options: [
              const FilterOption(value: null, label: 'All damage types'),
              for (final category in DamageCategory.values)
                FilterOption(value: category, label: category.label),
            ],
          ),
          FilterSelect<PriorityLevel>(
            placeholder: 'Priority',
            value: view.priority,
            onChanged: controller.setPriority,
            options: [
              const FilterOption(value: null, label: 'All priorities'),
              for (final level in PriorityLevel.values)
                FilterOption(value: level, label: level.label),
            ],
          ),
          FilterSelect<ReportStatus>(
            placeholder: 'Status',
            value: view.status,
            onChanged: controller.setStatus,
            options: [
              const FilterOption(value: null, label: 'All statuses'),
              for (final status in ReportStatus.values)
                FilterOption(value: status, label: status.label),
            ],
          ),
          TextButton(
            onPressed: view.hasFilters ? controller.clearFilters : null,
            child: const Text(
              'Clear all filters',
              style: AppTextStyles.linkText,
            ),
          ),
        ],
      ),
    );
  }
}
