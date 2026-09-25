import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/enums/date_range_filter.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/features/analytics/presentation/analytics_summary.dart';
import 'package:gsuhub/features/reporting/data/models/damage_report.dart';
import 'package:gsuhub/features/work_orders/data/models/work_order.dart';

/// The Analytics figures, each against its stated definition, at a pinned
/// "now" so the periods do not drift with the calendar.
void main() {
  // Local time throughout: months are bucketed in the campus's time zone.
  final now = DateTime(2026, 9, 25, 12);
  DateTime daysAgo(num days) =>
      now.subtract(Duration(minutes: (days * Duration.minutesPerDay).round()));

  DamageReport report(
    String id, {
    required DateTime submitted,
    ReportStatus status = ReportStatus.completed,
    DamageCategory? category = DamageCategory.electrical,
    String? facility = 'Engineering Building',
    DateTime? reviewed,
    String? workOrderId,
  }) => DamageReport(
    id: id,
    reporterId: 'faculty-1',
    reporterName: 'Maria Santos',
    title: 'Damage $id',
    description: 'Seeded for test.',
    requestorPriority: PriorityLevel.medium,
    status: status,
    category: category,
    facilityName: facility,
    reviewedAt: reviewed,
    workOrderId: workOrderId,
    submittedAt: submitted,
    updatedAt: submitted,
  );

  WorkOrder workOrder(
    String id, {
    required List<String> reportIds,
    required DateTime created,
    DateTime? completed,
    DateTime? scheduled,
    WorkOrderStatus? status,
  }) => WorkOrder(
    id: id,
    reportIds: reportIds,
    title: 'Repair $id',
    description: 'Seeded for test.',
    category: DamageCategory.electrical,
    priority: PriorityLevel.medium,
    status:
        status ??
        (completed == null
            ? WorkOrderStatus.pending
            : WorkOrderStatus.completed),
    assignedPersonnelIds: const ['p1'],
    scheduledFor: scheduled,
    completedAt: completed,
    createdBy: 'admin-1',
    createdAt: created,
    updatedAt: completed ?? created,
  );

  AnalyticsSummary compute(
    List<DamageReport> reports,
    List<WorkOrder> workOrders, {
    DateRangeFilter range = DateRangeFilter.last30,
  }) => AnalyticsSummary.compute(
    reports: reports,
    workOrders: workOrders,
    context: DateFilterContext(range: range, now: now),
  );

  group('total reports', () {
    test('counts the period and the one before it', () {
      final summary = compute([
        report('a', submitted: daysAgo(2)),
        report('b', submitted: daysAgo(29)),
        report('c', submitted: daysAgo(31)),
        report('d', submitted: daysAgo(61)),
      ], []);

      expect(summary.totalReports, 2);
      expect(summary.totalReportsPrevious, 1);
    });

    test('All Time has nothing before it to compare', () {
      final summary = compute(
        [report('a', submitted: daysAgo(400))],
        [],
        range: DateRangeFilter.all,
      );

      expect(summary.totalReports, 1);
      expect(summary.totalReportsPrevious, isNull);
      expect(summary.pendingOrOverduePrevious, isNull);
    });
  });

  group('average resolution', () {
    test('runs from the report being submitted to the work completing', () {
      final summary = compute(
        [
          report('a', submitted: daysAgo(10), workOrderId: 'w1'),
          report('b', submitted: daysAgo(9), workOrderId: 'w2'),
        ],
        [
          // 4 days and 2 days: an average of 3.
          workOrder(
            'w1',
            reportIds: ['a'],
            created: daysAgo(9),
            completed: daysAgo(6),
          ),
          workOrder(
            'w2',
            reportIds: ['b'],
            created: daysAgo(8),
            completed: daysAgo(7),
          ),
        ],
      );

      expect(summary.averageResolutionDays, closeTo(3, 0.001));
    });

    test('is unknown when nothing was completed', () {
      final summary = compute([report('a', submitted: daysAgo(3))], []);
      expect(summary.averageResolutionDays, isNull);
    });
  });

  group('completion rate', () {
    test('leaves dismissed reports out of the count', () {
      final summary = compute([
        report('a', submitted: daysAgo(2)),
        report('b', submitted: daysAgo(2), status: ReportStatus.closed),
        report('c', submitted: daysAgo(2), status: ReportStatus.inProgress),
        report('d', submitted: daysAgo(2), status: ReportStatus.rejected),
      ], []);

      // 2 of the 3 that could be completed; the rejection is not counted.
      expect(summary.completionRate, closeTo(2 / 3, 0.001));
    });
  });

  group('pending or overdue', () {
    test('counts reports awaiting review and overdue work orders', () {
      final summary = compute(
        [
          report('a', submitted: daysAgo(1), status: ReportStatus.submitted),
          report('b', submitted: daysAgo(1), status: ReportStatus.underReview),
          report('c', submitted: daysAgo(1), status: ReportStatus.approved),
        ],
        [
          workOrder(
            'w1',
            reportIds: ['c'],
            created: daysAgo(5),
            scheduled: daysAgo(2),
          ),
        ],
      );

      expect(summary.pendingOrOverdue, 3);
    });

    test('recovers the count at the start of the period', () {
      final summary = compute([
        // Waiting at the start, decided since: counted then, not now.
        report(
          'a',
          submitted: daysAgo(40),
          status: ReportStatus.approved,
          reviewed: daysAgo(10),
        ),
        // Still waiting: counted both times.
        report('b', submitted: daysAgo(40), status: ReportStatus.submitted),
        // Submitted after the period began: counted now only.
        report('c', submitted: daysAgo(5), status: ReportStatus.submitted),
      ], []);

      expect(summary.pendingOrOverdue, 2);
      expect(summary.pendingOrOverduePrevious, 2);
    });
  });

  group('charts', () {
    test('monthly volume covers six calendar months, oldest first', () {
      final summary = compute([
        report('a', submitted: DateTime(2026, 9, 3)),
        report('b', submitted: DateTime(2026, 9, 20)),
        report('c', submitted: DateTime(2026, 7, 14)),
        report('d', submitted: DateTime(2026, 3)), // outside the window
      ], []);

      final months = summary.monthlyVolume;
      expect(months, hasLength(6));
      expect(months.first.month, DateTime(2026, 4));
      expect(months.last.month, DateTime(2026, 9));
      expect(months.last.value, 2);
      expect(months[3].value, 1); // July
    });

    test('ranks the five busiest buildings', () {
      final summary = compute([
        for (var i = 0; i < 3; i++)
          report('lib$i', submitted: daysAgo(1), facility: 'Main Library'),
        for (var i = 0; i < 5; i++) report('eng$i', submitted: daysAgo(1)),
        for (final name in ['A', 'B', 'C', 'D'])
          report('x$name', submitted: daysAgo(1), facility: 'Hall $name'),
      ], []);

      final names = summary.byBuilding.map((b) => b.facilityName).toList();
      expect(names, hasLength(5));
      expect(names.take(2), ['Engineering Building', 'Main Library']);
      expect(summary.byBuilding.first.count, 5);
    });

    test('groups this month\'s issues and compares with last month', () {
      final summary = compute([
        report('a', submitted: DateTime(2026, 9, 2)),
        report('b', submitted: DateTime(2026, 9, 5)),
        report(
          'c',
          submitted: DateTime(2026, 9, 6),
          category: DamageCategory.plumbing,
        ),
        // Last month: one electrical at the same building.
        report('d', submitted: DateTime(2026, 8, 20)),
      ], []);

      final top = summary.topIssues;
      expect(top.first.category, DamageCategory.electrical);
      expect(top.first.count, 2);
      expect(top.first.trend, IssueTrend.up);
      expect(top.last.category, DamageCategory.plumbing);
      expect(top.last.trend, IssueTrend.up);
    });
  });
}
