import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/repository_providers.dart';
import '../../../core/enums/date_range_filter.dart';
import '../../../core/enums/priority_level.dart';
import '../../../core/enums/work_order_status.dart';
import '../../../core/utils/result.dart';
import '../../user_management/presentation/personnel_providers.dart';
import '../data/models/work_order.dart';

/// Live feed of every work order, newest first.
final workOrdersStreamProvider = StreamProvider<Result<List<WorkOrder>>>(
  (ref) => ref.watch(workOrderRepositoryProvider).watchAll(),
);

/// The work-order filter bar's state.
///
/// The design puts an explicit **Apply** button on this bar, so a draft is
/// edited and only committed on press — unlike the reports filters, which
/// take effect immediately. Both are what their screen draws.
class WorkOrderFilters {
  const WorkOrderFilters({
    this.search = '',
    this.status,
    this.priority,
    this.dateRange = DateRangeFilter.last30,
  });

  final String search;
  final WorkOrderStatus? status;
  final PriorityLevel? priority;
  final DateRangeFilter dateRange;

  WorkOrderFilters copyWith({
    String? search,
    WorkOrderStatus? status,
    PriorityLevel? priority,
    DateRangeFilter? dateRange,
    bool clearStatus = false,
    bool clearPriority = false,
  }) => WorkOrderFilters(
    search: search ?? this.search,
    status: clearStatus ? null : (status ?? this.status),
    priority: clearPriority ? null : (priority ?? this.priority),
    dateRange: dateRange ?? this.dateRange,
  );

  bool matches(WorkOrder workOrder, {required Map<String, String> assignees}) {
    if (status != null && workOrder.status != status) return false;
    if (priority != null && workOrder.priority != priority) return false;
    if (!dateRange.includes(workOrder.createdAt, DateTime.now().toUtc())) {
      return false;
    }

    final term = search.trim().toLowerCase();
    if (term.isEmpty) return true;

    // "ID, Staff, or Location", as the search box says.
    final staff = workOrder.assignedPersonnelIds
        .map((id) => assignees[id] ?? '')
        .join(' ');
    final haystack = [
      workOrder.id,
      workOrder.title,
      workOrder.facilityName ?? '',
      staff,
    ].join(' ').toLowerCase();
    return haystack.contains(term);
  }
}

/// The filters being edited, before Apply.
class WorkOrderFilterDraft extends Notifier<WorkOrderFilters> {
  @override
  WorkOrderFilters build() => const WorkOrderFilters();

  void setSearch(String value) => state = state.copyWith(search: value);

  void setStatus(WorkOrderStatus? value) =>
      state = state.copyWith(status: value, clearStatus: value == null);

  void setPriority(PriorityLevel? value) =>
      state = state.copyWith(priority: value, clearPriority: value == null);

  void setDateRange(DateRangeFilter value) =>
      state = state.copyWith(dateRange: value);
}

final workOrderFilterDraftProvider =
    NotifierProvider<WorkOrderFilterDraft, WorkOrderFilters>(
      WorkOrderFilterDraft.new,
    );

/// The filters actually in force.
class AppliedWorkOrderFilters extends Notifier<WorkOrderFilters> {
  @override
  WorkOrderFilters build() => const WorkOrderFilters();

  void apply(WorkOrderFilters filters) => state = filters;
}

final appliedWorkOrderFiltersProvider =
    NotifierProvider<AppliedWorkOrderFilters, WorkOrderFilters>(
      AppliedWorkOrderFilters.new,
    );

enum WorkOrderViewMode { table, kanban }

class WorkOrderViewModeController extends Notifier<WorkOrderViewMode> {
  @override
  // The design shows Kanban selected.
  WorkOrderViewMode build() => WorkOrderViewMode.kanban;

  void set(WorkOrderViewMode mode) => state = mode;
}

final workOrderViewModeProvider =
    NotifierProvider<WorkOrderViewModeController, WorkOrderViewMode>(
      WorkOrderViewModeController.new,
    );

/// Work orders passing the applied filters.
final filteredWorkOrdersProvider =
    Provider<AsyncValue<Result<List<WorkOrder>>>>((ref) {
      final filters = ref.watch(appliedWorkOrderFiltersProvider);
      final assignees = ref.watch(personnelNamesProvider);

      return ref
          .watch(workOrdersStreamProvider)
          .whenData(
            (result) => result.map(
              (workOrders) => workOrders
                  .where(
                    (workOrder) =>
                        filters.matches(workOrder, assignees: assignees),
                  )
                  .toList(growable: false),
            ),
          );
    });

/// Filtered work orders grouped into the four Kanban columns.
final kanbanColumnsProvider =
    Provider<AsyncValue<Result<Map<WorkOrderStatus, List<WorkOrder>>>>>(
      (ref) => ref
          .watch(filteredWorkOrdersProvider)
          .whenData(
            (result) => result.map((workOrders) {
              final columns = {
                for (final status in WorkOrderStatus.values)
                  status: <WorkOrder>[],
              };
              for (final workOrder in workOrders) {
                columns[workOrder.status]!.add(workOrder);
              }
              return columns;
            }),
          ),
    );

/// The four numbers above the board.
class WorkOrderStats {
  const WorkOrderStats({
    required this.total,
    required this.inProgress,
    required this.overdue,
    required this.completedToday,
  });

  factory WorkOrderStats.from(List<WorkOrder> workOrders) {
    final now = DateTime.now();
    var inProgress = 0;
    var overdue = 0;
    var completedToday = 0;

    for (final workOrder in workOrders) {
      if (workOrder.status == WorkOrderStatus.inProgress) inProgress++;

      if (workOrder.isOverdueAt(now)) overdue++;

      final completedAt = workOrder.completedAt?.toLocal();
      if (completedAt != null &&
          completedAt.year == now.year &&
          completedAt.month == now.month &&
          completedAt.day == now.day) {
        completedToday++;
      }
    }

    return WorkOrderStats(
      total: workOrders.length,
      inProgress: inProgress,
      overdue: overdue,
      completedToday: completedToday,
    );
  }

  final int total;
  final int inProgress;

  /// Past its target completion date and not finished.
  final int overdue;
  final int completedToday;

  static const String overdueDefinition =
      'Work orders whose target completion date has passed and which are '
      'not yet completed. A target date is optional when assigning.';
}

/// Counted over every work order, not the filtered set: a summary that
/// moved with the filters would answer a different question each time.
final workOrderStatsProvider = Provider<AsyncValue<Result<WorkOrderStats>>>(
  (ref) => ref
      .watch(workOrdersStreamProvider)
      .whenData((result) => result.map(WorkOrderStats.from)),
);
