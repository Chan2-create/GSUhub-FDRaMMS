import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/core/utils/result.dart';
import 'package:gsuhub/features/work_orders/presentation/work_order_controller.dart';
import 'package:gsuhub/features/work_orders/presentation/work_orders_screen.dart';

import '../support/fake_firestore_repositories.dart';
import '../support/fake_personnel_app.dart';
import '../support/fake_requestor_app.dart' show currentPath;

/// The console's work-order page (Objective 5.A–5.B): the administrator
/// adds tasks, and signs off or sends back the technician's report.
void main() {
  Future<PersonnelHarness> console(
    WidgetTester tester, {
    WorkOrderStatus status = WorkOrderStatus.pending,
    bool submitted = false,
    String? start,
  }) async {
    final app = PersonnelHarness(signedIn: fakeAdministrator);
    await app.seedJob(status: status);
    await app.data.addPersonnel(fakeAdministrator.uid, role: UserRole.admin);
    if (submitted) {
      final filed = await app.data.accomplishments.submit(
        reportId: 'acc-1',
        workOrderId: 'wo-1',
        completionNotes: 'Replaced the ballast and tested every tube.',
        photoUrls: const ['https://storage.test/after.jpg'],
        materialsUsed: const [],
        actor: FirestoreHarness.technician,
      );
      expect(filed.isSuccess, isTrue);
    }
    await app.pump(
      tester,
      start: start ?? RoutePaths.adminWorkOrderDetailFor('wo-1'),
      size: const Size(1440, 1000),
    );
    return app;
  }

  testWidgets('the administrator adds a task, and the technician is told', (
    tester,
  ) async {
    final app = await console(tester);
    final noticesBefore = (await app.data.notifications()).length;

    await tester.enterText(
      find.widgetWithText(TextField, 'Task'),
      'Replace the switch cover',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Add task'));
    await tester.tap(find.text('Add task'));
    await tester.pumpAndSettle();

    expect(await app.data.count(FirestorePaths.tasks), 2);
    expect(find.text('Replace the switch cover'), findsOneWidget);
    expect(
      find.text('Task added. The technician has been told.'),
      findsOneWidget,
    );
    final notices = await app.data.notifications();
    expect(notices, hasLength(noticesBefore + 1));
    expect(
      notices.where((notice) => notice['recipientId'] == 'personnel-1'),
      isNotEmpty,
    );
  });

  testWidgets('signing off the report completes the work order', (
    tester,
  ) async {
    final app = await console(
      tester,
      status: WorkOrderStatus.inProgress,
      submitted: true,
    );
    expect(find.text('Accomplishment report'), findsOneWidget);

    await tester.ensureVisible(find.text('Approve and sign off'));
    await tester.tap(find.text('Approve and sign off'));
    await tester.pumpAndSettle();

    expect(await app.workOrderStatus(), WorkOrderStatus.completed.id);
    final report = await app.read(
      FirestorePaths.accomplishmentReports,
      'acc-1',
    );
    expect(report['reviewedBy'], fakeAdministrator.uid);
    expect(
      find.text('Signed off. The work order is completed.'),
      findsOneWidget,
    );
    expect(find.text('Approve and sign off'), findsNothing);
  });

  testWidgets('sending it back reopens the work, with the note', (
    tester,
  ) async {
    final app = await console(
      tester,
      status: WorkOrderStatus.inProgress,
      submitted: true,
    );

    await tester.ensureVisible(find.text('Send back for rework'));
    await tester.tap(find.text('Send back for rework'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'What still needs doing'),
      'Two clips on the next panel are loose too.',
    );
    await tester.pump();
    await tester.tap(find.text('Send back'));
    await tester.pumpAndSettle();

    final workOrder = await app.read(FirestorePaths.workOrders, 'wo-1');
    expect(workOrder['status'], WorkOrderStatus.inProgress.id);
    expect(
      workOrder['adminNotes'],
      'Two clips on the next panel are loose too.',
    );
    expect(
      find.text('Sent back. The technician has been told.'),
      findsOneWidget,
    );
  });

  testWidgets('the administrator reassigns open work, and everyone is told', (
    tester,
  ) async {
    final app = await console(tester);
    await app.data.addPersonnel('personnel-2', fullName: 'Juan Luna');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.widgetWithText(TextButton, 'Reassign'));
    await tester.tap(find.widgetWithText(TextButton, 'Reassign'));
    await tester.pumpAndSettle();
    expect(find.text('Reassign this work order'), findsOneWidget);

    await tester.tap(find.text('Juan Luna'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reassign'));
    await tester.pumpAndSettle();

    expect(
      find.text('Reassigned to Juan Luna. They have been told.'),
      findsOneWidget,
    );
    final workOrder = await app.read(FirestorePaths.workOrders, 'wo-1');
    expect(workOrder['assignedPersonnelIds'], ['personnel-2']);
    final task = await app.read(FirestorePaths.tasks, 'task-1');
    expect(
      task['assignedTo'],
      'personnel-2',
      reason: "the work's task goes too",
    );
    final notices = await app.data.notifications();
    expect(
      notices.where(
        (n) =>
            n['recipientId'] == 'personnel-2' && n['title'] == 'New work order',
      ),
      isNotEmpty,
    );
    expect(
      notices.where(
        (n) =>
            n['recipientId'] == 'personnel-1' &&
            n['title'] == 'Work reassigned',
      ),
      isNotEmpty,
    );
  });

  testWidgets('work sent for review cannot be reassigned', (tester) async {
    await console(tester, status: WorkOrderStatus.inProgress, submitted: true);

    expect(find.widgetWithText(TextButton, 'Reassign'), findsNothing);
  });

  // The board cannot skip the sign-off (Objective 7.B; found testing on
  // live, 2026-10-20).
  group('the board and the sign-off', () {
    testWidgets('work waiting for sign-off opens at its report to review', (
      tester,
    ) async {
      final app = await console(
        tester,
        status: WorkOrderStatus.inProgress,
        submitted: true,
        start: RoutePaths.adminWorkOrders,
      );
      expect(await app.workOrderStatus(), WorkOrderStatus.forReview.id);

      await tester.tap(find.byTooltip('Review work order'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review the accomplishment report'));
      await tester.pumpAndSettle();

      expect(currentPath(tester), RoutePaths.adminWorkOrderDetailFor('wo-1'));
      expect(find.text('Approve and sign off'), findsOneWidget);
      expect(
        await app.workOrderStatus(),
        WorkOrderStatus.forReview.id,
        reason: 'nothing moved on the way',
      );
    });

    testWidgets('work in progress has no move on the board', (tester) async {
      await console(
        tester,
        status: WorkOrderStatus.inProgress,
        start: RoutePaths.adminWorkOrders,
      );

      expect(find.byTooltip('Move work order'), findsNothing);
      expect(find.byTooltip('Review work order'), findsNothing);
    });

    testWidgets('a drop on For Review or Completed is refused, with why', (
      tester,
    ) async {
      final app = await console(
        tester,
        status: WorkOrderStatus.inProgress,
        start: RoutePaths.adminWorkOrders,
      );
      final context = tester.element(find.byType(WorkOrdersScreen));
      final workOrder = switch (await app.data.workOrders.getById('wo-1')) {
        Success(:final value) => value,
        Error(:final failure) => fail(failure.message),
      };
      final controller = ProviderScope.containerOf(context)
          .read(workOrderControllerProvider);

      await controller.move(
        context: context,
        workOrder: workOrder,
        to: WorkOrderStatus.forReview,
      );
      await tester.pump();
      expect(
        find.text(
          'Work goes to For Review when its technician submits the '
          'accomplishment report.',
        ),
        findsOneWidget,
      );

      await controller.move(
        context: context,
        workOrder: workOrder,
        to: WorkOrderStatus.completed,
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Sign off the accomplishment report'),
        findsOneWidget,
      );
      expect(await app.workOrderStatus(), WorkOrderStatus.inProgress.id);
    });
  });
}
