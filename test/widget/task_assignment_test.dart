import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/damage_categories.dart';
import 'package:gsuhub/core/enums/account_status.dart';
import 'package:gsuhub/core/enums/priority_level.dart';
import 'package:gsuhub/core/enums/report_status.dart';
import 'package:gsuhub/core/errors/failures.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/reporting/data/models/damage_report.dart';
import 'package:gsuhub/features/user_management/data/models/app_user.dart';
import 'package:gsuhub/features/work_orders/presentation/task_assignment_screen.dart';

import '../support/fake_admin_backend.dart';

/// Task Assignment (Objective 2.B).
void main() {
  DamageReport approved({
    required String id,
    required String title,
    DamageCategory? category = DamageCategory.electrical,
    ReportStatus status = ReportStatus.approved,
    String? workOrderId,
  }) => DamageReport(
    id: id,
    reporterId: 'faculty-1',
    reporterName: 'Maria Santos',
    title: title,
    description: 'Seeded for test.',
    category: category,
    facilityName: 'Engineering Building',
    requestorPriority: PriorityLevel.high,
    status: status,
    workOrderId: workOrderId,
    submittedAt: DateTime.utc(2026, 9, 18),
    updatedAt: DateTime.utc(2026, 9, 18),
  );

  final electrician = fakePersonnel(id: 'p1', fullName: 'Marcus Wright');
  final plumber = fakePersonnel(
    id: 'p2',
    fullName: 'Juan Luna',
    specialization: DamageCategory.plumbing,
  );
  final inactive = fakePersonnel(
    id: 'p3',
    fullName: 'Elena Santillan',
    accountStatus: AccountStatus.inactive,
  );

  Future<FakeWorkOrderRepository> pump(
    WidgetTester tester, {
    required List<DamageReport> reports,
    required List<AppUser> personnel,
    Result<String> assignResult = const Result.success('wo-new'),
    String? preselected,
  }) async {
    tester.view
      ..physicalSize = const Size(1600, 2000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final workOrders = FakeWorkOrderRepository(
      const Result.success([]),
      assignResult: assignResult,
    );

    await tester.pumpWidget(
      fakeAdminScope(
        reports: Result.success(reports),
        personnel: Result.success(personnel),
        workOrderRepository: workOrders,
        child: MaterialApp(
          home: Scaffold(
            body: TaskAssignmentScreen(preselectedReportId: preselected),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return workOrders;
  }

  group('queue', () {
    testWidgets('lists only approved reports with no work order', (
      tester,
    ) async {
      await pump(
        tester,
        reports: [
          approved(id: 'rep-1', title: 'Flickering Lights'),
          approved(
            id: 'rep-2',
            title: 'Still under review',
            status: ReportStatus.underReview,
          ),
          approved(
            id: 'rep-3',
            title: 'Already assigned',
            status: ReportStatus.assigned,
            workOrderId: 'wo-1',
          ),
        ],
        personnel: [electrician],
      );

      expect(find.text('Flickering Lights'), findsOneWidget);
      expect(find.text('Still under review'), findsNothing);
      expect(find.text('Already assigned'), findsNothing);
      expect(find.text('1 PENDING'), findsOneWidget);
    });

    testWidgets('says why the queue is empty', (tester) async {
      await pump(tester, reports: [], personnel: [electrician]);

      expect(
        find.textContaining('once they have been approved'),
        findsOneWidget,
      );
    });
  });

  group('personnel panel', () {
    testWidgets('shows workload and account status', (tester) async {
      await pump(
        tester,
        reports: [approved(id: 'rep-1', title: 'Flickering Lights')],
        personnel: [
          fakePersonnel(
            id: 'p1',
            fullName: 'Marcus Wright',
            activeTaskCount: 2,
          ),
          inactive,
        ],
      );

      expect(find.text('Marcus Wright'), findsOneWidget);
      expect(find.text('2 active'), findsOneWidget);
      expect(find.text('ACTIVE'), findsOneWidget);
      expect(find.text('INACTIVE'), findsOneWidget);
    });

    testWidgets('ranks the matching trade first without hiding the rest', (
      tester,
    ) async {
      // The administrator keeps the final say — the plumber stays on
      // screen for an electrical job, just not at the top.
      await pump(
        tester,
        reports: [approved(id: 'rep-1', title: 'Flickering Lights')],
        personnel: [plumber, electrician],
      );

      await tester.tap(find.text('Assign').first);
      await tester.pumpAndSettle();

      final names = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .whereType<String>()
          .toList();
      expect(
        names.indexOf('Marcus Wright'),
        lessThan(names.indexOf('Juan Luna')),
      );
    });

    testWidgets('cannot assign before a report is chosen', (tester) async {
      await pump(
        tester,
        reports: [approved(id: 'rep-1', title: 'Flickering Lights')],
        personnel: [electrician],
      );

      // The row's Assign button — the card's is the first in the tree.
      final rowAssign = find.widgetWithText(OutlinedButton, 'Assign');
      expect(tester.widget<OutlinedButton>(rowAssign).onPressed, isNull);
    });

    testWidgets('an inactive account can never be assigned', (tester) async {
      await pump(
        tester,
        reports: [approved(id: 'rep-1', title: 'Flickering Lights')],
        personnel: [inactive],
      );

      await tester.tap(find.text('Assign').first); // select the report
      await tester.pumpAndSettle();

      final rowAssign = find.widgetWithText(OutlinedButton, 'Assign');
      expect(tester.widget<OutlinedButton>(rowAssign).onPressed, isNull);
    });
  });

  group('assigning', () {
    Future<void> selectAndAssign(WidgetTester tester) async {
      await tester.tap(find.text('Assign').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Assign'));
      await tester.pumpAndSettle();
    }

    testWidgets('confirms the pairing before writing anything', (tester) async {
      final repository = await pump(
        tester,
        reports: [approved(id: 'rep-1', title: 'Flickering Lights')],
        personnel: [electrician],
      );

      await selectAndAssign(tester);

      expect(find.text('Assign this report'), findsOneWidget);
      expect(find.text('No target completion date'), findsOneWidget);
      // Nothing is written until the dialog is confirmed.
      expect(repository.assignments, isEmpty);
    });

    testWidgets('passes the report and person to the repository', (
      tester,
    ) async {
      final repository = await pump(
        tester,
        reports: [approved(id: 'rep-1', title: 'Flickering Lights')],
        personnel: [electrician],
      );

      await selectAndAssign(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Assign'));
      await tester.pumpAndSettle();

      expect(repository.assignments, hasLength(1));
      expect(repository.assignments.single.reportId, 'rep-1');
      expect(repository.assignments.single.personnelId, 'p1');
      // The date is optional and was not set.
      expect(repository.assignments.single.scheduledFor, isNull);
      expect(find.textContaining('assigned to Marcus Wright'), findsOneWidget);
    });

    testWidgets('warns when the trade does not match, without blocking', (
      tester,
    ) async {
      final repository = await pump(
        tester,
        reports: [approved(id: 'rep-1', title: 'Flickering Lights')],
        personnel: [plumber],
      );

      await selectAndAssign(tester);

      expect(find.textContaining('usually handled by a'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Assign'));
      await tester.pumpAndSettle();

      expect(repository.assignments, hasLength(1));
    });

    testWidgets('surfaces a refusal from the repository', (tester) async {
      final repository = await pump(
        tester,
        reports: [approved(id: 'rep-1', title: 'Unclassified', category: null)],
        personnel: [electrician],
        assignResult: const Result.failure(
          ValidationFailure(
            'This report has no damage category yet, so no work order can '
            'be raised for it. It must be classified first.',
          ),
        ),
      );

      await selectAndAssign(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Assign'));
      await tester.pumpAndSettle();

      expect(repository.assignments, hasLength(1));
      expect(find.textContaining('no damage category'), findsOneWidget);
    });

    testWidgets('arrives with a report already selected from the table', (
      tester,
    ) async {
      await pump(
        tester,
        reports: [
          approved(id: 'rep-1', title: 'Flickering Lights'),
          approved(id: 'rep-2', title: 'Leaking Pipe'),
        ],
        personnel: [electrician],
        preselected: 'rep-2',
      );

      // Selecting is what enables the personnel row's Assign button.
      final rowAssign = find.widgetWithText(OutlinedButton, 'Assign');
      expect(tester.widget<OutlinedButton>(rowAssign).onPressed, isNotNull);
      expect(find.text('Selected — choose personnel'), findsOneWidget);
    });
  });
}
