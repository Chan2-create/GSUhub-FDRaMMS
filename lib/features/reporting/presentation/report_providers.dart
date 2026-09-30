import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/damage_categories.dart';
import '../../../core/di/repository_providers.dart';
import '../../../core/enums/priority_level.dart';
import '../../../core/enums/report_status.dart';
import '../../../core/utils/result.dart';
import '../../work_orders/data/models/work_order.dart';
import '../../work_orders/presentation/work_order_providers.dart';
import '../data/models/damage_report.dart';

/// Live feed of every report that is not a merged duplicate.
///
/// The single query behind the dashboard, the reports table and the
/// assignment queue. Firestore cannot filter on "official priority if set,
/// otherwise the requestor's", and paging server-side would need a cursor
/// per filter combination, so the screens narrow this list in memory. At
/// campus scale — one university's facility reports — that is a few
/// hundred documents, and one listener beats four disagreeing ones.
final reportsStreamProvider = StreamProvider<Result<List<DamageReport>>>(
  (ref) => ref.watch(damageReportRepositoryProvider).watchAll(),
);

/// One report, watched live so a review decision updates the detail view
/// without a refetch.
final reportByIdProvider = StreamProvider.family<Result<DamageReport>, String>(
  (ref, reportId) =>
      ref.watch(damageReportRepositoryProvider).watchById(reportId),
);

/// What the Damage Reports table is currently showing.
class ReportsView {
  const ReportsView({this.category, this.priority, this.status, this.page = 0});

  final DamageCategory? category;
  final PriorityLevel? priority;
  final ReportStatus? status;

  /// Zero-based page index.
  final int page;

  static const int pageSize = 10;

  bool get hasFilters => category != null || priority != null || status != null;

  /// Whether [report] survives the current filters.
  bool matches(DamageReport report) {
    if (category != null && report.category != category) return false;
    if (priority != null && report.effectivePriority != priority) return false;
    if (status != null && report.status != status) return false;
    return true;
  }
}

/// Filters and page for the reports table, held together so that changing
/// a filter always returns to the first page — a filtered list of three
/// results while sitting on page four would otherwise look empty.
class ReportsViewController extends Notifier<ReportsView> {
  @override
  ReportsView build() => const ReportsView();

  void setCategory(DamageCategory? category) => state = ReportsView(
    category: category,
    priority: state.priority,
    status: state.status,
  );

  void setPriority(PriorityLevel? priority) => state = ReportsView(
    category: state.category,
    priority: priority,
    status: state.status,
  );

  void setStatus(ReportStatus? status) => state = ReportsView(
    category: state.category,
    priority: state.priority,
    status: status,
  );

  void clearFilters() => state = const ReportsView();

  void setPage(int page) => state = ReportsView(
    category: state.category,
    priority: state.priority,
    status: state.status,
    page: page,
  );
}

final reportsViewProvider =
    NotifierProvider<ReportsViewController, ReportsView>(
      ReportsViewController.new,
    );

/// Reports matching the current filters, newest first.
final filteredReportsProvider =
    Provider<AsyncValue<Result<List<DamageReport>>>>((ref) {
      final view = ref.watch(reportsViewProvider);
      return ref
          .watch(reportsStreamProvider)
          .whenData(
            (result) => result.map(
              (reports) => reports.where(view.matches).toList(growable: false),
            ),
          );
    });

/// The current page of [filteredReportsProvider].
final reportsPageProvider = Provider<AsyncValue<Result<List<DamageReport>>>>((
  ref,
) {
  final view = ref.watch(reportsViewProvider);
  return ref
      .watch(filteredReportsProvider)
      .whenData(
        (result) => result.map((reports) {
          final start = view.page * ReportsView.pageSize;
          if (start >= reports.length) return const <DamageReport>[];
          final end = (start + ReportsView.pageSize).clamp(0, reports.length);
          return reports.sublist(start, end);
        }),
      );
});

/// Reports awaiting assignment: approved, not yet tied to a work order.
final unassignedReportsProvider =
    Provider<AsyncValue<Result<List<DamageReport>>>>(
      (ref) => ref
          .watch(reportsStreamProvider)
          .whenData(
            (result) => result.map(
              (reports) => reports
                  .where((report) => report.awaitsAssignment)
                  .toList(growable: false),
            ),
          ),
    );

/// The four numbers above the reports table.
class ReportStats {
  const ReportStats({
    required this.totalOpen,
    required this.highPriority,
    required this.completedToday,
    this.averageResponse,
  });

  factory ReportStats._compute(
    List<DamageReport> reports,
    List<WorkOrder> workOrders,
    int totalOpen,
    int highPriority,
  ) {
    final now = DateTime.now();
    final windowStart = now.toUtc().subtract(responseWindow);
    final submittedAt = {
      for (final report in reports) report.id: report.submittedAt,
    };

    final responseTimes = <Duration>[];
    final completedToday = <String>{};

    for (final workOrder in workOrders) {
      if (!workOrder.createdAt.isBefore(windowStart)) {
        for (final reportId in workOrder.reportIds) {
          final submitted = submittedAt[reportId];
          // Guard against a clock skew that would make a work order look
          // as though it preceded the report it came from.
          if (submitted != null && !workOrder.createdAt.isBefore(submitted)) {
            responseTimes.add(workOrder.createdAt.difference(submitted));
          }
        }
      }

      final completedAt = workOrder.completedAt?.toLocal();
      if (completedAt != null && _isSameDay(completedAt, now)) {
        completedToday.addAll(workOrder.reportIds);
      }
    }

    return ReportStats(
      totalOpen: totalOpen,
      highPriority: highPriority,
      completedToday: completedToday.length,
      averageResponse: responseTimes.isEmpty
          ? null
          : Duration(
              microseconds:
                  responseTimes
                      .map((duration) => duration.inMicroseconds)
                      .reduce((a, b) => a + b) ~/
                  responseTimes.length,
            ),
    );
  }

  /// [workOrders] is null when the work-order feed failed or is still
  /// loading. The counts drawn from reports alone stay true; the two that
  /// need work orders report unknown rather than zero.
  factory ReportStats.from({
    required List<DamageReport> reports,
    required List<WorkOrder>? workOrders,
  }) {
    final open = reports.where((report) => report.status.isOpen);
    final highPriority = open
        .where((report) => report.effectivePriority.isHighOrAbove)
        .length;

    if (workOrders == null) {
      return ReportStats(
        totalOpen: open.length,
        highPriority: highPriority,
        completedToday: null,
      );
    }
    return ReportStats._compute(reports, workOrders, open.length, highPriority);
  }

  /// Everything still in the administrator's hands or being worked.
  final int totalOpen;

  /// Open reports whose effective priority is high or critical.
  final int highPriority;

  /// Reports whose work order was completed today. Null when the work
  /// orders could not be read — "we do not know" is not "none".
  final int? completedToday;

  /// Mean time from submission to work-order creation. Null when no
  /// report was assigned in the window — "no data yet" is not zero hours.
  final Duration? averageResponse;

  static const Duration responseWindow = Duration(days: 30);

  static const String responseDefinition =
      'Average time from a report being submitted to a work order being '
      'raised for it, over reports assigned in the last 30 days.';

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

final reportStatsProvider = Provider<AsyncValue<Result<ReportStats>>>((ref) {
  final workOrders = ref
      .watch(workOrdersStreamProvider)
      .value
      ?.fold((list) => list, (_) => null);

  return ref
      .watch(reportsStreamProvider)
      .whenData(
        (result) => result.map(
          (reports) =>
              ReportStats.from(reports: reports, workOrders: workOrders),
        ),
      );
});

/// "4.2h" — the compact form the stat card shows.
String formatResponseTime(Duration? duration) {
  if (duration == null) return '—';
  if (duration.inMinutes < 60) return '${duration.inMinutes}m';
  if (duration.inHours < 48) {
    return '${(duration.inMinutes / 60).toStringAsFixed(1)}h';
  }
  return '${(duration.inHours / 24).toStringAsFixed(1)}d';
}
