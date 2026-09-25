import '../../../core/constants/damage_categories.dart';
import '../../../core/enums/date_range_filter.dart';
import '../../../core/enums/report_status.dart';
import '../../../core/enums/work_order_status.dart';
import '../../../core/widgets/category_donut.dart';
import '../../reporting/data/models/damage_report.dart';
import '../../work_orders/data/models/work_order.dart';

/// One month's bar or point on the Analytics trend charts.
class MonthlyValue<T> {
  const MonthlyValue({required this.month, required this.value});

  /// The first day of the month, local time.
  final DateTime month;
  final T value;
}

/// One bar in "Reports by Building".
class BuildingCount {
  const BuildingCount({required this.facilityName, required this.count});

  final String facilityName;
  final int count;
}

/// Which way a group's report count moved against last month.
enum IssueTrend { up, flat, down }

/// One row of "Top Reported Issues This Month": a kind of damage at one
/// building.
class TopIssue {
  const TopIssue({
    required this.category,
    required this.facilityName,
    required this.count,
    required this.averageResolutionDays,
    required this.trend,
  });

  /// Null for reports not yet classified.
  final DamageCategory? category;
  final String facilityName;
  final int count;

  /// Mean days from report to completed work, over this group's completed
  /// work orders. Null when none has been completed.
  final double? averageResolutionDays;
  final IssueTrend trend;
}

/// Everything the Analytics screen shows, computed from the live report and
/// work-order feeds (Objective 2.C).
///
/// Computed client-side for the same reason as the 2.B screens: at one
/// university's volume this is a few hundred documents, one listener each,
/// and every figure stays consistent with the tables elsewhere. The
/// definitions below are what the cards' tooltips say, so each number can
/// be defended.
class AnalyticsSummary {
  const AnalyticsSummary({
    required this.range,
    required this.totalReports,
    required this.totalReportsPrevious,
    required this.averageResolutionDays,
    required this.averageResolutionDaysPrevious,
    required this.completionRate,
    required this.completionRatePrevious,
    required this.pendingOrOverdue,
    required this.pendingOrOverduePrevious,
    required this.monthlyVolume,
    required this.byCategory,
    required this.byBuilding,
    required this.resolutionByMonth,
    required this.topIssues,
  });

  factory AnalyticsSummary.compute({
    required List<DamageReport> reports,
    required List<WorkOrder> workOrders,
    required DateFilterContext context,
  }) {
    final range = context.range;
    final now = context.now;

    final submittedAt = {
      for (final report in reports) report.id: report.submittedAt,
    };

    bool inRange(DateTime moment) => range.includes(moment, now);
    bool inPrevious(DateTime moment) => range.includesPrevious(moment, now);

    final current = reports.where((r) => inRange(r.submittedAt)).toList();
    final previous = range.hasPreviousPeriod
        ? reports.where((r) => inPrevious(r.submittedAt)).toList()
        : null;

    final completedNow = workOrders.where(
      (w) => w.completedAt != null && inRange(w.completedAt!),
    );
    final completedBefore = range.hasPreviousPeriod
        ? workOrders.where(
            (w) => w.completedAt != null && inPrevious(w.completedAt!),
          )
        : null;

    final start = range.startOf(now);

    return AnalyticsSummary(
      range: range,
      totalReports: current.length,
      totalReportsPrevious: previous?.length,
      averageResolutionDays: _averageDays(completedNow, submittedAt),
      averageResolutionDaysPrevious: completedBefore == null
          ? null
          : _averageDays(completedBefore, submittedAt),
      completionRate: _completionRate(current),
      completionRatePrevious: previous == null
          ? null
          : _completionRate(previous),
      pendingOrOverdue: _pendingOrOverdueAt(now, reports, workOrders),
      pendingOrOverduePrevious: start == null
          ? null
          : _pendingOrOverdueAt(start, reports, workOrders),
      monthlyVolume: _monthlyVolume(reports, now),
      byCategory: _byCategory(current),
      byBuilding: _byBuilding(current),
      resolutionByMonth: _resolutionByMonth(workOrders, submittedAt, now),
      topIssues: _topIssues(reports, workOrders, submittedAt, now),
    );
  }

  final DateRangeFilter range;

  final int totalReports;

  /// Null when [range] has no preceding period ("All Time").
  final int? totalReportsPrevious;

  final double? averageResolutionDays;
  final double? averageResolutionDaysPrevious;

  /// 0.0–1.0, or null when no report in the period can count.
  final double? completionRate;
  final double? completionRatePrevious;

  final int pendingOrOverdue;

  /// The same count as it stood when the period began.
  final int? pendingOrOverduePrevious;

  /// Reports per calendar month, the last six, oldest first.
  final List<MonthlyValue<int>> monthlyVolume;
  final List<CategorySlice> byCategory;

  /// The five busiest locations, busiest first.
  final List<BuildingCount> byBuilding;

  /// Mean resolution days per calendar month, the last six, oldest first;
  /// null for a month in which nothing was completed.
  final List<MonthlyValue<double?>> resolutionByMonth;
  final List<TopIssue> topIssues;

  // --- definitions, as the tooltips state them ---

  static const String totalReportsDefinition =
      'Reports submitted in the selected period, merged duplicates excluded. '
      'The change is against the period of equal length before it.';

  static const String resolutionDefinition =
      'Average days from a report being submitted to its work order being '
      'completed, over work completed in the selected period.';

  static const String completionDefinition =
      'Of the reports submitted in the selected period, the share whose work '
      'is completed or closed. Rejected and archived reports are left out: '
      'they were dismissed, not left undone.';

  static const String pendingDefinition =
      'Reports still awaiting a review decision, plus work orders past their '
      'target completion date. The change is against the count when the '
      'period began.';

  /// How many months the trend charts span — the design's NOV–APR.
  static const int trendMonths = 6;

  /// How many buildings and issues the ranked lists show.
  static const int rankedRows = 5;

  // --- computations ---

  /// Days from report to completion. A work order raised from several
  /// merged reports is measured from the earliest of them; one whose
  /// report is gone is measured from its own creation.
  static double? _resolutionDays(
    WorkOrder workOrder,
    Map<String, DateTime> submittedAt,
  ) {
    final completed = workOrder.completedAt;
    if (completed == null) return null;

    DateTime? from;
    for (final id in workOrder.reportIds) {
      final submitted = submittedAt[id];
      if (submitted != null && (from == null || submitted.isBefore(from))) {
        from = submitted;
      }
    }
    from ??= workOrder.createdAt;
    if (completed.isBefore(from)) return null;
    return completed.difference(from).inMinutes / Duration.minutesPerDay;
  }

  static double? _averageDays(
    Iterable<WorkOrder> completed,
    Map<String, DateTime> submittedAt,
  ) {
    final days = [
      for (final workOrder in completed)
        ?_resolutionDays(workOrder, submittedAt),
    ];
    if (days.isEmpty) return null;
    return days.reduce((a, b) => a + b) / days.length;
  }

  static double? _completionRate(List<DamageReport> reports) {
    final counted = reports.where(
      (r) =>
          r.status != ReportStatus.rejected &&
          r.status != ReportStatus.archived,
    );
    if (counted.isEmpty) return null;
    final done = counted.where(
      (r) =>
          r.status == ReportStatus.completed || r.status == ReportStatus.closed,
    );
    return done.length / counted.length;
  }

  /// Awaiting review at [moment]: submitted by then and not yet decided.
  /// A decision stamps `reviewedAt`, which is how the count at the start of
  /// a period is recovered without a history table.
  static int _pendingOrOverdueAt(
    DateTime moment,
    List<DamageReport> reports,
    List<WorkOrder> workOrders,
  ) {
    var count = 0;
    for (final report in reports) {
      if (report.submittedAt.isAfter(moment)) continue;
      final reviewed = report.reviewedAt;
      final awaiting = reviewed == null
          ? report.status == ReportStatus.submitted ||
                report.status == ReportStatus.underReview
          : reviewed.isAfter(moment);
      if (awaiting) count++;
    }
    for (final workOrder in workOrders) {
      if (workOrder.isOverdueAt(moment)) count++;
    }
    return count;
  }

  static List<DateTime> _lastMonths(DateTime now) {
    final local = now.toLocal();
    return [
      for (var i = trendMonths - 1; i >= 0; i--)
        DateTime(local.year, local.month - i),
    ];
  }

  static bool _sameMonth(DateTime moment, DateTime month) {
    final local = moment.toLocal();
    return local.year == month.year && local.month == month.month;
  }

  static List<MonthlyValue<int>> _monthlyVolume(
    List<DamageReport> reports,
    DateTime now,
  ) => [
    for (final month in _lastMonths(now))
      MonthlyValue(
        month: month,
        value: reports.where((r) => _sameMonth(r.submittedAt, month)).length,
      ),
  ];

  static List<CategorySlice> _byCategory(List<DamageReport> reports) {
    if (reports.isEmpty) return const [];
    final counts = <String, int>{};
    for (final report in reports) {
      final label = report.category?.label ?? 'Unclassified';
      counts[label] = (counts[label] ?? 0) + 1;
    }
    final ordered = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final entry in ordered)
        CategorySlice(
          label: entry.key,
          count: entry.value,
          share: entry.value / reports.length,
        ),
    ];
  }

  static String _locationOf(DamageReport report) =>
      report.facilityName ?? 'Unspecified location';

  static List<BuildingCount> _byBuilding(List<DamageReport> reports) {
    final counts = <String, int>{};
    for (final report in reports) {
      final name = _locationOf(report);
      counts[name] = (counts[name] ?? 0) + 1;
    }
    final ordered = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return [
      for (final entry in ordered.take(rankedRows))
        BuildingCount(facilityName: entry.key, count: entry.value),
    ];
  }

  static List<MonthlyValue<double?>> _resolutionByMonth(
    List<WorkOrder> workOrders,
    Map<String, DateTime> submittedAt,
    DateTime now,
  ) => [
    for (final month in _lastMonths(now))
      MonthlyValue(
        month: month,
        value: _averageDays(
          workOrders.where(
            (w) =>
                w.status == WorkOrderStatus.completed &&
                w.completedAt != null &&
                _sameMonth(w.completedAt!, month),
          ),
          submittedAt,
        ),
      ),
  ];

  /// This calendar month's reports, grouped by kind of damage and
  /// building, busiest first; trend against the same group last month.
  static List<TopIssue> _topIssues(
    List<DamageReport> reports,
    List<WorkOrder> workOrders,
    Map<String, DateTime> submittedAt,
    DateTime now,
  ) {
    final local = now.toLocal();
    final thisMonth = DateTime(local.year, local.month);
    final lastMonth = DateTime(local.year, local.month - 1);

    String keyOf(DamageReport r) => '${r.category?.id}|${_locationOf(r)}';

    final groups = <String, List<DamageReport>>{};
    final lastMonthCounts = <String, int>{};
    for (final report in reports) {
      if (_sameMonth(report.submittedAt, thisMonth)) {
        (groups[keyOf(report)] ??= []).add(report);
      } else if (_sameMonth(report.submittedAt, lastMonth)) {
        lastMonthCounts[keyOf(report)] =
            (lastMonthCounts[keyOf(report)] ?? 0) + 1;
      }
    }

    final workOrderById = {for (final w in workOrders) w.id: w};

    TopIssue toIssue(String key, List<DamageReport> group) {
      final completed = {
        for (final report in group)
          if (report.workOrderId case final id?)
            if (workOrderById[id] case final workOrder?)
              if (workOrder.completedAt != null) workOrder,
      };
      final previous = lastMonthCounts[key] ?? 0;
      return TopIssue(
        category: group.first.category,
        facilityName: _locationOf(group.first),
        count: group.length,
        averageResolutionDays: _averageDays(completed, submittedAt),
        trend: group.length > previous
            ? IssueTrend.up
            : group.length < previous
            ? IssueTrend.down
            : IssueTrend.flat,
      );
    }

    final issues =
        [for (final entry in groups.entries) toIssue(entry.key, entry.value)]
          ..sort((a, b) {
            final byCount = b.count.compareTo(a.count);
            return byCount != 0
                ? byCount
                : a.facilityName.compareTo(b.facilityName);
          });

    return issues.take(rankedRows).toList();
  }
}

/// The period an [AnalyticsSummary] is computed over, and the moment it is
/// computed at — passed in rather than read from the clock, so the
/// computation is a pure function a test can pin.
class DateFilterContext {
  const DateFilterContext({required this.range, required this.now});

  final DateRangeFilter range;
  final DateTime now;
}
