import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/user_role.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/routing/route_paths.dart';

import '../support/fake_firestore_repositories.dart';
import '../support/fake_personnel_app.dart';

/// The console's work-order page (Objective 5.A–5.B): the administrator
/// adds tasks, and signs off or sends back the technician's report.
void main() {
  Future<PersonnelHarness> console(
    WidgetTester tester, {
    WorkOrderStatus status = WorkOrderStatus.pending,
    bool submitted = false,
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
      start: RoutePaths.adminWorkOrderDetailFor('wo-1'),
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
}
