import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/enums/priority_level.dart';
import '../../../../core/enums/work_order_status.dart';
import '../../../../core/widgets/filter_select.dart';
import '../work_order_providers.dart';

/// Search, status, priority, date range, Apply, and the Table/Kanban
/// toggle (Figma `234:650`).
class WorkOrderFilterBar extends ConsumerStatefulWidget {
  const WorkOrderFilterBar({super.key});

  @override
  ConsumerState<WorkOrderFilterBar> createState() => _WorkOrderFilterBarState();
}

class _WorkOrderFilterBarState extends ConsumerState<WorkOrderFilterBar> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(workOrderFilterDraftProvider);
    final draftController = ref.read(workOrderFilterDraftProvider.notifier);
    final mode = ref.watch(workOrderViewModeProvider);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        border: Border.all(color: AppColors.borderStrong),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(17),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 16,
        children: [
          SizedBox(
            width: 320,
            child: TextField(
              controller: _searchController,
              onChanged: draftController.setSearch,
              onSubmitted: (_) => _apply(),
              style: AppTextStyles.inputText,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'ID, Staff, or Location...',
                hintStyle: AppTextStyles.inputText.copyWith(
                  color: AppColors.textMuted,
                ),
                filled: true,
                fillColor: AppColors.surface,
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(10),
                  child: SvgPicture.asset(
                    'assets/icons/search.svg',
                    width: 18,
                    height: 18,
                    colorFilter: const ColorFilter.mode(
                      AppColors.textSecondary,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 38,
                  minHeight: 38,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.borderStrong),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.borderStrong),
                ),
              ),
            ),
          ),
          FilterSelect<WorkOrderStatus>(
            placeholder: 'All Statuses',
            dense: true,
            width: 160,
            value: draft.status,
            onChanged: draftController.setStatus,
            options: [
              const FilterOption(value: null, label: 'All Statuses'),
              for (final status in WorkOrderStatus.values)
                FilterOption(value: status, label: status.title),
            ],
          ),
          FilterSelect<PriorityLevel>(
            placeholder: 'All Priorities',
            dense: true,
            width: 160,
            value: draft.priority,
            onChanged: draftController.setPriority,
            options: [
              const FilterOption(value: null, label: 'All Priorities'),
              for (final level in PriorityLevel.values)
                FilterOption(value: level, label: level.label),
            ],
          ),
          _DateRangeSelect(
            value: draft.dateRange,
            onChanged: draftController.setDateRange,
          ),
          FilledButton(
            onPressed: _apply,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textOnDark,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Apply', style: AppTextStyles.buttonLabel),
          ),
          _ViewToggle(
            mode: mode,
            onChanged: ref.read(workOrderViewModeProvider.notifier).set,
          ),
        ],
      ),
    );
  }

  void _apply() => ref
      .read(appliedWorkOrderFiltersProvider.notifier)
      .apply(ref.read(workOrderFilterDraftProvider));
}

class _DateRangeSelect extends StatelessWidget {
  const _DateRangeSelect({required this.value, required this.onChanged});

  final WorkOrderDateRange value;
  final ValueChanged<WorkOrderDateRange> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<WorkOrderDateRange>(
    tooltip: 'Date range',
    position: PopupMenuPosition.under,
    initialValue: value,
    onSelected: onChanged,
    itemBuilder: (context) => [
      for (final range in WorkOrderDateRange.values)
        PopupMenuItem(value: range, child: Text(range.label)),
    ],
    child: Container(
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderStrong),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(child: Text(value.label, style: AppTextStyles.inputText)),
          SvgPicture.asset(
            'assets/icons/date_range.svg',
            width: 18,
            height: 20,
            colorFilter: const ColorFilter.mode(
              AppColors.textSecondary,
              BlendMode.srcIn,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.mode, required this.onChanged});

  final WorkOrderViewMode mode;
  final ValueChanged<WorkOrderViewMode> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surfaceControl,
      border: Border.all(color: AppColors.borderStrong),
      borderRadius: BorderRadius.circular(8),
    ),
    padding: const EdgeInsets.all(5),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ToggleButton(
          label: 'Table',
          asset: 'assets/icons/view_table.svg',
          selected: mode == WorkOrderViewMode.table,
          onPressed: () => onChanged(WorkOrderViewMode.table),
        ),
        _ToggleButton(
          label: 'Kanban',
          asset: 'assets/icons/view_kanban.svg',
          selected: mode == WorkOrderViewMode.kanban,
          onPressed: () => onChanged(WorkOrderViewMode.kanban),
        ),
      ],
    ),
  );
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.label,
    required this.asset,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final String asset;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? AppColors.accentOlive
        : AppColors.textSecondary;

    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.highlightAmber : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(
                asset,
                width: 13.5,
                height: 13.5,
                colorFilter: ColorFilter.mode(foreground, BlendMode.srcIn),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTextStyles.buttonLabel.copyWith(
                  color: foreground,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
