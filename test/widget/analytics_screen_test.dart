import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/analytics/presentation/analytics_export.dart';
import 'package:gsuhub/features/analytics/presentation/analytics_screen.dart';
import 'package:gsuhub/features/reporting/data/models/damage_report.dart';
import 'package:gsuhub/features/work_orders/data/models/work_order.dart';

import '../support/fake_admin_backend.dart';

/// Analytics (Objective 2.C; Figma `61:5086`).
void main() {
  final now = DateTime.now();

  DamageReport report(
    String id, {
    required int daysAgo,
    DamageCategory category = DamageCategory.electrical,
    String facility = 'Engineering Building',
    ReportStatus status = ReportStatus.completed,
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
    workOrderId: workOrderId,
    submittedAt: now.subtract(Duration(days: daysAgo)).toUtc(),
    updatedAt: now.toUtc(),
  );

  WorkOrder completed(String id, String reportId, {required int daysAgo}) =>
      WorkOrder(
        id: id,
        reportIds: [reportId],
        title: 'Repair $id',
        description: 'Seeded for test.',
        category: DamageCategory.electrical,
        priority: PriorityLevel.medium,
        status: WorkOrderStatus.completed,
        assignedPersonnelIds: const ['p1'],
        completedAt: now.subtract(Duration(days: daysAgo)).toUtc(),
        createdBy: 'admin-1',
        createdAt: now.subtract(Duration(days: daysAgo + 1)).toUtc(),
        updatedAt: now.toUtc(),
      );

  Future<void> pump(
    WidgetTester tester, {
    required List<DamageReport> reports,
    List<WorkOrder> workOrders = const [],
    FakeFileDownloadService? downloads,
    Widget? child,
  }) async {
    tester.view
      ..physicalSize = const Size(1800, 3200)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      fakeAdminScope(
        reports: Result.success(reports),
        workOrders: Result.success(workOrders),
        downloads: downloads,
        child: MaterialApp(
          home: Scaffold(body: child ?? const AnalyticsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows figures computed from the data', (tester) async {
    await pump(
      tester,
      reports: [
        report('a', daysAgo: 3, workOrderId: 'w1'),
        report('b', daysAgo: 4, category: DamageCategory.plumbing),
        report('c', daysAgo: 5, facility: 'Main Library'),
        report('old', daysAgo: 120),
      ],
      workOrders: [completed('w1', 'a', daysAgo: 1)],
    );

    expect(find.text('TOTAL REPORTS'), findsOneWidget);
    expect(find.text('3'), findsWidgets); // three in the last 30 days
    expect(find.text('vs last month'), findsOneWidget);
    // Each chart is present and fed.
    expect(find.text('Monthly Report Volume'), findsOneWidget);
    expect(find.text('Reports by Damage Type'), findsOneWidget);
    expect(find.text('ENGINEERING BUILDING'), findsOneWidget);
    expect(find.text('Top Reported Issues This Month'), findsOneWidget);
    expect(find.text('VIEW DETAILED REPORT'), findsOneWidget);
  });

  testWidgets('says so rather than drawing empty charts', (tester) async {
    await pump(tester, reports: const []);

    expect(find.text('No reports in the last 30 days.'), findsNWidgets(2));
    expect(
      find.text('No work orders completed in the last six months.'),
      findsOneWidget,
    );
    expect(
      find.text('No reports have been submitted this month yet.'),
      findsOneWidget,
    );
  });

  testWidgets('exports the period as a CSV through the download service', (
    tester,
  ) async {
    final downloads = FakeFileDownloadService();
    await pump(
      tester,
      reports: [report('rep-0001', daysAgo: 2)],
      downloads: downloads,
      child: Consumer(
        builder: (context, ref, _) => TextButton(
          onPressed: () =>
              ref.read(analyticsExportControllerProvider).export(context),
          child: const Text('Export'),
        ),
      ),
    );

    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();

    final file = downloads.saved.single;
    expect(file.fileName, startsWith('gsuhub-analytics-last-30-days-'));
    expect(file.contents, contains('#REP-0001'));
    expect(find.textContaining('Exported 1 report'), findsOneWidget);
  });
}
