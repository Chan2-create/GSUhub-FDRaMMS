import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/core/constants/firestore_paths.dart';
import 'package:gsuhub/core/enums/work_order_status.dart';
import 'package:gsuhub/core/routing/route_paths.dart';
import 'package:gsuhub/features/scanning/domain/personnel_scan_resolver.dart';

import '../support/fake_personnel_app.dart';
import '../support/fake_requestor_app.dart' show currentPath;

/// The personnel app (Objective 5.A–5.C), end to end over an in-memory
/// Firestore: what the technician sees, and what each action writes.
void main() {
  group('home (5.A)', () {
    testWidgets('greets the technician with the day and their work', (
      tester,
    ) async {
      final app = PersonnelHarness();
      await app.seedJob();
      await app.pump(tester);

      expect(find.textContaining('Marcus Wright'), findsOneWidget);
      expect(find.text("Today's Tasks"), findsOneWidget);
      expect(find.text('Replace the ballast'), findsOneWidget);
      expect(find.text('My Work Orders'), findsOneWidget);
      expect(find.text('Flickering lights'), findsWidgets);
    });

    testWidgets('ticking a task on pending work starts the work', (
      tester,
    ) async {
      final app = PersonnelHarness();
      await app.seedJob();
      await app.pump(tester);

      await tester.tap(find.bySemanticsLabel('Mark as done'));
      await tester.pumpAndSettle();

      final task = await app.read(FirestorePaths.tasks, 'task-1');
      expect(task['status'], 'completed');
      expect(await app.workOrderStatus(), WorkOrderStatus.inProgress.id);
      expect(find.bySemanticsLabel('Mark as not done'), findsOneWidget);
    });

    testWidgets('the tabs and the bell lead where they say', (tester) async {
      final app = PersonnelHarness();
      await app.seedJob();
      await app.pump(tester);

      await tester.tap(find.text('Tasks').last);
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.personnelTasks);
      expect(find.text('Today'), findsOneWidget);

      await tester.tap(find.text('Materials').last);
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.personnelMaterials);
      expect(find.text('Materials & Tools'), findsOneWidget);

      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.personnelAlerts);
    });

    testWidgets('a work order card opens the work order', (tester) async {
      final app = PersonnelHarness();
      await app.seedJob();
      await app.pump(tester);

      await tester.tap(find.text('View all'));
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.personnelWorkOrders);

      await tester.tap(find.text('Flickering lights').first);
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.personnelWorkOrderFor('wo-1'));
      expect(find.text('Start work'), findsOneWidget);
    });
  });

  group('work order (5.B)', () {
    testWidgets('Start work moves it to in progress', (tester) async {
      final app = PersonnelHarness();
      await app.seedJob();
      await app.pump(tester, start: RoutePaths.personnelWorkOrderFor('wo-1'));

      await tester.tap(find.text('Start work'));
      await tester.pumpAndSettle();

      expect(await app.workOrderStatus(), WorkOrderStatus.inProgress.id);
      expect(
        find.text('Work started. The requestor has been told.'),
        findsOneWidget,
      );
      expect(find.text('Start work'), findsNothing);
    });

    testWidgets('Mark Complete asks for notes and a photo first', (
      tester,
    ) async {
      final app = PersonnelHarness();
      await app.seedJob(status: WorkOrderStatus.inProgress);
      await app.pump(tester, start: RoutePaths.personnelWorkOrderFor('wo-1'));

      await reveal(tester, find.text('Mark Complete'));
      await tester.tap(find.text('Mark Complete'));
      await tester.pumpAndSettle();

      expect(find.text('Describe the work that was done.'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Enter completion notes here...'),
        'Replaced the ballast.',
      );
      await reveal(tester, find.text('Mark Complete'));
      await tester.tap(find.text('Mark Complete'));
      await tester.pumpAndSettle();
      expect(
        find.text('Add at least one photo of the finished work.'),
        findsOneWidget,
      );
      expect(find.text('Mark complete?'), findsNothing);
      expect(await app.workOrderStatus(), WorkOrderStatus.inProgress.id);
    });

    testWidgets('submitting the report sends the work for sign-off', (
      tester,
    ) async {
      final app = PersonnelHarness();
      await app.seedJob(status: WorkOrderStatus.inProgress);
      await app.pump(tester, start: RoutePaths.personnelWorkOrderFor('wo-1'));

      await reveal(tester, find.text('Mark Complete'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Enter completion notes here...'),
        'Replaced the ballast and tested every tube.',
      );
      await tester.tap(find.bySemanticsLabel('Add a photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose from gallery'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark Complete'));
      await tester.pumpAndSettle();

      expect(find.text('Mark complete?'), findsOneWidget);
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      expect(await app.workOrderStatus(), WorkOrderStatus.forReview.id);
      expect(await app.data.count(FirestorePaths.accomplishmentReports), 1);
      expect(
        app.storage.uploadedPaths.single,
        startsWith('accomplishment_reports/'),
      );
      expect(
        find.text('Report submitted. GSU will review it and sign it off.'),
        findsOneWidget,
      );
    });
  });

  group('scanning (5.C)', () {
    testWidgets('a scanned material is recorded on the work order', (
      tester,
    ) async {
      final app = PersonnelHarness()..nextScan = 'INV-INV-LED';
      await app.seedJob(status: WorkOrderStatus.inProgress);
      await app.pump(tester);

      await tester.tap(find.byTooltip('Scan a code'));
      await tester.pumpAndSettle();
      expect(currentPath(tester), RoutePaths.personnelScanning);
      expect(find.text('LED Bulbs'), findsWidgets);

      await tester.tap(find.text('Record use on a work order'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Work order'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Flickering lights').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Quantity used'),
        '3',
      );
      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();

      final used = await app.data.firestore
          .collection(FirestorePaths.workOrders)
          .doc('wo-1')
          .collection(FirestorePaths.materialsUsed)
          .doc('inv-led')
          .get();
      expect(used.data()?['quantityUsed'], 3);
    });

    testWidgets('a scanned tool is borrowed, then returned', (tester) async {
      final app = PersonnelHarness()..nextScan = 'TOOL-TL-0001';
      await app.seedJob(status: WorkOrderStatus.inProgress);
      await app.pump(tester);

      await tester.tap(find.byTooltip('Scan a code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Borrow'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Borrow').last);
      await tester.pumpAndSettle();

      expect(
        (await app.read(FirestorePaths.tools, 'tool-1'))['status'],
        'borrowed',
      );
      // The page reads the tool again: it is now the technician's to return.
      expect(find.text('Borrow'), findsNothing);

      // Lets the "Borrowed" message go; it sits over the sheet's button.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Return'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Return').last);
      await tester.pumpAndSettle();

      expect(
        (await app.read(FirestorePaths.tools, 'tool-1'))['status'],
        'available',
      );
      expect(find.text('Borrow'), findsOneWidget);
    });

    testWidgets('an unknown code says so', (tester) async {
      final app = PersonnelHarness()..nextScan = 'HELLO';
      await app.seedJob();
      await app.pump(tester);

      await tester.tap(find.byTooltip('Scan a code'));
      await tester.pumpAndSettle();

      expect(find.text(PersonnelScanResolver.unregistered), findsOneWidget);
      expect(find.text('Scan again'), findsOneWidget);
    });

    testWidgets('backing out of the scanner stays put', (tester) async {
      final app = PersonnelHarness();
      await app.seedJob();
      await app.pump(tester);

      await tester.tap(find.byTooltip('Scan a code'));
      await tester.pumpAndSettle();

      expect(app.scans, 1);
      expect(currentPath(tester), RoutePaths.personnelDashboard);
    });
  });
}

/// Scrolls [finder] to the middle of the page, clear of the bottom bar.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
}
