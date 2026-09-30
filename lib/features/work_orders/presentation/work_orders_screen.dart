import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/enums/work_order_status.dart';
import '../../../core/utils/display_id.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/priority_chip.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/status_chip.dart';
import '../../user_management/presentation/personnel_providers.dart';
import '../data/models/work_order.dart';
import 'widgets/kanban_board.dart';
import 'widgets/work_order_filter_bar.dart';
import 'work_order_providers.dart';

/// Work Order Management (Figma node `202:5355`, content area only).
class WorkOrdersScreen extends ConsumerWidget {
  const WorkOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      const SingleChildScrollView(
        padding: EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Work Order Management', style: AppTextStyles.pageTitle),
            SizedBox(height: 4),
            Text(
              'Track and manage all maintenance tasks and staff assignments.',
              style: AppTextStyles.pageSubtitle,
            ),
            SizedBox(height: 24),
            _StatRow(),
            SizedBox(height: 24),
            WorkOrderFilterBar(),
            SizedBox(height: 24),
            _Body(),
          ],
        ),
      );
}

class _StatRow extends ConsumerWidget {
  const _StatRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(workOrderStatsProvider);
    final resolved = stats.value?.fold((data) => data, (_) => null);
    final isLoading = stats.isLoading;
    final hasError = stats.hasError || (stats.value?.isFailure ?? false);

    // The design's corner annotations ("This Month", "+12% last wk",
    // "Target: 25") are omitted: no data source defines a target or a
    // week-on-week comparison, and inventing one would be worse than
    // leaving it out.
    final cards = <Widget>[
      StatCard(
        label: 'TOTAL ORDERS',
        value: resolved?.total,
        accent: AppColors.statAccentTotal,
        definition: 'Every work order ever raised.',
        isLoading: isLoading,
        hasError: hasError,
      ),
      StatCard(
        label: 'IN PROGRESS',
        value: resolved?.inProgress,
        accent: AppColors.statAccentInProgress,
        definition: 'Work orders personnel are actively working.',
        isLoading: isLoading,
        hasError: hasError,
      ),
      StatCard(
        label: 'OVERDUE',
        value: resolved?.overdue,
        accent: AppColors.statAccentNeedsReview,
        definition: WorkOrderStats.overdueDefinition,
        isLoading: isLoading,
        hasError: hasError,
      ),
      StatCard(
        label: 'COMPLETED TODAY',
        value: resolved?.completedToday,
        accent: AppColors.statAccentCompleted,
        definition: 'Work orders completed since midnight.',
        isLoading: isLoading,
        hasError: hasError,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000 ? 4 : 2;
        const gap = 16.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(workOrderViewModeProvider);
    final filters = ref.watch(appliedWorkOrderFiltersProvider);

    const emptyMessage = 'No work orders match these filters.';
    const noneYet =
        'No work orders yet. They are raised by assigning an approved '
        'report on the Task Assignment screen.';

    if (mode == WorkOrderViewMode.kanban) {
      return AsyncValueView<Map<WorkOrderStatus, List<WorkOrder>>>(
        value: ref.watch(kanbanColumnsProvider),
        isEmpty: (columns) => columns.values.every((column) => column.isEmpty),
        emptyIcon: Icons.view_kanban_outlined,
        emptyMessage: filters.status != null || filters.search.isNotEmpty
            ? emptyMessage
            : noneYet,
        onRetry: () => ref.invalidate(workOrdersStreamProvider),
        data: (columns) => KanbanBoard(columns: columns),
      );
    }

    return AsyncValueView<List<WorkOrder>>(
      value: ref.watch(filteredWorkOrdersProvider),
      isEmpty: (workOrders) => workOrders.isEmpty,
      emptyIcon: Icons.assignment_outlined,
      emptyMessage: filters.status != null || filters.search.isNotEmpty
          ? emptyMessage
          : noneYet,
      onRetry: () => ref.invalidate(workOrdersStreamProvider),
      data: (workOrders) => _WorkOrderTable(workOrders: workOrders),
    );
  }
}

class _WorkOrderTable extends ConsumerWidget {
  const _WorkOrderTable({required this.workOrders});

  final List<WorkOrder> workOrders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(personnelNamesProvider);
    final dateFormat = DateFormat('MMM d, y');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderStrong),
        borderRadius: BorderRadius.circular(8),
      ),
      child: AppDataTable<WorkOrder>(
        rows: workOrders,
        columns: [
          AppTableColumn(
            label: 'Work Order',
            width: 140,
            cell: (workOrder) => Text(
              DisplayId.workOrder(workOrder.id),
              style: AppTextStyles.workOrderId,
            ),
          ),
          AppTableColumn(
            label: 'Title',
            flex: 2,
            cell: (workOrder) =>
                Text(workOrder.title, style: AppTextStyles.tableCellStrong),
          ),
          AppTableColumn(
            label: 'Location',
            cell: (workOrder) => Text(
              workOrder.facilityName ?? '—',
              style: AppTextStyles.tableCell,
            ),
          ),
          AppTableColumn(
            label: 'Assignee',
            cell: (workOrder) {
              final assignees = workOrder.assignedPersonnelIds
                  .map((id) => names[id])
                  .whereType<String>()
                  .join(', ');
              return Text(
                assignees.isEmpty ? 'Unassigned' : assignees,
                style: AppTextStyles.tableCell,
              );
            },
          ),
          AppTableColumn(
            label: 'Priority',
            width: 130,
            cell: (workOrder) => PriorityChip(level: workOrder.priority),
          ),
          AppTableColumn(
            label: 'Status',
            width: 150,
            cell: (workOrder) => StatusChip.workOrder(workOrder.status),
          ),
          AppTableColumn(
            label: 'Created',
            width: 130,
            cell: (workOrder) => Text(
              dateFormat.format(workOrder.createdAt.toLocal()),
              style: AppTextStyles.tableCell,
            ),
          ),
        ],
      ),
    );
  }
}
